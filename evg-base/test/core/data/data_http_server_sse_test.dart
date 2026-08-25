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
import 'package:flutter_test/flutter_test.dart';

/// 解码 HTTP/1.1 chunked transfer-encoding body。
///
/// SSE 流式多帧依赖 HTTP/1.1 的 chunked 分块（HTTP/1.0 无分块编码，
/// `flush()` 后不能再 add——见 DataHttpServer._pipeSse 注释）。本函数剥离
/// chunk 大小行，还原纯 SSE 帧文本。对不完整 body（长连接短读）尽力解码。
String _decodeChunked(String raw) {
  final headerEnd = raw.indexOf('\r\n\r\n');
  if (headerEnd < 0) return '';
  final head = raw.substring(0, headerEnd);
  var rest = raw.substring(headerEnd + 4);
  final isChunked = head.toLowerCase().contains('transfer-encoding: chunked');
  if (!isChunked) return rest;
  final out = StringBuffer();
  while (rest.isNotEmpty) {
    final lineEnd = rest.indexOf('\r\n');
    if (lineEnd < 0) break;
    final size = int.tryParse(rest.substring(0, lineEnd).trim(), radix: 16);
    if (size == null || size == 0) break;
    rest = rest.substring(lineEnd + 2);
    if (rest.length < size) {
      // 长连接短读：chunk 未完整到达，剩余归入输出（宽松容错）。
      out.write(rest);
      break;
    }
    out.write(rest.substring(0, size));
    rest = rest.substring(size);
    if (rest.startsWith('\r\n')) rest = rest.substring(2);
  }
  return out.toString();
}

/// 原始 Socket 发一次 GET（HTTP/1.1，服务器按 chunked 响应），读完整响应后
/// 解码 chunked，返回 `(status, contentType, body)`。
Future<(int, String?, String)> _rawSseGet(int port, String path,
    {Duration timeout = const Duration(seconds: 10)}) async {
  final socket = await Socket.connect('127.0.0.1', port);
  // HTTP/1.1：SSE 流式多帧依赖 chunked 分块（HTTP/1.0 无法多帧流式）。
  // Connection: close 让服务器在响应完成后关闭连接，客户端读满即结束。
  socket.write(
      'GET $path HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n');
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
  final body = headerEnd < 0 ? '' : _decodeChunked(all);
  final statusLine = head.split('\r\n').first;
  final status = int.parse(statusLine.split(' ')[1]);
  // 注：Dart RegExp 不支持 `(?i)` 内联标志（抛 Invalid group），用构造参数。
  final contentType = RegExp('content-type:\\s*([^\\r\\n]+)',
          caseSensitive: false)
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
    // 注：SSE/流式测试不落盘（registerStream 不写 Cache），不初始化 Cache——
    // 避免依赖 path_provider 平台通道（Windows 走 path_provider_windows 原生实现，
    // MethodChannel mock 不生效，可能在无 app 环境下抛错）。
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
          'GET /data/events HTTP/1.1\r\nHost: localhost\r\n\r\n');

      // 等待服务器异步处理请求并订阅 dataChangeEvents（避免事件在订阅前发出而漏帧）。
      await Future<void>.delayed(const Duration(milliseconds: 200));

      orch.register(type, () async => {'v': 1});
      await orch.refresh(type, notifyOnChange: true); // 首次：无基线不发
      orch.register(type, () async => {'v': 2});
      await orch.refresh(type, notifyOnChange: true); // 1 → 2，发事件

      // 短读：抓取已到达的字节（不等待连接关闭，变更流长连接不主动关闭）。
      final bytes = <int>[];
      await for (final chunk in socket.timeout(const Duration(seconds: 3))) {
        bytes.addAll(chunk);
        // chunked 分块可能跨越帧边界，先解码再检查 change 帧。
        if (_decodeChunked(utf8.decode(bytes, allowMalformed: true))
            .contains('event: change')) {
          break;
        }
      }
      socket.destroy();

      final body = _decodeChunked(utf8.decode(bytes, allowMalformed: true));
      final frames = _parseSse(body);
      final changeFrames = frames.where((f) => f.$1 == 'change').toList();
      expect(changeFrames, isNotEmpty);
      final payload = jsonDecode(changeFrames.first.$2) as Map<String, dynamic>;
      expect(payload['sourceName'], 'sse_evt_a');
    });
  });
}
