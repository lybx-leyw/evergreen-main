/// Chrome DevTools Protocol (CDP) Network 域客户端。
///
/// 通过 `--remote-debugging-port` 连接到 WebView2 的远程调试端点，
/// 发送 `Network.enable` 后接收**全部**网络请求事件——
/// 覆盖 fetch/XHR、页面导航、子资源（img/css/js/font）、WebSocket、重定向等。
///
/// 参考：https://chromedevtools.github.io/devtools-protocol/tot/Network/
library cdp_network_client;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../workflow/scraper_workflow.dart';

// ═══════ CDP Network 事件类型 ═══════

/// CDP 网络事件（已解析为 HttpRequestLog）。
class CdpNetworkEvent {
  final String eventType; // requestWillBeSent / responseReceived / loadingFinished / loadingFailed
  final HttpRequestLog log;
  final int? statusCode; // 来自 responseReceived
  final String? errorText; // 来自 loadingFailed
  final double? encodedDataLength; // 来自 loadingFinished

  const CdpNetworkEvent({
    required this.eventType,
    required this.log,
    this.statusCode,
    this.errorText,
    this.encodedDataLength,
  });
}

// ═══════ CdpNetworkClient ═══════

/// CDP Network 域捕获客户端。
///
/// 使用方式：
/// ```dart
/// final client = CdpNetworkClient(debugPort: 9222);
/// client.networkEvents.listen((event) {
///   workflow.addLog(event.log);
/// });
/// await client.connect();
/// ```
class CdpNetworkClient {
  final int debugPort;
  final Duration _connectTimeout;
  final Duration _pollInterval;

  WebSocket? _ws;
  int _msgId = 0;
  bool _disposed = false;

  /// 等待中命令的 id → Completer（修复 send-and-forget，使 [connect] 能确认 CDP 命令生效）。
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};

  /// requestId → {url, method, mimeType}，用于在 loadingFinished 时判断是否为 JSON 响应。
  final Map<String, Map<String, String>> _reqMeta = {};

  final _networkEventController = StreamController<CdpNetworkEvent>.broadcast();
  final _statusController = StreamController<String>.broadcast();

  /// CDP 网络事件流（全类型）。
  Stream<CdpNetworkEvent> get networkEvents => _networkEventController.stream;

  /// 状态日志流（连接/错误/降级）。
  Stream<String> get statusLog => _statusController.stream;

  CdpNetworkClient({
    this.debugPort = 9222,
    Duration connectTimeout = const Duration(seconds: 5),
    Duration pollInterval = const Duration(milliseconds: 500),
  })  : _connectTimeout = connectTimeout,
        _pollInterval = pollInterval;

  /// 连接到 CDP 端点并启用 Network domain。
  ///
  /// 返回 `true` 表示成功，`false` 表示无法连接（调用方应降级到 JS 方案）。
  Future<bool> connect() async {
    if (_disposed) return false;

    try {
      // 步骤 1：发现可调试目标
      final wsUrl = await _discoverTarget(_connectTimeout);
      if (wsUrl == null) {
        _log('未找到可调试目标（可能 WebView 尚未启动）');
        return false;
      }
      _log('发现目标 → $wsUrl');

      // 步骤 2：建立 WebSocket 连接
      _ws = await WebSocket.connect(wsUrl).timeout(_connectTimeout);
      _log('CDP WebSocket 已连接');

      // 步骤 3：先启动监听，再发命令——[_sendCommand] 现在按 id 等待响应，
      // 若监听器尚未就绪，命令响应会被丢弃导致超时（修复原 send-and-forget 遗留坑）。
      _listen();

      // 启用 Network domain（含 POST body 捕获）
      await _sendCommand('Network.enable', {
        'maxTotalBufferSize': 10000000,
        'maxResourceBufferSize': 5000000,
        'maxPostDataSize': 65536, // 64KB POST body
      });

      // 同时启用 Page domain（获取 frame navigations）
      await _sendCommand('Page.enable', {});

      _log('Network.enable + Page.enable 已发送 ✅');
      return true;
    } on TimeoutException {
      _log('CDP 连接超时（${_connectTimeout.inSeconds}s）');
      return false;
    } on SocketException catch (e) {
      _log('CDP Socket 错误: $e');
      return false;
    } on WebSocketException catch (e) {
      _log('CDP WebSocket 错误: $e');
      return false;
    } catch (e) {
      _log('CDP 连接异常: $e');
      return false;
    }
  }

  /// 发现 WebView2 调试目标。
  ///
  /// 轮询 `http://localhost:{port}/json` 直到找到 page 类型目标。
  Future<String?> _discoverTarget(Duration timeout) async {
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      try {
        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 2);
        try {
          final request =
              await client.getUrl(Uri.parse('http://127.0.0.1:$debugPort/json'));
          final response = await request.close().timeout(const Duration(seconds: 2));
          if (response.statusCode == 200) {
            final body = await response.transform(utf8.decoder).join();
            final List<dynamic> targets = jsonDecode(body) as List<dynamic>;

            for (final t in targets) {
              if (t is Map<String, dynamic> &&
                  t['type'] == 'page' &&
                  t['webSocketDebuggerUrl'] != null) {
                client.close();
                return t['webSocketDebuggerUrl'] as String;
              }
            }
            _log('json 端点返回 ${targets.length} 个目标，但无 page 类型');
          }
        } finally {
          client.close();
        }
      } on SocketException {
        // 端口尚未开放，等待后重试
      } on TimeoutException {
        // 请求超时，重试
      } catch (e) {
        _log('目标发现异常: $e');
      }

      await Future.delayed(_pollInterval);
    }

    return null;
  }

  /// 发送 CDP 命令并等待其响应（修复原 send-and-forget：现在真正按 id 匹配等待，
  /// 命令失败（含 CDP `error` 字段）会抛异常，调用方据此清晰降级）。
  Future<Map<String, dynamic>> _sendCommand(
      String method, Map<String, dynamic> params) async {
    if (_ws == null) throw StateError('CDP 未连接');

    final id = ++_msgId;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;

    final msg = jsonEncode({
      'id': id,
      'method': method,
      'params': params,
    });
    _ws!.add(msg);

    try {
      final resp = await completer.future.timeout(const Duration(seconds: 5));
      if (resp.containsKey('error')) {
        final err = resp['error'];
        final msgText = err is Map ? (err['message'] ?? err.toString()) : err.toString();
        throw Exception('CDP $method 失败: $msgText');
      }
      return resp;
    } on TimeoutException {
      _pending.remove(id);
      throw Exception('CDP $method 响应超时');
    }
  }

  /// 持续监听 CDP 事件。
  void _listen() {
    if (_ws == null) return;

    StringBuffer? _buffer;

    _ws!.listen(
      (data) {
        if (_disposed) return;

        try {
          String raw;
          if (data is String) {
            raw = data;
          } else if (data is List<int>) {
            // WebSocket 可能返回字节（CDP 总是 UTF-8 文本，防御性处理）
            raw = utf8.decode(data);
          } else {
            return;
          }

          // CDP 消息可能被 TCP 分片——用换行符拼接
          // （实际上 CDP 通过 WebSocket 帧确保消息完整性，但保留拼接逻辑）
          if (_buffer != null) {
            _buffer!.write(raw);
            raw = _buffer.toString();
            _buffer = null;
          }

          // 尝试解析 JSON（可能包含多条以 \n 分隔的消息）
          for (final line in raw.split('\n')) {
            final trimmed = line.trim();
            if (trimmed.isEmpty) continue;

            try {
              final map = jsonDecode(trimmed) as Map<String, dynamic>;
              _routeMessage(map);
            } catch (_) {
              // 如果解析失败，可能是分片消息，缓存起来
              _buffer = StringBuffer(trimmed);
            }
          }
        } catch (e) {
          _log('CDP 数据处理异常: $e');
        }
      },
      onError: (e) {
        _log('CDP WebSocket 错误: $e');
        _emitStatus('DISCONNECTED');
      },
      onDone: () {
        _log('CDP WebSocket 已关闭');
        _emitStatus('DISCONNECTED');
      },
      cancelOnError: false,
    );
  }

  /// 路由单条 CDP 消息：命令响应（含 id、无 method）走 [_pending] 完成器；
  /// 事件（含 method）走 [_handleMessage]。
  void _routeMessage(Map<String, dynamic> map) {
    if (map['method'] == null && map['id'] != null) {
      final id = map['id'] as int;
      final c = _pending.remove(id);
      if (c != null && !c.isCompleted) c.complete(map);
      return;
    }
    _handleMessage(map);
  }

  /// 处理单条 CDP 消息。
  void _handleMessage(Map<String, dynamic> map) {
    final method = map['method'] as String?;
    final params = map['params'] as Map<String, dynamic>?;

    if (method == null || params == null) return; // 命令响应，忽略

    switch (method) {
      case 'Network.requestWillBeSent':
        _onRequestWillBeSent(params);
        break;
      case 'Network.responseReceived':
        _onResponseReceived(params);
        break;
      case 'Network.loadingFinished':
        _onLoadingFinished(params);
        break;
      case 'Network.loadingFailed':
        _onLoadingFailed(params);
        break;
      case 'Network.webSocketCreated':
        _onWebSocketCreated(params);
        break;
      case 'Network.webSocketFrameSent':
      case 'Network.webSocketFrameReceived':
        // WebSocket 帧——也当请求日志捕获
        _onWebSocketFrame(method, params);
        break;
      case 'Page.frameNavigated':
        _onFrameNavigated(params);
        break;
    }
  }

  // ── CDP 事件处理器 ──────────────────────────────────────

  void _onRequestWillBeSent(Map<String, dynamic> params) {
    final request = params['request'] as Map<String, dynamic>?;
    if (request == null) return;

    final url = request['url'] as String? ?? '';
    if (url.isEmpty) return;
    if (url.startsWith('data:')) return; // 跳过 data: URI

    final requestId = params['requestId'] as String? ?? '';
    final method = request['method'] as String? ?? 'GET';
    final headers = <String, String>{};
    final rawHeaders = request['headers'] as Map<String, dynamic>?;
    if (rawHeaders != null) {
      rawHeaders.forEach((k, v) => headers[k] = v.toString());
    }

    String? body;
    if (request['hasPostData'] == true && request['postData'] != null) {
      body = request['postData'] as String?;
      if (body != null && body.length > 65536) {
        body = '${body.substring(0, 65536)}... (truncated at 64KB)';
      }
    }

    final type = params['type'] as String? ?? ''; // Document / Fetch / XHR / Script / etc.
    final initiator = params['initiator'] as Map<String, dynamic>?;
    final initiatorType = initiator?['type'] as String? ?? '';

    // wallTime 是 epoch 毫秒
    final wallTime = (params['wallTime'] as num?)?.toDouble() ?? 0;
    final timestamp = wallTime > 0
        ? DateTime.fromMillisecondsSinceEpoch((wallTime * 1000).round())
        : DateTime.now();

    final log = HttpRequestLog(
      timestamp: timestamp,
      method: method.toUpperCase(),
      url: url,
      headers: headers,
      body: body,
      // P2-2：资源类型结构化透传（Document/Fetch/XHR/Script…）
      resourceType: type.isEmpty ? null : type,
    );

    if (requestId.isNotEmpty) {
      _reqMeta[requestId] = {'url': url, 'method': method.toUpperCase(), 'mimeType': ''};
    }

      _emitEvent(CdpNetworkEvent(
        eventType: 'requestWillBeSent',
        log: log,
      ));
  }

  void _onResponseReceived(Map<String, dynamic> params) {
    final response = params['response'] as Map<String, dynamic>?;
    if (response == null) return;

    final requestId = params['requestId'] as String? ?? '';
    final url = response['url'] as String? ?? '';
    if (url.isEmpty || url.startsWith('data:')) return;

    final statusCode = response['status'] as int?;
    final mimeType = response['mimeType'] as String? ?? '';

    // P2-2：响应头结构化透传（Set-Cookie 登录态 / Content-Type 类型 /
    // WWW-Authenticate 认证质询等关键头进日志）
    final respHeaders = <String, String>{};
    final rawRespHeaders = response['headers'] as Map<String, dynamic>?;
    if (rawRespHeaders != null) {
      rawRespHeaders.forEach((k, v) => respHeaders[k] = v.toString());
    }

    // 记录 mimeType，便于 loadingFinished 时判断是否为 JSON 响应
    // （P2-2：顺带记录 statusCode，让 responseBody 日志也携带状态码）
    final meta = _reqMeta[requestId];
    if (meta != null || requestId.isNotEmpty) {
      _reqMeta[requestId] = {
        'url': url,
        'method': meta?['method'] ?? 'RESPONSE',
        'mimeType': mimeType,
        if (statusCode != null) 'statusCode': statusCode.toString(),
      };
    }

    final log = HttpRequestLog(
      timestamp: DateTime.now(),
      method: 'RESPONSE',
      url: url,
      // P2-2：状态码不再只拼进 URL 文本——结构化字段进日志，AI 可区分
      // 200/401/403 并识别 Set-Cookie 登录态
      statusCode: statusCode,
      responseHeaders: respHeaders.isEmpty ? null : respHeaders,
      resourceType: params['type'] as String?,
    );

      _emitEvent(CdpNetworkEvent(
        eventType: 'responseReceived',
      log: log,
      statusCode: statusCode,
    ));
  }

  void _onLoadingFinished(Map<String, dynamic> params) {
    final requestId = params['requestId'] as String?;
    final encodedDataLength = (params['encodedDataLength'] as num?)?.toDouble();

    if (requestId != null && encodedDataLength != null) {
      final log = HttpRequestLog(
        timestamp: DateTime.now(),
        method: 'FINISHED',
        url: requestId,
      );
      _emitEvent(CdpNetworkEvent(
        eventType: 'loadingFinished',
        log: log,
        encodedDataLength: encodedDataLength,
      ));
    }

    // C1：JSON 响应体捕获——loadingFinished 时响应体已就绪，发 getResponseBody
    if (requestId != null) {
      final meta = _reqMeta.remove(requestId);
      final mime = meta?['mimeType'] ?? '';
      final isJson =
          _isJson(mime) || (meta?['url'] ?? '').contains('json');
      if (meta != null && isJson) {
        final code = int.tryParse(meta?['statusCode'] ?? '');
        _fetchResponseBody(requestId, meta['url'] ?? '', statusCode: code);
      }
    }
  }

  /// 是否为 JSON 响应类型。
  bool _isJson(String? mimeType) =>
      mimeType != null && mimeType.toLowerCase().contains('json');

  /// 请求 CDP 返回响应体并作为新日志事件发出（≤32KB 截断）。
  void _fetchResponseBody(String requestId, String url, {int? statusCode}) {
    _sendCommand('Network.getResponseBody', {'requestId': requestId}).then((resp) {
      final result = resp['result'] as Map<String, dynamic>?;
      if (result == null) return;
      var body = result['body'] as String? ?? '';
      if (result['base64Encoded'] == true) {
        try {
          body = utf8.decode(base64Decode(body));
        } catch (_) {
          // 解码失败保留原文
        }
      }
      if (body.length > 32768) {
        body = '${body.substring(0, 32768)}… (truncated at 32KB)';
      }
      _emitEvent(CdpNetworkEvent(
        eventType: 'responseBody',
        log: HttpRequestLog(
          timestamp: DateTime.now(),
          method: 'RESPONSE',
          url: url,
          statusCode: statusCode,
          responseBody: body,
        ),
      ));
      _log('✅ 响应体已捕获（$url, ${body.length} chars）');
    }).catchError((e) {
      _log('⚠ 响应体捕获失败（$url）: $e');
    });
  }

  void _onLoadingFailed(Map<String, dynamic> params) {
    final requestId = params['requestId'] as String? ?? '';
    final url = params['url'] as String? ?? requestId;
    final errorText = params['errorText'] as String? ?? 'Unknown error';
    final type = params['type'] as String? ?? '';

    final log = HttpRequestLog(
      timestamp: DateTime.now(),
      method: 'FAILED',
      url: '$url ($type: $errorText)',
    );

      _emitEvent(CdpNetworkEvent(
        eventType: 'loadingFailed',
      log: log,
      errorText: errorText,
    ));
  }

  void _onWebSocketCreated(Map<String, dynamic> params) {
    final url = params['url'] as String? ?? '';
    if (url.isEmpty) return;

    final log = HttpRequestLog(
      timestamp: DateTime.now(),
      method: 'WS_OPEN',
      url: url,
    );
      _emitEvent(CdpNetworkEvent(
        eventType: 'webSocketCreated',
      log: log,
    ));
  }

  void _onWebSocketFrame(String eventType, Map<String, dynamic> params) {
    final response = params['response'] as Map<String, dynamic>?;
    final payloadData = response?['payloadData'] as String?;
    final url = response?['url'] as String? ?? '';

    if (payloadData == null || payloadData.isEmpty) return;

    final dir = eventType == 'Network.webSocketFrameSent' ? 'SENT' : 'RECV';
    final log = HttpRequestLog(
      timestamp: DateTime.now(),
      method: 'WS_$dir',
      url: url,
      body: payloadData.length > 4096
          ? '${payloadData.substring(0, 4096)}...'
          : payloadData,
    );
      _emitEvent(CdpNetworkEvent(
        eventType: 'webSocketFrame',
      log: log,
    ));
  }

  void _onFrameNavigated(Map<String, dynamic> params) {
    final frame = params['frame'] as Map<String, dynamic>?;
    final url = frame?['url'] as String? ?? '';
    if (url.isEmpty) return;

    final log = HttpRequestLog(
      timestamp: DateTime.now(),
      method: 'NAVIGATION',
      url: url,
    );
      _emitEvent(CdpNetworkEvent(
        eventType: 'frameNavigated',
      log: log,
    ));
  }

  // ── 资源管理 ──

  /// 受释放保护的网络事件分发（避免 dispose 后向已关闭的控制器 add）。
  void _emitEvent(CdpNetworkEvent event) {
    if (_disposed || _networkEventController.isClosed) return;
    _networkEventController.add(event);
  }

  void _log(String msg) {
    if (_disposed || _statusController.isClosed) return;
    _statusController.add(msg);
    assert(() {
      debugPrint('[CdpNetworkClient] $msg');
      return true;
    }());
  }

  /// 受释放保护的状态日志分发。
  void _emitStatus(String msg) {
    if (_disposed || _statusController.isClosed) return;
    _statusController.add(msg);
  }

  /// 释放所有资源。
  void dispose() {
    _disposed = true;
    _ws?.close();
    _ws = null;
    _networkEventController.close();
    _statusController.close();
    _log('已释放');
  }
}
