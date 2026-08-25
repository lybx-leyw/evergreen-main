/// HTTP 服务器——暴露 REST 端点供插件 .exe 查询、刷新、测试连通性。
///
/// ## DataHttpServer
/// | 方法 | 说明 |
/// |------|------|
/// | `DataHttpServer(orchestrator, {port})` | 构造，默认端口 0（自动分配） |
/// | `start()` | 启动监听，返回实际端口 |
/// | `stop()` | 关闭服务器 |
/// | `isRunning` | 是否正在监听 |
/// | `port` | 实际端口号 |

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:evergreen_base/core/log.dart';
import 'package:evergreen_base/core/utils/greenix_path.dart';

import 'orchestrator.dart';
import 'type.dart';
import 'exceptions.dart';
import 'register_data_source.dart';
import 'data_diff.dart';
import 'sse_frame.dart';

// ═══════════════════════════════════════════════════════════════════════════
// DataHttpServer
// ═══════════════════════════════════════════════════════════════════════════

/// 数据层 HTTP 服务器。供插件 .exe 通过 HTTP 调用平台数据能力。
///
/// 端点：
/// - `GET  /data/health`
/// - `GET  /data/types`
/// - `GET  /data/types/:name`
/// - `POST /data/types/:name/refresh`
/// - `GET  /data/status`
/// - `GET  /data/status/:name`
/// - `POST /data/connectivity/test`
/// - `GET  /data/stream/:name`（SSE 长连接：订阅流式数据源）
/// - `GET  /data/events`（SSE 长连接：全局数据变更事件流）
class DataHttpServer {
  final DataOrchestrator _orchestrator;
  final int _requestedPort;

  HttpServer? _server;
  bool _running = false;

  DataHttpServer(this._orchestrator, {int port = 0}) : _requestedPort = port;

  bool get isRunning => _running;
  int get port => _server?.port ?? 0;

  /// 启动监听。返回实际绑定的端口号。
  Future<int> start() async {
    if (_running) return _server!.port;

    _server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      _requestedPort,
    );
    _running = true;

    _server!.listen(_handleRequest);
    Log().info('DataHttpServer: 启动 (port: ${_server!.port})');
    return _server!.port;
  }

  /// 关闭服务器。
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    await _server?.close(force: true);
    _server = null;
    Log().info('DataHttpServer: 已关闭');
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 路由
  // ═══════════════════════════════════════════════════════════════════════
  //
  // 路由表：`(method, pattern)` → handler。
  // `pattern` 支持 `:param` 占位符（如 `/data/types/:name`）。
  // 精确匹配优先于参数匹配。

  static final _paramPattern = RegExp(r'^:(\w+)$');

  Future<void> _handleRequest(HttpRequest request) async {
    final sw = Stopwatch()..start();
    int status;
    try {
      status = await _dispatch(request);
    } catch (e, st) {
      status = 500;
      Log().error('DataHttpServer: 请求处理异常', error: e, stack: st);
      _respond(request.response, 500, {'error': '内部错误'});
    }
    stderr.writeln(
      '[DataHttp] ${request.method} ${request.uri.path} → $status (${sw.elapsedMilliseconds}ms)');
  }

  /// 分发请求，返回响应状态码。
  Future<int> _dispatch(HttpRequest request) async {
    final method = request.method;
    final path = request.uri.path;
    final segments = path.split('/')..removeAt(0); // drop leading empty

    // 精确匹配
    final exactKey = '$method $path';
    final exact = _routes[exactKey];
    if (exact != null) {
      await exact(request, {});
      return 200;
    }

    // 参数匹配
    for (final entry in _paramRoutes.entries) {
      final parts = entry.key.split(' ');
      if (parts[0] != method) continue;
      final patternSegments = parts[1].split('/')..removeAt(0);
      if (patternSegments.length != segments.length) continue;

      final params = <String, String>{};
      var match = true;
      for (var i = 0; i < patternSegments.length; i++) {
        final pm = _paramPattern.firstMatch(patternSegments[i]);
        if (pm != null) {
          params[pm.group(1)!] = segments[i];
        } else if (patternSegments[i] != segments[i]) {
          match = false;
          break;
        }
      }
      if (match) {
        await entry.value(request, params);
        return 200;
      }
    }

    // 404
    _respond(request.response, 404,
        {'error': '未找到: $method $path'});
    return 404;
  }

  // 路由表定义
  late final Map<String, Future<void> Function(HttpRequest, Map<String, String>)> _routes = {
    'GET /data/health': (req, _) async {
      _respond(req.response, 200, {'status': 'ok'});
    },
    'GET /data/types': (req, _) async {
      final types = _orchestrator.registeredTypes.map((name) {
        final s = _orchestrator.status(name);
        return {
          'name': name,
          'category': s?.category ?? '',
          'displayName': s?.displayName ?? name,
          'isFresh': s?.isFresh ?? false,
          'connected': s?.connected ?? false,
        };
      }).toList();
      _respond(req.response, 200, {'types': types});
    },
    'GET /data/status': (req, _) async {
      final statuses =
          _orchestrator.allStatuses.map(_statusToJson).toList();
      _respond(req.response, 200, {
        'statuses': statuses,
        'summary': {
          'total': _orchestrator.totalCount,
          'connected': _orchestrator.connectedCount,
          'fresh': _orchestrator.freshCount,
        },
      });
    },
    'POST /data/connectivity/test': (req, _) async {
      final results = await _orchestrator.testAllConnectivity();
      _respond(req.response, 200, {'results': results});
    },
    // 运行期热注册：DSH tool 写数据源产物后调用，触发 DataOrchestrator 注册。
    // body: { "pluginDir": "<plugins>/data-<name>" }（含 data/manifest.json）。
    'POST /data/register': (req, _) async {
      await _handleRegister(req);
    },
    // 全局数据变更事件 SSE（长连接）：转发 DataOrchestrator.dataChangeEvents。
    'GET /data/events': (req, _) async {
      await _handleEventsSse(req);
    },
  };

  /// POST /data/register 处理：读 body → 注册数据源 → 返回结果。
  Future<void> _handleRegister(HttpRequest req) async {
    try {
      final body = await utf8.decoder.bind(req).join();
      final json = body.isEmpty ? <String, dynamic>{} : jsonDecode(body);
      if (json is! Map<String, dynamic>) {
        _respond(req.response, 400, {'error': 'body 必须是 JSON 对象'});
        return;
      }
      final pluginDir = json['pluginDir'] as String? ?? '';
      if (pluginDir.isEmpty) {
        _respond(req.response, 400, {'error': '缺少 pluginDir 参数'});
        return;
      }
      final projectRoot = resolveProjectRoot() ?? Directory.current.path;
      final registered = registerDataSourcesFromManifest(
        orch: _orchestrator,
        pluginDir: pluginDir,
        projectRoot: projectRoot,
      );
      if (registered.isEmpty) {
        _respond(req.response, 404, {
          'error': '未注册任何数据源（manifest 缺失/非法或类型为空）',
          'pluginDir': pluginDir,
        });
        return;
      }
      _respond(req.response, 200, {
        'registered': registered,
        'pluginDir': pluginDir,
      });
    } catch (e) {
      Log().error('DataHttpServer: /data/register 处理异常', error: e);
      _respond(req.response, 500, {'error': '注册失败: $e'});
    }
  }

  late final Map<String, Future<void> Function(HttpRequest, Map<String, String>)> _paramRoutes = {
    'GET /data/types/:name': (req, p) async {
      final name = p['name']!;
      // 复用中枢已注册的 DataType（携带 persistentKey/ttl），以启用“缓存优先”读取；
      // 否则临时构造的空壳 DataType 因 persistentKey 为 null 会令 _orchestrator.get
      // 每次都真实拉取、绕过缓存。未注册时兜底空壳，get 内部降级为异常。
      final dt = _orchestrator.typeByName(name) ??
          DataType<dynamic>(name: name, category: '');
      try {
        final data = await _orchestrator.get(dt);
        if (data == null) {
          // fetcher 失败（如网络错误、认证失败等）——返回错误详情
          final status = _orchestrator.status(name);
          final errMsg = status?.lastError ?? '数据源 "$name" 拉取失败';
          _respond(req.response, 502, {'error': errMsg, 'name': name});
        } else {
          _respond(req.response, 200, {'data': data});
        }
      } on DataTypeNotRegisteredException {
        _respond(req.response, 404, {'error': '数据类型未注册: $name'});
      } catch (e) {
        _respond(req.response, 500, {'error': '获取数据失败: $e', 'name': name});
      }
    },
    'POST /data/types/:name/refresh': (req, p) async {
      final name = p['name']!;
      // 同上：优先复用已注册 DataType（携带 persistentKey），refresh 无条件重抓但
      // 仍写回中枢缓存，避免后续 get 因 type 不匹配而失效。未注册时兜底空壳。
      final dt = _orchestrator.typeByName(name) ??
          DataType<dynamic>(name: name, category: '');
      try {
        final data = await _orchestrator.refresh(dt);
        if (data == null) {
          final status = _orchestrator.status(name);
          final errMsg = status?.lastError ?? '数据源 "$name" 刷新失败';
          _respond(req.response, 502, {'error': errMsg, 'name': name});
        } else {
          _respond(req.response, 200, {'data': data});
        }
      } on DataTypeNotRegisteredException {
        _respond(req.response, 404, {'error': '数据类型未注册: $name'});
      } catch (e) {
        _respond(req.response, 500, {'error': '刷新数据失败: $e', 'name': name});
      }
    },
    'GET /data/status/:name': (req, p) async {
      final name = p['name']!;
      final s = _orchestrator.status(name);
      if (s == null) {
        _respond(req.response, 404, {'error': '数据源未找到: $name'});
      } else {
        _respond(req.response, 200, _statusToJson(s));
      }
    },
    // 流式数据源 SSE（长连接）：订阅 streamByName(name) 的 data/error/done 帧。
    'GET /data/stream/:name': (req, p) async {
      await _handleStreamSse(req, p['name']!);
    },
  };

  // ═══════════════════════════════════════════════════════════════════════
  // SSE 端点（长连接）
  // ═══════════════════════════════════════════════════════════════════════

  /// `GET /data/stream/:name`：订阅 [DataOrchestrator.streamByName] 的流式数据。
  ///
  /// 未注册流式类型 → 404；否则以 `text/event-stream` 长连接转发
  /// `event: data` / `event: error` / `event: done` 帧（见 [sse_frame.dart]）。
  Future<void> _handleStreamSse(HttpRequest req, String name) async {
    final stream = _orchestrator.streamByName(name);
    if (stream == null) {
      _respond(req.response, 404, {'error': '流式数据源未注册: $name'});
      return;
    }
    await _pipeSse(
      req,
      stream,
      frame: (data) => dataStreamSseFrame(name, data),
      errorFrame: (e) => dataStreamErrorSseFrame(name, e),
      doneFrame: () => dataStreamDoneSseFrame(name),
    );
  }

  /// `GET /data/events`：订阅全局数据变更事件流（[DataOrchestrator.dataChangeEvents]）。
  Future<void> _handleEventsSse(HttpRequest req) async {
    await _pipeSse(
      req,
      _orchestrator.dataChangeEvents,
      frame: (e) => changeEventSseFrame(e as DataChangeEvent),
      errorFrame: (e) => 'event: error\ndata: '
          '${jsonEncode({'error': '$e'})}\n\n',
    );
  }

  /// 以 SSE 长连接转发 [stream]，处理客户端断开与清理。
  ///
  /// - [frame] 把每个数据项编码为完整 SSE 帧（`event: ...\ndata: ...\n\n`）。
  /// - [errorFrame] 编码流错误帧；错误帧发送后**关闭连接**（而非保持）——理由：
  ///   流级错误意味着数据源已损坏，保持半开连接会让客户端误以为仍有数据到来；
  ///   关闭后客户端可重连（重新 `streamOf` → 流工厂取新流）。
  /// - [doneFrame]（可选）在流正常结束时发送结束帧再关闭。
  ///
  /// 用 `await for` 背压感知地逐帧 `add` + `await flush`。**不能** fire-and-forget
  /// 地并发 flush：dart:io 的 `HttpResponse.flush()` 完成前再 `add()` 会抛
  /// `Bad state: StreamSink is bound to a stream`——同步流（如 `Stream.fromIterable`）
  /// 首帧 flush 未完成即同步派发下一帧，帧直接丢失（客户端只见响应头、body 为空）。
  /// `await for` 保证上一帧冲刷完成才消费下一事件，同步流亦安全。
  ///
  /// **必须** `bufferOutput = false`：dart:io 的 `HttpResponse.bufferOutput` 默认
  /// true，会把 body 数据缓存在内部 `_HttpOutgoing._buffer`，只有 `close()` 才
  /// 冲刷到 socket——SSE 长连接（不 close）下 `flush()` 根本推不出帧，客户端只
  /// 见响应头（Windows 实测复现）。关闭输出缓冲后 `add`+`flush` 才即时推送。
  ///
  /// 客户端断开检测：写入已断开 socket 时 `response.flush()` 以错误完成 → 退出
  /// `await for` → finally 取消订阅 + 关闭响应，释放订阅资源。
  Future<void> _pipeSse(
    HttpRequest req,
    Stream<dynamic> stream, {
    required String Function(dynamic data) frame,
    required String Function(Object error) errorFrame,
    String Function()? doneFrame,
  }) async {
    final response = req.response;
    response.statusCode = 200;
    // 关闭 dart:io 输出缓冲（默认 true）：SSE 长连接必须逐帧即时推送，
    // 否则 body 帧被缓存到 close 才发送，长连接期间客户端永远收不到帧。
    response.bufferOutput = false;
    response.headers.contentType =
        ContentType('text', 'event-stream', charset: 'utf-8');
    response.headers.set('Cache-Control', 'no-cache');
    response.headers.set('Access-Control-Allow-Origin', '*');
    // 注意：不显式设置 `Connection: keep-alive`。dart:io 对 HTTP/1.0 请求的响应
    // 默认不带 keep-alive（连接以 close 界定 body）；若显式 keep-alive 且无
    // Content-Length，`response.flush()` 会挂起/抛异常（SSE 帧永远发不出）。
    // HTTP/1.1 客户端默认 keep-alive + chunked，flush 即时发 chunk，不受影响。
    // 监听 response.done 以吞掉客户端断开时产生的未捕获错误（避免
    // UnhandledFutureError；长连接期间 done 不完成，正常 close 后完成）。
    response.done.then((_) {}, onError: (Object _) {});

    try {
      await for (final data in stream) {
        response.add(utf8.encode(frame(data)));
        await response.flush();
      }
      // 流正常结束 → done 帧后关闭。
      if (doneFrame != null) {
        try {
          response.add(utf8.encode(doneFrame()));
          await response.flush();
        } catch (_) {
          // 连接已不可写，忽略
        }
      }
    } catch (e) {
      // 流错误（errorFrame 后关闭连接，理由见方法注释）或客户端断开（flush 失败）。
      try {
        response.add(utf8.encode(errorFrame(e)));
        await response.flush();
      } catch (_) {
        // 连接已不可写（客户端断开），忽略
      }
    } finally {
      try {
        await response.close();
      } catch (_) {
        // 客户端已断开
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 内部
  // ═══════════════════════════════════════════════════════════════════════

  void _respond(HttpResponse response, int status, Map<String, dynamic> body) {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.headers.add('Access-Control-Allow-Origin', '*');
    response.write(jsonEncode(body));
    response.close();
  }

  Map<String, dynamic> _statusToJson(DataSourceStatus s) => {
        'name': s.name,
        'category': s.category,
        'displayName': s.displayName,
        'connected': s.connected,
        'isFresh': s.isFresh,
        'freshnessLabel': s.freshnessLabel,
        'relativeTime': s.relativeTime,
        'lastFetchedAt': s.lastFetchedAt?.toIso8601String(),
        'lastError': s.lastError,
      };
}
