/// registerModuleStorageSource 测试（T5-storage）—— 插件模块存储 → 数据中枢数据源。
///
/// 覆盖：注册后 orch.getByName 返回 storage 内容、storage 更新后重新 get 读到新值
/// （fetcher 读盘）、未注册名、重复注册覆盖、unregister 清除、storage.json 不存在
/// 幂等（fetcher 返回空 Map 不抛错）、自定义 category、非法 pluginId 拒绝。
library;

import 'dart:io';

import 'package:evergreen_base/core/services/module_storage_service.dart';
import 'package:test/test.dart';

import '../exceptions.dart';
import '../orchestrator.dart';
import '../register_module_storage.dart';

Directory tempRoot(String prefix) {
  final dir = Directory.systemTemp.createTempSync(prefix);
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

void main() {
  group('registerModuleStorageSource', () {
    test('注册后 orch.getByName 返回 storage 内容；类型元信息符合契约', () async {
      final root = tempRoot('rms_reg_');
      final orch = DataOrchestrator();
      final storage =
          ModuleStorageService.forPlugin('my-plugin', pluginsRoot: root.path);
      await storage.write('score', 99);
      await storage.write('title', 'hello');

      final names = registerModuleStorageSource(
          orch: orch, pluginId: 'my-plugin', pluginsRoot: root.path);
      expect(names, ['my-plugin_storage']);

      final data = await orch.getByName('my-plugin_storage');
      expect(data, isA<Map<String, dynamic>>());
      final map = data as Map<String, dynamic>;
      expect(map['score'], 99);
      expect(map['title'], 'hello');

      final type = orch.typeByName('my-plugin_storage')!;
      expect(type.label, 'my-plugin 存储'); // displayName = <pluginId> 存储
      expect(type.category, '未分类'); // 缺省分类
      expect(type.persistentKey, isNull); // storage.json 即持久化，不二次缓存
      expect(type.ttl, kModuleStorageSourceTtl); // 默认 30s 短 TTL
      expect(orch.status('my-plugin_storage')!.connected, isTrue);
    });

    test('storage 更新后重新 get 读到新值（fetcher 读盘，跨实例可见）', () async {
      final root = tempRoot('rms_fetch_');
      final orch = DataOrchestrator();
      final writer =
          ModuleStorageService.forPlugin('p1', pluginsRoot: root.path);
      await writer.write('k', 'v1');
      registerModuleStorageSource(
          orch: orch, pluginId: 'p1', pluginsRoot: root.path);

      expect((await orch.getByName('p1_storage'))['k'], 'v1');

      // 经另一个实例写入（模拟 renderer 桥写路径），重新 get 必须读到新值
      await writer.write('k', 'v2');
      await writer.write('extra', true);
      final again = await orch.getByName('p1_storage');
      expect(again['k'], 'v2');
      expect(again['extra'], isTrue);
    });

    test('未注册名：typeByName 返回 null、getByName 抛 DataTypeNotRegisteredException',
        () async {
      final orch = DataOrchestrator();
      expect(orch.typeByName('nope_storage'), isNull);
      await expectLater(orch.getByName('nope_storage'),
          throwsA(isA<DataTypeNotRegisteredException>()));
    });

    test('重复注册覆盖（对齐 orchestrator 覆盖语义，registeredTypes 不重复）', () async {
      final root = tempRoot('rms_over_');
      final orch = DataOrchestrator();
      registerModuleStorageSource(
          orch: orch, pluginId: 'p1', pluginsRoot: root.path, category: '插件');
      // 覆盖注册：category 回到缺省「未分类」，fetcher 被替换仍可拉取
      registerModuleStorageSource(
          orch: orch, pluginId: 'p1', pluginsRoot: root.path);

      final type = orch.typeByName('p1_storage')!;
      expect(type.category, '未分类');
      expect(orch.registeredTypes.where((n) => n == 'p1_storage').length, 1);
      // 覆盖后的 fetcher 仍返回 storage 内容
      final storage =
          ModuleStorageService.forPlugin('p1', pluginsRoot: root.path);
      await storage.write('k', 'overwritten');
      expect((await orch.getByName('p1_storage'))['k'], 'overwritten');
    });

    test('unregister 清除注册；重复注销无害（no-op）', () async {
      final root = tempRoot('rms_unreg_');
      final orch = DataOrchestrator();
      final storage =
          ModuleStorageService.forPlugin('p1', pluginsRoot: root.path);
      await storage.write('k', 'v');
      registerModuleStorageSource(
          orch: orch, pluginId: 'p1', pluginsRoot: root.path);
      expect(orch.typeByName('p1_storage'), isNotNull);

      unregisterModuleStorageSource(orch, 'p1');
      expect(orch.typeByName('p1_storage'), isNull);
      expect(orch.registeredTypes, isNot(contains('p1_storage')));
      expect(orch.status('p1_storage'), isNull);
      await expectLater(orch.getByName('p1_storage'),
          throwsA(isA<DataTypeNotRegisteredException>()));

      // 幂等：重复注销 no-op
      unregisterModuleStorageSource(orch, 'p1');

      // 注销不删除 storage.json（文件归模块存储生命周期）
      expect(File(storage.storagePath).existsSync(), isTrue);
    });

    test('storage.json 不存在：fetcher 返回空 Map（源可达，不抛错）', () async {
      final root = tempRoot('rms_empty_');
      final orch = DataOrchestrator();
      registerModuleStorageSource(
          orch: orch, pluginId: 'ghost', pluginsRoot: root.path);

      // fetcher 返回 {} → 中枢空数据门控：get 返回 null（不抛），状态标记
      // 「源可达但数据为空」（区别于拉取失败）
      final data = await orch.getByName('ghost_storage');
      expect(data, isNull);
      expect(orch.status('ghost_storage')!.lastError, contains('源可达但数据为空'));
      // 幂等：重复 get 不抛
      expect(await orch.getByName('ghost_storage'), isNull);
    });

    test('自定义 category 透传', () async {
      final root = tempRoot('rms_cat_');
      final orch = DataOrchestrator();
      registerModuleStorageSource(
          orch: orch,
          pluginId: 'p1',
          pluginsRoot: root.path,
          category: 'HTML 插件');
      expect(orch.typeByName('p1_storage')!.category, 'HTML 插件');
    });

    test('非法 pluginId：注册即抛 ArgumentError（fail-fast）', () {
      final root = tempRoot('rms_badid_');
      final orch = DataOrchestrator();
      expect(
          () => registerModuleStorageSource(
              orch: orch, pluginId: '../evil', pluginsRoot: root.path),
          throwsArgumentError);
      expect(
          () => registerModuleStorageSource(
              orch: orch, pluginId: '5', pluginsRoot: root.path),
          throwsArgumentError);
      expect(orch.typeByName('evil_storage'), isNull);
    });

    test('类型名格式：<pluginId>_storage（防与插件声明的其它数据源冲突）', () {
      expect(moduleStorageTypeName('my-plugin'), 'my-plugin_storage');
      expect(moduleStorageTypeName('a'), 'a_storage');
    });
  });
}
