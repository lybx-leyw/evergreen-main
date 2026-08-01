/// DataHttpServer 回归测试。
///
/// 重点验证 `GET /data/types/:name` 经由 `typeByName` 复用已注册的带
/// `persistentKey` 的 DataType 后，缓存优先读取生效（不再每次真实拉取），
/// 以及 `POST .../refresh` 仍强制重抓、未注册类型降级为 404。
///
/// 注意：测试 binding 会把 `HttpClient` 请求伪造成 400，故本测试用**原始
/// `Socket`** 直连 loopback 服务器（绕过 HttpClient 拦截），同时仍可正常初始化
/// Cache + path_provider mock 以验证文件缓存命中。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:evergreen_base/core/data/data.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 用原始 Socket 发送一次 HTTP 请求并解析状态行 + JSON body。
Future<Map<String, dynamic>> _raw(
    String method, int port, String path) async {
  final socket = await Socket.connect('127.0.0.1', port);
  // 用 HTTP/1.0：服务器会直接发送纯文本 body（不启用 chunked 分块），
  // 便于原始 Socket 客户端直接 jsonDecode。
  socket.write(
      '$method $path HTTP/1.0\r\nHost: localhost\r\nContent-Length: 0\r\nConnection: close\r\n\r\n');
  final bytes = <int>[];
  final done = Completer<List<int>>();
  socket.listen(bytes.addAll, onDone: () => done.complete(bytes),
      onError: done.completeError);
  final all = utf8.decode(await done.future);
  final statusLine = all.substring(0, all.indexOf('\r\n'));
  final status = int.parse(statusLine.split(' ')[1]);
  final headerEnd = all.indexOf('\r\n\r\n');
  final bodyStr = headerEnd < 0 ? '' : all.substring(headerEnd + 4);
  final body =
      bodyStr.isEmpty ? <String, dynamic>{} : jsonDecode(bodyStr) as Map<String, dynamic>;
  return {'status': status, 'body': body};
}

void main() {
  // 安装交互式 binding 以初始化 TestDefaultBinaryMessengerBinding，
  // 供 path_provider mock + Cache 初始化（缓存命中验证必需）。
  TestWidgetsFlutterBinding.ensureInitialized();

  late DataOrchestrator orch;
  late DataHttpServer server;
  late int port;

  setUp(() async {
    // flutter test 环境无 path_provider 平台实现，mock 使其指向临时目录，
    // 让 Cache 的文件读写可用（否则抛 MissingPluginException）。
    final tmp = Directory.systemTemp.createTempSync('hsrv_cache_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => tmp.path,
    );
    // 初始化 Cache 单例（否则 DataOrchestrator._cache 为 null，缓存被禁用）。
    await Cache.getInstance();

    // 计数 fetcher：每次真实拉取 +1，返回当前计数。
    var calls = 0;
    orch = DataOrchestrator();
    orch.register(
      const DataType<Map<String, dynamic>>(
        name: 'hsrv_cache_a',
        category: 'test',
        persistentKey: 'hsrv_cache_a:key',
        ttl: Duration(minutes: 5),
      ),
      () async => <String, dynamic>{'v': ++calls},
    );
    // 独立类型用于 refresh/未注册用例，避免与缓存用例的文件缓存相互污染。
    orch.register(
      const DataType<Map<String, dynamic>>(
        name: 'hsrv_refresh_b',
        category: 'test',
        persistentKey: 'hsrv_refresh_b:key',
        ttl: Duration(minutes: 5),
      ),
      () async => <String, dynamic>{'v': (calls += 1)},
    );

    server = DataHttpServer(orch);
    port = await server.start();
  });

  tearDown(() async {
    await server.stop();
  });

  group('DataHttpServer 数据拉取', () {
    test('GET /data/types/:name → 200 且命中缓存不重复拉取', () async {
      final r1 = await _raw('GET', port, '/data/types/hsrv_cache_a');
      expect(r1['status'], 200);
      expect(r1['body']['data']['v'], 1);

      // 第二次拉取：缓存优先，不应再次调用 fetcher（v 仍为 1）。
      final r2 = await _raw('GET', port, '/data/types/hsrv_cache_a');
      expect(r2['status'], 200);
      expect(r2['body']['data']['v'], 1);
    });

    test('POST /data/types/:name/refresh → 200 且强制重抓', () async {
      final r = await _raw('POST', port, '/data/types/hsrv_refresh_b/refresh');
      expect(r['status'], 200);
      final v1 = r['body']['data']['v'] as int;
      // 再次 refresh 应再次真实拉取（计数递增）。
      final r2 = await _raw('POST', port, '/data/types/hsrv_refresh_b/refresh');
      expect(r2['status'], 200);
      final v2 = r2['body']['data']['v'] as int;
      expect(v2, greaterThan(v1));
    });

    test('GET /data/types/:name → 404 未注册', () async {
      final r = await _raw('GET', port, '/data/types/hsrv_not_registered');
      expect(r['status'], 404);
    });

    test('GET /data/types → 200 列出已注册类型', () async {
      final r = await _raw('GET', port, '/data/types');
      expect(r['status'], 200);
      final types = r['body']['types'] as List;
      expect(types.any((t) => t['name'] == 'hsrv_cache_a'), isTrue);
    });
  });
}
