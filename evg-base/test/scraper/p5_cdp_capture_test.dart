/// A-P5 Batch 3（C1+C2 捕获质量补全）单元测试。
///
/// 覆盖：
/// - C1：`CdpNetworkClient` 通过 CDP `Network.getResponseBody` 捕获 JSON 响应体
///   （普通 / base64 / 超大截断 / 非 JSON 不捕获）。
/// - C2：`_sendCommand` 按 id 匹配等待命令响应（请求/响应往返验证）；
///   `Network.enable` 失败时 `connect()` 优雅返回 `false`（降级日志清晰）。
/// - 纯 Dart：`HttpRequestLog.responseBody` 经 toJson/fromJson 往返 + AI 摘要包含响应体。
///
/// 通过本地伪 CDP 服务端（dart:io HttpServer + WebSocket）驱动真实连接流程，
/// 不依赖真实 Edge WebView2 / 网络。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:evergreen_base/renderer/templates/scraper_modle/cdp_network_client.dart';
import 'package:evergreen_base/renderer/templates/scraper_modle/scraper_workflow.dart';
import 'package:flutter_test/flutter_test.dart';

/// 伪 CDP 服务端：模拟 WebView2 的 `/json` 目标发现 + `/cdp` WebSocket 端点。
///
/// 收到命令（含 id）即回 `{id, result:{}}`；`Network.getResponseBody` 回响应体；
/// `Page.enable` 后推送 requestWillBeSent → responseReceived → loadingFinished 序列，
/// 触发客户端去取响应体。
class FakeCdpServer {
  FakeCdpServer({
    required this.bodyToReturn,
    this.base64 = false,
    this.mimeType = 'application/json',
    this.errorOnEnable = false,
  });

  final String bodyToReturn;
  final bool base64;
  final String mimeType;
  final bool errorOnEnable;

  late HttpServer _httpServer;
  WebSocket? _cdpWs;

  Future<int> start() async {
    _httpServer = await HttpServer.bind('127.0.0.1', 0);
    _httpServer.listen((request) async {
      if (request.uri.path == '/json') {
        final targets = [
          {
            'type': 'page',
            'webSocketDebuggerUrl': 'ws://127.0.0.1:${_httpServer.port}/cdp',
          }
        ];
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(targets));
        await request.response.close();
      } else if (request.uri.path == '/cdp') {
        _cdpWs = await WebSocketTransformer.upgrade(request);
        _handleWs(_cdpWs!);
      } else {
        request.response.statusCode = 404;
        await request.response.close();
      }
    });
    return _httpServer.port;
  }

  void _handleWs(WebSocket ws) {
    ws.listen((data) {
      final msg = jsonDecode(data as String) as Map<String, dynamic>;
      final id = msg['id'];
      if (id == null) return; // 仅处理命令
      final method = msg['method'] as String?;

      if (method == 'Network.getResponseBody') {
        final payload = base64
            ? base64Encode(utf8.encode(bodyToReturn))
            : bodyToReturn;
        ws.add(jsonEncode({
          'id': id,
          'result': {'body': payload, 'base64Encoded': base64},
        }));
        return;
      }

      if (method == 'Network.enable' && errorOnEnable) {
        ws.add(jsonEncode({
          'id': id,
          'error': {'message': 'CDP Network.enable failed (fake)'},
        }));
        return;
      }

      ws.add(jsonEncode({'id': id, 'result': {}}));

      // Page.enable 成功后模拟一次 JSON 接口请求序列。
      if (method == 'Page.enable') {
        Timer.run(() => _pushEvents(ws));
      }
    });
  }

  void _pushEvents(WebSocket ws) {
    ws.add(jsonEncode({
      'method': 'Network.requestWillBeSent',
      'params': {
        'requestId': 'req1',
        'request': {'url': 'https://x.com/api/data', 'method': 'GET'},
        'type': 'XHR',
      },
    }));
    ws.add(jsonEncode({
      'method': 'Network.responseReceived',
      'params': {
        'requestId': 'req1',
        'response': {
          'url': 'https://x.com/api/data',
          'status': 200,
          'mimeType': mimeType,
        },
      },
    }));
    ws.add(jsonEncode({
      'method': 'Network.loadingFinished',
      'params': {'requestId': 'req1', 'encodedDataLength': 1234},
    }));
  }

  Future<void> stop() async {
    try {
      await _cdpWs?.close();
    } catch (_) {}
    await _httpServer.close(force: true);
  }
}

/// 等待并提取首条指定类型的网络事件。
///
/// 注意：必须用 `await Future.delayed` 让出事件循环，绝不可用 [sleep]——
/// [sleep] 会阻塞整个 isolate，导致 CDP 异步往返（WebSocket 收发）无法推进。
Future<CdpNetworkEvent?> _awaitEvent(
  List<CdpNetworkEvent> events,
  String type, {
  Duration timeout = const Duration(seconds: 6),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final found = events.where((e) => e.eventType == type).firstOrNull;
    if (found != null) return found;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  return null;
}

void main() {
  group('C1 CdpNetworkClient 响应体捕获', () {
    late FakeCdpServer server;
    late CdpNetworkClient client;
    late List<CdpNetworkEvent> events;
    late StreamSubscription<CdpNetworkEvent> sub;

    Future<void> setUpServer(FakeCdpServer s) async {
      server = s;
      final port = await server.start();
      client = CdpNetworkClient(debugPort: port);
      events = [];
      sub = client.networkEvents.listen(events.add);
      final ok = await client.connect();
      expect(ok, isTrue, reason: 'CDP 应连接成功');
    }

    Future<void> tearDownServer() async {
      await sub.cancel();
      client.dispose();
      await server.stop();
    }

    test('捕获 JSON 响应体（普通文本）', () async {
      const body = '{"id":1,"name":"test"}';
      await setUpServer(FakeCdpServer(bodyToReturn: body));

      final rb = await _awaitEvent(events, 'responseBody');
      expect(rb, isNotNull, reason: '应发出 responseBody 事件');
      expect(rb!.log.responseBody, body);
      expect(rb.log.method, 'RESPONSE');
      expect(rb.log.url, 'https://x.com/api/data');

      await tearDownServer();
    });

    test('解码 base64 编码的响应体', () async {
      const body = '{"ok":true,"count":3}';
      await setUpServer(FakeCdpServer(bodyToReturn: body, base64: true));

      final rb = await _awaitEvent(events, 'responseBody');
      expect(rb, isNotNull);
      expect(rb!.log.responseBody, body);

      await tearDownServer();
    });

    test('超大响应体在 32KB 处截断', () async {
      final body = 'x' * 40000;
      await setUpServer(FakeCdpServer(bodyToReturn: body));

      final rb = await _awaitEvent(events, 'responseBody');
      expect(rb, isNotNull);
      final captured = rb!.log.responseBody!;
      expect(captured, contains('truncated at 32KB'));
      expect(captured.length, greaterThan(32768));
      expect(captured.startsWith('x'), isTrue);

      await tearDownServer();
    });

    test('非 JSON 响应（text/html）不触发 getResponseBody', () async {
      await setUpServer(FakeCdpServer(
        bodyToReturn: 'ignore',
        mimeType: 'text/html',
      ));

      // 给足够时间，确认无 responseBody 事件（非 JSON 不应取体）。
      await Future<void>.delayed(const Duration(milliseconds: 400));
      final rb = events.where((e) => e.eventType == 'responseBody').firstOrNull;
      expect(rb, isNull, reason: '非 JSON 响应不应捕获响应体');

      // 但请求/响应事件本身应正常存在。
      expect(
        events.where((e) => e.eventType == 'requestWillBeSent').firstOrNull,
        isNotNull,
      );

      await tearDownServer();
    });
  });

  group('C2 CdpNetworkClient 命令响应等待', () {
    test('Network.enable 失败时 connect 优雅返回 false', () async {
      final server = FakeCdpServer(bodyToReturn: '', errorOnEnable: true);
      final port = await server.start();
      final client = CdpNetworkClient(debugPort: port);

      final ok = await client.connect();
      expect(ok, isFalse, reason: 'enable 失败应降级返回 false');

      client.dispose();
      await server.stop();
    });
  });

  group('C1 纯 Dart：HttpRequestLog.responseBody 往返', () {
    test('toJson/fromJson 往返 + AI 摘要包含响应体', () {
      const body = '{"field":"value"}';
      final log = HttpRequestLog(
        timestamp: DateTime.now(),
        method: 'RESPONSE',
        url: 'https://x.com/api/data',
        responseBody: body,
      );

      final j = log.toJson();
      expect(j['responseBody'], body);

      final back = HttpRequestLog.fromJson(j);
      expect(back.responseBody, body);

      expect(log.toAiSummary(), contains('ResponseBody'));
      expect(log.toLogLine(), contains('ResponseBody'));
    });
  });
}
