/// DataHttpServer SSE 端点测试（T3：data 层流式能力）。
///
/// 覆盖：
/// - `GET /data/stream/:name`：流式数据源 SSE 长连接，验证 `event: data`/`event: done`
///   帧格式（fake 有限流 + 短读/整读）；未注册流式类型 → 404。
/// - `GET /data/events`：全局数据变更事件 SSE，验证 `event: change` 帧（触发一次
///   diff 变更后短读）。
///
/// 注意：本文件属主包集成测试（依赖 `package:evergreen_base` 完整 core 树，含
/// `greenix_path`），只能在主包 `flutter test` 运行；受 data 子包「纯数据文件独立
/// 测试」约束，不能下沉到 `lib/core/data/test/`（见 data/CLAUDE.md Stub 隔离说明）。
///
/// 与 data_http_server_test.dart 同理：flutter_test binding 会把 `HttpClient` 请求
/// 伪造成 400，故用**原始 `Socket`** 直连 loopback 服务器绕过拦截。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:evergreen_base/core/data/data.dart';
import 'package:flutter/services.dart' show MethodCall, MethodChannel;
import 'package:flutter_test/flutter_test.dart';

/// 原始 Socket 发一次 GET，读完整响应（服务器关闭连接后返回）。
///
/// 返回 `(status, contentType, body)`。适合有限流（`Stream.fromIterable`）——
/// 服务器写完 data/done 帧后主动关闭，客户端读满即结束。
Future<(int, String?, String)> _rawSseGet(int port, String path,
    {Duration timeout = const Duration(seconds: 10)}) async {
  final socket = await Socket.connect('127.0.0.1', port);
  // HTTP/1.0 + Connection: close：服务器以纯文本 body 发送（无 chunked 分块），
  // 便于原始 Socket 直接解析 SSE 帧。
  socket.write(
      'GET $path HTTP/1.0\r\nHost: localhost\r\nConnection: close\r\n\r\n');
  final bytes = <int>[];
  final done = Completer<void>();
  socket.listen(bytes.addAll, onDone: () {
    if (!done.isCompleted) done.complete();
  }, onError: (Object _) {
    if (!done.isCompleted) done.complete();
  });
  await done.future.timeout(timeout, onTimeout: () {});
  socket.destroy();
  final all = utf8.decode(bytes, allowMalformed: true);
  final headerEnd = all.indexOf('\r\n\r\n');
  final head = headerEnd < 0 ? all : all.substring(0, headerEnd);
  final body = headerEnd < 0 ? '' : all.substring(headerEnd + 4);
  final statusLine = head.split('\r\n').first;
  final status = int.parse(statusLine.split(' ')[1]);
  final contentType = RegExp(r'(?i)content-type:\s*([^\r\n]+)')
      .firstMatch(head)
      ?.group(1);
  return (status, contentType, body);
}

/// 解析 SSE body 里的 `event: <name>` 段，返回 `(事件名, data 负载 JSON)` 列表。
List<(String, String)> _parseSse(String body) {
  final out = <(String, String)>[];
  for (final block in body.split('\n\n')) {
    String? event;
    String? data;
    for (final line in block.split('\n')) {
      if (line.startsWith('event: ')) event = line.substring(7).trim();
      if (line.startsWith('data: ')) data = line.substring(6).trim();
    }
    if (event != null && data != null) out.add((event, data));
  }
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DataOrchestrator orch;
  late DataHttpServer server;
  late int port;

  setUp(() async {
    final tmp = Directory.systemTemp.createTempSync('hsrv_sse_cache_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => tmp.path,
    );
    await Cache.getInstance();

    orch = DataOrchestrator();
    server = DataHttpServer(orch);
    port = await server.start();
  });

  tearDown(() async {
    await server.stop();
  });

  group('GET /data/stream/:name（SSE 流式数据源）', () {
    test('有限流 → event:data 帧 + event:done 帧，帧格式正确', () async {
      orch.registerStream(
        const DataType<Map<String, dynamic>>(
            name: 'sse_stream_a', category: 'test'),
        () => Stream.fromIterable([
          {'t': 1},
          {'t': 2},
        ]),
      );

      final (status, contentType, body) =
          await _rawSseGet(port, '/data/stream/sse_stream_a');

      expect(status, 200);
      expect(contentType, contains('text/event-stream'));

      final frames = _parseSse(body);
      final dataFrames = frames.where((f) => f.$1 == 'data').toList();
      final doneFrames = frames.where((f) => f.$1 == 'done').toList();

      expect(dataFrames.length, 2);
      expect(jsonDecode(dataFrames[0].$2)['data'], {'t': 1});
      expect(jsonDecode(dataFrames[1].$2)['data'], {'t': 2});
      expect(doneFrames.length, 1);
      // 流结束后状态标记完成（不注销）
      expect(orch.status('sse_stream_a')!.completed, isTrue);
    });

    test('未注册流式类型 → 404', () async {
      final (status, _, _) = await _rawSseGet(port, '/data/stream/not_exists');
      expect(status, 404);
    });

    test('流错误 → event:error 帧后关闭连接', () async {
      orch.registerStream(
        const DataType<int>(name: 'sse_stream_err', category: 'test'),
        () => Stream<int>.error(Exception('boom')),
      );

      final (status, _, body) =
          await _rawSseGet(port, '/data/stream/sse_stream_err');

      expect(status, 200);
      final frames = _parseSse(body);
      expect(frames.any((f) => f.$1 == 'error'), isTrue);
      expect(orch.status('sse_stream_err')!.connected, isFalse);
      expect(orch.status('sse_stream_err')!.lastError, contains('boom'));
    });
  });

  group('GET /data/events（SSE 全局变更事件流）', () {
    test('触发 diff 变更 → 短读收到 event:change 帧', () async {
      const type = DataType<Map<String, dynamic>>(
          name: 'sse_evt_a', category: 'test', persistentKey: 'sse_evt_a:key');

      // 先建立 SSE 连接（后台），再触发变更。
      final socket = await Socket.connect('127.0.0.1', port);
      socket.write(
          'GET /data/events HTTP/1.0\r\nHost: localhost\r\nConnection: close\r\n\r\n');

      orch.register(type, () async => {'v': 1});
      await orch.refresh(type, notifyOnChange: true); // 首次：无基线不发
      orch.register(type, () async => {'v': 2});
      await orch.refresh(type, notifyOnChange: true); // 1 → 2，发事件

      // 短读：抓取已到达的字节（不等待连接关闭，变更流长连接不主动关闭）。
      final bytes = <int>[];
      await for (final chunk in socket.timeout(const Duration(seconds: 3))) {
        bytes.addAll(chunk);
        if (utf8.decode(bytes, allowMalformed: true).contains('event: change')) {
          break;
        }
      }
      socket.destroy();

      final body = utf8.decode(bytes, allowMalformed: true);
      final frames = _parseSse(body);
      final changeFrames = frames.where((f) => f.$1 == 'change').toList();
      expect(changeFrames, isNotEmpty);
      final payload = jsonDecode(changeFrames.first.$2) as Map<String, dynamic>;
      expect(payload['sourceName'], 'sse_evt_a');
    });
  });
}
