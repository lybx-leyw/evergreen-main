/// 回归测试：卸载路径必须以「扫描时捕获的真实磁盘目录」为准，
/// 不能靠 manifest 的 id 反推（id 可能与文件夹名不同，反推指向不存在路径→卸载静默失败）。
///
/// 纯 Dart，不挂载 widget、不碰 Riverpod/SharedPreferences，绝不挂死。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:evergreen_base/renderer/templates/v4_modle/components/marketplace/marketplace_scan.dart';

void main() {
  group('scanPluginManifests 目录映射', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('mp_uninstall_');
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('id 等于文件夹名时，dirs[id] 指向该文件夹', () {
      final pluginDir = Directory(p.join(tmp.path, 'myplugin'))..createSync();
      Directory(p.join(pluginDir.path, 'module')).createSync();
      File(p.join(pluginDir.path, 'module', 'manifest.json'))
          .writeAsStringSync('''
{
  "type": "module",
  "id": "myplugin",
  "name": "My Plugin"
}
''');

      final (descriptors, dirs) = scanPluginManifests(tmp.path);

      expect(descriptors.length, 1);
      expect(descriptors.first.id, 'myplugin');
      expect(dirs['myplugin'], p.join(tmp.path, 'myplugin'));
    });

    test('id 不等于文件夹名时，dirs[id] 仍指向真实文件夹（而非 id 拼出的错误路径）', () {
      // 模拟真实坑：文件夹名 "weird-folder"，但 manifest 的 id 是 "different-id"
      final pluginDir = Directory(p.join(tmp.path, 'weird-folder'))..createSync();
      Directory(p.join(pluginDir.path, 'module')).createSync();
      File(p.join(pluginDir.path, 'module', 'manifest.json'))
          .writeAsStringSync('''
{
  "type": "module",
  "id": "different-id",
  "name": "Weird Plugin"
}
''');

      final (descriptors, dirs) = scanPluginManifests(tmp.path);

      expect(descriptors.length, 1);
      expect(descriptors.first.id, 'different-id');
      // 关键断言：路径来自文件夹名，不是 id
      expect(dirs['different-id'], p.join(tmp.path, 'weird-folder'));
      expect(dirs['different-id'], isNot(p.join(tmp.path, 'different-id')));
    });

    test('卸载删除 dirs[id] 能真实移除磁盘目录（模拟 _doUninstall 的核心逻辑）', () {
      final pluginDir = Directory(p.join(tmp.path, 'weird-folder'))..createSync();
      Directory(p.join(pluginDir.path, 'module')).createSync();
      File(p.join(pluginDir.path, 'module', 'manifest.json'))
          .writeAsStringSync('''
{
  "type": "module",
  "id": "different-id",
  "name": "Weird Plugin"
}
''');

      final (descriptors, dirs) = scanPluginManifests(tmp.path);
      final id = descriptors.first.id;

      // 复刻 _doUninstall 的删除决策：优先用捕获目录，回退 pluginsDir/id
      final captured = dirs[id];
      final dirPath = (captured != null && captured.isNotEmpty)
          ? captured
          : p.join(tmp.path, id);
      final toDelete = Directory(dirPath);
      expect(toDelete.existsSync(), isTrue);
      toDelete.deleteSync(recursive: true);

      // 真实文件夹已被删除
      expect(Directory(p.join(tmp.path, 'weird-folder')).existsSync(), isFalse);
      // 反推路径（错误做法）并不存在，验证我们确实没去删一个不存在的 id 路径
      expect(Directory(p.join(tmp.path, 'different-id')).existsSync(), isFalse);
    });

    test('pluginsDir 不存在时返回空且 darts 安全', () {
      final missing = p.join(tmp.path, 'does-not-exist');
      final (descriptors, dirs) = scanPluginManifests(missing);
      expect(descriptors, isEmpty);
      expect(dirs, isEmpty);
    });

    test('隐藏目录（.开头）与文件被跳过', () {
      Directory(p.join(tmp.path, '.hidden')).createSync();
      File(p.join(tmp.path, 'a-file.txt')).writeAsStringSync('x');
      // 无有效插件
      final (descriptors, dirs) = scanPluginManifests(tmp.path);
      expect(descriptors, isEmpty);
      expect(dirs, isEmpty);
    });
  });

  group('scanPluginManifests 覆盖非 module 类型', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('mp_types_');
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('agent 类型（无 id、无 type）也能被发现，id 回退文件夹名', () {
      // 模拟 python-runner/agent/manifest.json：只有 name/description，无 id、无 type
      final dir = Directory(p.join(tmp.path, 'python-runner'))..createSync();
      Directory(p.join(dir.path, 'agent')).createSync();
      File(p.join(dir.path, 'agent', 'manifest.json'))
          .writeAsStringSync('''
{
  "name": "python_runner",
  "description": "Python 解释器 + pip 包管理"
}
''');

      final (descriptors, dirs) = scanPluginManifests(tmp.path);

      expect(descriptors.length, 1);
      final info = descriptors.first;
      expect(info.id, 'python-runner'); // 回退文件夹名
      expect(info.name, 'python_runner');
      expect(info.type, 'agent'); // 由子目录推断
      expect(info.isModule, isFalse);
      expect(dirs['python-runner'], p.join(tmp.path, 'python-runner'));
    });

    test('data-source 类型（无 id，有 type）被发现', () {
      final dir = Directory(p.join(tmp.path, 'custom-scraper'))..createSync();
      Directory(p.join(dir.path, 'data')).createSync();
      File(p.join(dir.path, 'data', 'manifest.json'))
          .writeAsStringSync('''
{
  "type": "data-source",
  "script": "scraper.exe",
  "dataTypes": []
}
''');

      final (descriptors, dirs) = scanPluginManifests(tmp.path);

      expect(descriptors.length, 1);
      final info = descriptors.first;
      expect(info.id, 'custom-scraper');
      expect(info.type, 'data-source');
      expect(info.isModule, isFalse);
      expect(info.typeLabel, '数据源');
    });

    test('一个文件夹含 module + data 时，两种类型都作为独立卡片出现', () {
      final dir = Directory(p.join(tmp.path, 'showcase'))..createSync();
      Directory(p.join(dir.path, 'module')).createSync();
      Directory(p.join(dir.path, 'data')).createSync();
      File(p.join(dir.path, 'module', 'manifest.json')).writeAsStringSync('''
{
  "type": "module",
  "id": "showcase",
  "name": "展示模块"
}
''');
      File(p.join(dir.path, 'data', 'manifest.json')).writeAsStringSync('''
{
  "type": "data-source",
  "id": "showcase-data",
  "name": "展示数据源"
}
''');

      final (descriptors, dirs) = scanPluginManifests(tmp.path);

      expect(descriptors.length, 2);
      final types = descriptors.map((d) => d.type).toList();
      expect(types, contains('module'));
      expect(types, contains('data-source'));
      // 两个卡片都指向同一文件夹，卸载任一都会删除整个文件夹
      expect(dirs['showcase'], p.join(tmp.path, 'showcase'));
      expect(dirs['showcase-data'], p.join(tmp.path, 'showcase'));
    });
  });
}
