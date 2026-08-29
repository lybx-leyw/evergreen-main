/// ModuleStorageService 测试（T5-storage）—— 插件级 JSON 键值存储器。
///
/// 覆盖：写→读回、readSync 内存命中、覆盖写、remove、clear、null 删除、原子写
/// （文件存在且 JSON 合法）、路径沙箱（pluginId 含 `../` 拒绝）、多实例隔离、
/// 跨实例读盘可见、幂等空文件、并发写串行、大小上限与值校验。
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../services/module_storage_service.dart';

Directory tempRoot(String prefix) {
  final dir = Directory.systemTemp.createTempSync(prefix);
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

/// 读取 storage.json 原始解码结果（断言落盘用）。
Map<String, dynamic> readDisk(ModuleStorageService s) =>
    jsonDecode(File(s.storagePath).readAsStringSync()) as Map<String, dynamic>;

void main() {
  group('ModuleStorageService', () {
    test('write 后 readSync 读回；storage.json 存在、JSON 合法且无临时文件残留', () async {
      final root = tempRoot('mss_write_');
      final s =
          ModuleStorageService.forPlugin('my-plugin', pluginsRoot: root.path);
      await s.write('name', 'Evergreen');
      await s.write('count', 3);
      await s.write('ok', true);
      await s.write('nested', {
        'a': [1, 2],
        'b': null,
      });

      expect(s.readSync('name'), 'Evergreen');
      expect(s.readSync('count'), 3);
      expect(s.readSync('ok'), isTrue);
      expect(s.readSync('nested'), {
        'a': [1, 2],
        'b': null,
      });
      expect(s.readSync('missing'), isNull);

      // 落盘文件存在、合法、内容与内存一致
      expect(File(s.storagePath).existsSync(), isTrue);
      final disk = readDisk(s);
      expect(disk['name'], 'Evergreen');
      expect(disk['count'], 3);
      expect(disk['nested'], {
        'a': [1, 2],
        'b': null,
      });
      // 原子写：无临时文件残留
      expect(File('${s.storagePath}.tmp').existsSync(), isFalse);
    });

    test('readSync 首次读盘加载全量，之后内存命中（删盘仍可读）', () async {
      final root = tempRoot('mss_mem_');
      final writer =
          ModuleStorageService.forPlugin('p', pluginsRoot: root.path);
      await writer.write('k', 'v');

      final s = ModuleStorageService.forPlugin('p', pluginsRoot: root.path);
      expect(s.isLoaded, isFalse);
      expect(s.readSync('k'), 'v'); // 首次访问同步读盘全量
      expect(s.isLoaded, isTrue);
      // 删除盘上文件：内存命中仍返回（同步热路径零 I/O）
      File(s.storagePath).deleteSync();
      expect(s.readSync('k'), 'v');
    });

    test('覆盖写：后写覆盖前写（内存 + 落盘）', () async {
      final root = tempRoot('mss_over_');
      final s = ModuleStorageService.forPlugin('p', pluginsRoot: root.path);
      await s.write('k', 1);
      await s.write('k', 2);
      expect(s.readSync('k'), 2);
      expect(readDisk(s)['k'], 2);
    });

    test('remove 删除 key（内存 + 落盘）', () async {
      final root = tempRoot('mss_rm_');
      final s = ModuleStorageService.forPlugin('p', pluginsRoot: root.path);
      await s.write('a', 1);
      await s.write('b', 2);
      await s.remove('a');
      expect(s.readSync('a'), isNull);
      expect(s.readSync('b'), 2);
      final disk = readDisk(s);
      expect(disk.containsKey('a'), isFalse);
      expect(disk['b'], 2);
      // 删不存在的 key 无害
      await s.remove('never-existed');
    });

    test('write null 删除 key（对齐 localStorage.removeItem 语义）', () async {
      final root = tempRoot('mss_null_');
      final s = ModuleStorageService.forPlugin('p', pluginsRoot: root.path);
      await s.write('k', 'v');
      await s.write('k', null);
      expect(s.readSync('k'), isNull);
      expect((await s.readAll()).containsKey('k'), isFalse);
      expect(readDisk(s).containsKey('k'), isFalse);
    });

    test('clear 清空并删除 storage.json', () async {
      final root = tempRoot('mss_clear_');
      final s = ModuleStorageService.forPlugin('p', pluginsRoot: root.path);
      await s.write('a', 1);
      await s.write('b', 2);
      expect(File(s.storagePath).existsSync(), isTrue);
      await s.clear();
      expect(s.readSync('a'), isNull);
      expect(s.readSync('b'), isNull);
      expect(await s.readAll(), isEmpty);
      expect(File(s.storagePath).existsSync(), isFalse);
    });

    test('原子写：连续写后文件始终存在且为合法 JSON（崩溃不损坏语义）', () async {
      final root = tempRoot('mss_atomic_');
      final s = ModuleStorageService.forPlugin('p', pluginsRoot: root.path);
      for (var i = 0; i < 50; i++) {
        await s.write('k$i', 'value-$i');
        final raw = File(s.storagePath).readAsStringSync();
        expect(jsonDecode(raw), isA<Map<String, dynamic>>());
        expect(File('${s.storagePath}.tmp').existsSync(), isFalse);
      }
      expect(s.readSync('k49'), 'value-49');
    });

    test('超限写入被拒绝（抛 ModuleStorageException），既有文件不受损', () async {
      final root = tempRoot('mss_size_');
      final s = ModuleStorageService.forPlugin('p', pluginsRoot: root.path);
      await s.write('small', 'ok');
      final big = 'x' * (kModuleStorageMaxBytes + 1);
      await expectLater(
          s.write('big', big), throwsA(isA<ModuleStorageException>()));
      // 盘上旧数据仍在、新 key 未落盘
      final disk = readDisk(s);
      expect(disk['small'], 'ok');
      expect(disk.containsKey('big'), isFalse);
      // 内存保留最新写入（调用方应视为写入失败——见 API 注释）
      expect(s.readSync('big'), big);
    });

    test('非 JSON 可序列化值写入被同步拒绝（内存不变）', () async {
      final root = tempRoot('mss_badval_');
      final s = ModuleStorageService.forPlugin('p', pluginsRoot: root.path);
      await s.write('good', 'v');
      // write 对不可序列化值**同步** fail-fast（先校验后改内存）
      expect(() => s.write('bad', Object()),
          throwsA(isA<ModuleStorageException>()));
      expect(s.readSync('bad'), isNull);
      expect(s.readSync('good'), 'v');
      expect(readDisk(s).containsKey('bad'), isFalse);
    });

    test('pluginId 校验：拒绝路径穿越/分隔符/纯数字/大写/超长/空（对齐 htmlPluginIdError）', () {
      final root = tempRoot('mss_id_');
      for (final bad in [
        '',
        '../evil',
        '..',
        'my/plugin',
        'a\\b',
        '5',
        '123',
        'My-Plugin',
        'my plugin',
        'a' * 65,
      ]) {
        expect(
            () => ModuleStorageService.forPlugin(bad, pluginsRoot: root.path),
            throwsArgumentError,
            reason: 'bad pluginId: "$bad"');
        expect(moduleStoragePluginIdError(bad), isNotNull);
      }
      for (final good in ['my-dashboard', 'a', 'my2-plugin-3', 'x']) {
        expect(moduleStoragePluginIdError(good), isNull);
        final s = ModuleStorageService.forPlugin(good, pluginsRoot: root.path);
        // 落盘路径限定在 pluginsRoot 内（PathSandbox confine）
        expect(s.storagePath, startsWith(root.path));
      }
    });

    test('多实例隔离：不同 pluginId 互不可见', () async {
      final root = tempRoot('mss_iso_');
      final a = ModuleStorageService.forPlugin('alpha', pluginsRoot: root.path);
      final b = ModuleStorageService.forPlugin('beta', pluginsRoot: root.path);
      await a.write('k', 'A');
      expect(a.readSync('k'), 'A');
      expect(b.readSync('k'), isNull);
      expect((await b.readAll()).containsKey('k'), isFalse);
    });

    test('readAll 重新读盘：另一实例写入立即可见（数据源 fetcher 读盘语义）', () async {
      final root = tempRoot('mss_reload_');
      final writer =
          ModuleStorageService.forPlugin('p', pluginsRoot: root.path);
      await writer.write('k', 'v1');

      final reader =
          ModuleStorageService.forPlugin('p', pluginsRoot: root.path);
      expect((await reader.readAll())['k'], 'v1'); // 首次加载
      await writer.write('k', 'v2');
      await writer.write('extra', true);
      final again = await reader.readAll();
      expect(again['k'], 'v2'); // 重新读盘可见外部写入
      expect(again['extra'], isTrue);
    });

    test('storage.json 不存在：readSync 返回 null、readAll 返回空 Map（幂等）', () async {
      final root = tempRoot('mss_missing_');
      final s = ModuleStorageService.forPlugin('ghost', pluginsRoot: root.path);
      expect(s.readSync('anything'), isNull);
      expect(await s.readAll(), isEmpty);
      // 写后正常创建目录结构
      await s.write('k', 'v');
      expect(File(s.storagePath).existsSync(), isTrue);
    });

    test('ensureLoaded 预热加载', () async {
      final root = tempRoot('mss_warm_');
      final writer =
          ModuleStorageService.forPlugin('p', pluginsRoot: root.path);
      await writer.write('k', 'v');
      final s = ModuleStorageService.forPlugin('p', pluginsRoot: root.path);
      expect(s.isLoaded, isFalse);
      await s.ensureLoaded();
      expect(s.isLoaded, isTrue);
      expect(s.readSync('k'), 'v');
    });

    test('并发写串行落盘，最终一致（单 isolate Future 链）', () async {
      final root = tempRoot('mss_concur_');
      final s = ModuleStorageService.forPlugin('p', pluginsRoot: root.path);
      await Future.wait([for (var i = 0; i < 20; i++) s.write('k$i', i)]);
      final all = await s.readAll();
      expect(all.length, 20);
      expect(all['k19'], 19);
      final disk = readDisk(s);
      expect(disk.length, 20);
      expect(disk['k19'], 19);
    });
  });
}
