/// data_source_resolver 缓存优先回归测试。
///
/// 覆盖 bug：`resolveDataSource` 曾自造“空壳 DataType”（persistentKey 为 null）传给
/// `orch.get`，导致数据中枢的“缓存优先”读取被绕过——即便数据源在注册时声明了
/// persistentKey，也会每次真实拉取。修复后 `resolveDataSource` 复用中枢**已注册**的
/// DataType（携带 persistentKey/ttl），因此有缓存时不再重复拉取。
///
/// 运行：cd evg-base && flutter test test/renderer/atomic/data_source_resolver_cache_test.dart
library;
import 'dart:io';

import 'package:evergreen_base/core/data/data.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/renderer/atomic/data_source_resolver.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // flutter test 环境无 path_provider 平台实现，mock getApplicationSupportDirectory
  // 指向临时目录，使 Cache 的文件读写可用（否则抛 MissingPluginException）。
  setUpAll(() {
    final tmp = Directory.systemTemp.createTempSync('dsr_cache_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => tmp.path,
    );
  });

  // 唯一 name/persistentKey，避免与其它测试的全局文件缓存冲突。
  const cachedType = DataType<Map<String, dynamic>>(
    name: 'dsr_cache_test',
    persistentKey: 'dsr_cache_test:key',
    ttl: Duration(minutes: 5),
  );

  setUp(() async {
    final cache = await Cache.getInstance();
    await cache.clear();
  });

  tearDown(() async {
    final cache = await Cache.getInstance();
    await cache.clear();
  });

  test('复用已注册 DataType → 有缓存时 get 不重复拉取', () async {
    await Cache.getInstance(); // 确保缓存单例已就绪（否则读写均 no-op）
    int calls = 0;
    final orch = DataOrchestrator();
    orch.register(cachedType, () async {
      calls++;
      return {'value': 'v$calls'};
    });

    const ds = DataSourceDescriptor(endpoint: 'orch://dsr_cache_test');

    // 首次：无缓存 → 真实拉取并写缓存（calls==1）。
    final first = await resolveDataSource(ds: ds, orch: orch);
    expect((first as Map)['value'], 'v1');
    expect(calls, 1);

    // 二次：命中缓存 → 不再调 fetcher（calls 仍为 1）。
    // 修复前此处会因空壳 DataType(persistentKey=null) 绕过缓存导致 calls==2。
    final second = await resolveDataSource(ds: ds, orch: orch);
    expect((second as Map)['value'], 'v1');
    expect(calls, 1, reason: '声明了 persistentKey 时应命中缓存，不应重复拉取');
  });

  test('forceRefresh → 绕过缓存强制重拉（供自动刷新使用）', () async {
    await Cache.getInstance();
    int calls = 0;
    final orch = DataOrchestrator();
    orch.register(cachedType, () async {
      calls++;
      return {'value': 'v$calls'};
    });

    const ds = DataSourceDescriptor(endpoint: 'orch://dsr_cache_test');
    await resolveDataSource(ds: ds, orch: orch); // calls==1，写缓存
    final refreshed =
        await resolveDataSource(ds: ds, orch: orch, forceRefresh: true);
    expect((refreshed as Map)['value'], 'v2');
    expect(calls, 2, reason: 'forceRefresh 应绕过缓存强制重抓');
  });

  test('未注册类型 → 优雅降级返回 null（不抛到 UI）', () async {
    final orch = DataOrchestrator();
    const ds = DataSourceDescriptor(endpoint: 'orch://dsr_not_registered_xyz');
    final r = await resolveDataSource(ds: ds, orch: orch);
    expect(r, isNull);
  });
}
