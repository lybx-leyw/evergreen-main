/// 文件型插件（`file-source`）清单解析与注册测试（P1）。
///
/// 方案：`docs/plugin-registry/file-source-plugin-plan-v1.md` §2 / §7。
///
/// 锁定契约：
///  1. `type` 判别严格为 `"file-source"`，与 `"data-source"` **互不干扰**；
///  2. `script` / `process` 互斥二选一；`files` 非空；
///  3. 复用既有解析器：TTL（默认 **24h**，比 data-source 的 5m 长）、
///     `androidSupport` fail-closed、`timeoutSeconds`（1..3600）、`auth`；
///  4. `accept` 扩展名白名单规范化（小写 + 补前导点）；
///  5. **A7 零行为变化**：`files/` 与 `data/` 两条扫描路径互不误拾。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:evergreen_base/core/data/orchestrator.dart';
import 'package:evergreen_base/core/data/plugin/file_source_manifest.dart';
import 'package:evergreen_base/core/data/register_data_source.dart';
import 'package:evergreen_base/core/data/register_file_source.dart';

/// 在临时目录下造一个插件目录，写入 `files/manifest.json`。
Directory makePlugin(String manifestJson, {String sub = 'files'}) {
  final root = Directory.systemTemp.createTempSync('fsrc_');
  final d = Directory(p.join(root.path, sub))..createSync(recursive: true);
  File(p.join(d.path, 'manifest.json')).writeAsStringSync(manifestJson);
  return root;
}

Map<String, dynamic> minimal({
  List<Map<String, dynamic>>? files,
  String? script = 'discover.py',
  Object? process,
  Object? accept,
}) =>
    {
      'type': 'file-source',
      'id': 'demo',
      'name': '演示文件源',
      if (script != null) 'script': script,
      if (process != null) 'process': process,
      'files': files ??
          [
            {
              'name': 'demo_files',
              'typeArg': 'demo_files',
              if (accept != null) 'accept': accept,
            }
          ],
    };

void main() {
  group('FileSourceManifest 解析', () {
    test('合法清单：解析出 files 与缺省值', () {
      final m = FileSourceManifest.fromJson(minimal());
      expect(m.id, equals('demo'));
      expect(m.name, equals('演示文件源'));
      expect(m.script, equals('discover.py'));
      expect(m.runtime, equals('native'));
      expect(m.androidSupport, isTrue);
      expect(m.auth, isNull);
      expect(m.files, hasLength(1));
    });

    test('type 必须精确为 "file-source"', () {
      final bad = minimal()..['type'] = 'data-source';
      expect(() => FileSourceManifest.fromJson(bad),
          throwsA(isA<FormatException>()));
    });

    test('script 与 process 互斥', () {
      expect(
          () => FileSourceManifest.fromJson(
              minimal(process: 'server.py')), // script 仍在 → 冲突
          throwsA(isA<FormatException>()));
      // 只给 process → 合法
      final m = FileSourceManifest.fromJson(minimal(script: null, process: 'server.py'));
      expect(m.processExe, equals('server.py'));
    });

    test('两者皆缺 → FormatException', () {
      expect(() => FileSourceManifest.fromJson(minimal(script: null)),
          throwsA(isA<FormatException>()));
    });

    test('files 缺失或空数组 → FormatException', () {
      final empty = minimal()..['files'] = <Map<String, dynamic>>[];
      expect(() => FileSourceManifest.fromJson(empty),
          throwsA(isA<FormatException>()));
      final missing = minimal()..remove('files');
      expect(() => FileSourceManifest.fromJson(missing),
          throwsA(isA<FormatException>()));
    });

    test('androidSupport fail-closed：非 bool 视为 false', () {
      for (final v in ['false', 1, const <int>[], {'a': 1}]) {
        final m = FileSourceManifest.fromJson(minimal()..['androidSupport'] = v);
        expect(m.androidSupport, isFalse, reason: '非 bool 值 $v 应 fail-closed');
      }
      final t = FileSourceManifest.fromJson(minimal()..['androidSupport'] = true);
      expect(t.androidSupport, isTrue);
    });

    test('auth 复用 DataSourceAuth 语义', () {
      final m = FileSourceManifest.fromJson(minimal()
        ..['auth'] = {
          'sessionProvider': 'zju',
          'sessionDomain': 'classroom.zju.edu.cn',
          'credentialKeys': ['ZJU_USERNAME'],
        });
      expect(m.auth, isNotNull);
      expect(m.auth!.sessionProvider, equals('zju'));
      expect(m.auth!.sessionDomain, equals('classroom.zju.edu.cn'));
      expect(m.auth!.credentialKeys, equals(['ZJU_USERNAME']));
    });
  });

  group('FileSourceDecl', () {
    test('默认 TTL 为 24h（比 data-source 的 5m 长，避免被 5 分钟 tick 反复发现）', () {
      final d = FileSourceDecl.fromJson({'name': 'x'});
      expect(d.ttl, equals(const Duration(hours: 24)));
      expect(d.category, equals('文件'));
    });

    test('timeoutSeconds 复用 per-type 超时解析器（1..3600）', () {
      expect(FileSourceDecl.fromJson({'name': 'x', 'timeoutSeconds': 1800}).timeout,
          equals(const Duration(minutes: 30)));
      expect(FileSourceDecl.fromJson({'name': 'x', 'timeoutSeconds': 0}).timeout,
          isNull);
      expect(FileSourceDecl.fromJson({'name': 'x', 'timeoutSeconds': 99999}).timeout,
          isNull);
    });

    test('name 必填', () {
      expect(() => FileSourceDecl.fromJson({'title': '无 name'}),
          throwsA(isA<FormatException>()));
    });

    test('accept 规范化：小写 + 补前导点 + 去重', () {
      final d = FileSourceDecl.fromJson({
        'name': 'x',
        'accept': ['.MP4', 'mp4', 'PDF', '  .m3u8  ', '', 123],
      });
      expect(d.accept, equals(['.mp4', '.pdf', '.m3u8']));
    });

    test('acceptsPath：未声明白名单恒 true；声明后按后缀（大小写不敏感）', () {
      final open = FileSourceDecl.fromJson({'name': 'x'});
      expect(open.acceptsPath('/a/b.anything'), isTrue);

      final d = FileSourceDecl.fromJson({'name': 'x', 'accept': ['.mp4']});
      expect(d.acceptsPath('/cache/A.MP4'), isTrue);
      expect(d.acceptsPath('/cache/a.txt'), isFalse);
      expect(d.acceptsPath('/cache/mp4'), isFalse, reason: '必须是后缀不是包含');
    });

    test('toJson 往返', () {
      final d = FileSourceDecl.fromJson({
        'name': 'v',
        'title': '录播',
        'ttl': '6h',
        'timeoutSeconds': 600,
        'accept': ['.mp4'],
        'persistentKey': 'v1',
      });
      final back = FileSourceDecl.fromJson(d.toJson());
      expect(back.name, equals('v'));
      expect(back.title, equals('录播'));
      expect(back.ttl, equals(const Duration(hours: 6)));
      expect(back.timeout, equals(const Duration(minutes: 10)));
      expect(back.accept, equals(['.mp4']));
      expect(back.persistentKey, equals('v1'));
    });
  });

  group('registerFileSourcesFromManifest', () {
    test('无 files/manifest.json → 空（不抛）', () {
      final dir = Directory.systemTemp.createTempSync('fsrc_none_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final r = registerFileSourcesFromManifest(
          orch: DataOrchestrator(), pluginDir: dir.path, projectRoot: '.');
      expect(r, isEmpty);
    });

    test('files/manifest.json 但 type 为 data-source → 跳过（互不误拾）', () {
      final dir = makePlugin('{"type":"data-source","script":"x.py","dataTypes":[{"name":"t"}]}');
      addTearDown(() => dir.deleteSync(recursive: true));
      final orch = DataOrchestrator();
      final r = registerFileSourcesFromManifest(
          orch: orch, pluginDir: dir.path, projectRoot: '.');
      expect(r, isEmpty);
      expect(orch.typeByName('t') != null, isFalse, reason: '不该注册 data-source 的类型');
    });

    test('合法清单 → 注册 org:// 类型（脚本不存在仍注册）', () {
      final dir = makePlugin('''
{
  "type": "file-source",
  "id": "demo",
  "name": "演示",
  "script": "discover.py",
  "runtime": "python",
  "files": [
    {"name": "demo_files", "typeArg": "demo_files", "title": "演示文件",
     "ttl": "6h", "timeoutSeconds": 900, "accept": [".mp4"]}
  ]
}
''');
      addTearDown(() => dir.deleteSync(recursive: true));
      final orch = DataOrchestrator();
      final r = registerFileSourcesFromManifest(
          orch: orch, pluginDir: dir.path, projectRoot: '.');
      expect(r, equals(['demo_files']));
      expect(orch.typeByName('demo_files') != null, isTrue);
    });

    test('onlyType 过滤：只注册指定类型', () {
      final dir = makePlugin('''
{
  "type": "file-source", "script": "d.py",
  "files": [{"name": "a"}, {"name": "b"}]
}
''');
      addTearDown(() => dir.deleteSync(recursive: true));
      final orch = DataOrchestrator();
      final r = registerFileSourcesFromManifest(
          orch: orch, pluginDir: dir.path, projectRoot: '.', onlyType: 'b');
      expect(r, equals(['b']));
      expect(orch.typeByName('a') != null, isFalse);
      expect(orch.typeByName('b') != null, isTrue);
    });

    test('模型二（process）尚未支持 → 记 warn 跳过（不静默）', () {
      final dir = makePlugin('''
{
  "type": "file-source", "process": "server.py",
  "files": [{"name": "p1"}]
}
''');
      addTearDown(() => dir.deleteSync(recursive: true));
      final orch = DataOrchestrator();
      final r = registerFileSourcesFromManifest(
          orch: orch, pluginDir: dir.path, projectRoot: '.');
      expect(r, isEmpty);
      expect(orch.typeByName('p1') != null, isFalse);
    });

    test('androidSupport=false 在安卓上跳过（此处非安卓，仍注册）', () {
      final dir = makePlugin('''
{
  "type": "file-source", "script": "d.py", "androidSupport": false,
  "files": [{"name": "n1"}]
}
''');
      addTearDown(() => dir.deleteSync(recursive: true));
      final orch = DataOrchestrator();
      final r = registerFileSourcesFromManifest(
          orch: orch, pluginDir: dir.path, projectRoot: '.');
      if (Platform.isAndroid) {
        expect(r, isEmpty);
      } else {
        expect(r, equals(['n1']));
      }
    });
  });

  group('A7 零行为变化：两条扫描路径互不误拾', () {
    test('scanAndLoadFileSources 不碰 data/ 下的 data-source', () async {
      final root = Directory.systemTemp.createTempSync('fsrc_mix_');
      addTearDown(() => root.deleteSync(recursive: true));
      // 插件 A：只有业务型
      final a = Directory(p.join(root.path, 'pluginA', 'data'))
        ..createSync(recursive: true);
      File(p.join(a.path, 'manifest.json')).writeAsStringSync(
          '{"type":"data-source","script":"s.py","dataTypes":[{"name":"biz"}]}');
      // 插件 B：只有文件型
      final b = Directory(p.join(root.path, 'pluginB', 'files'))
        ..createSync(recursive: true);
      File(p.join(b.path, 'manifest.json')).writeAsStringSync(
          '{"type":"file-source","script":"d.py","files":[{"name":"fl"}]}');

      final orch = DataOrchestrator();
      final got = await scanAndLoadFileSources(
          pluginsDir: root.path, orchestrator: orch, projectRoot: '.');
      expect(got, equals(['fl']));
      expect(orch.typeByName('biz'), isNull, reason: 'data-source 不该被 file-source 扫描拾取');
      expect(orch.typeByName('fl'), isNotNull);
    });

    test('registerDataSourcesFromManifest 不碰 files/ 下的 file-source', () {
      final root = Directory.systemTemp.createTempSync('fsrc_mix2_');
      addTearDown(() => root.deleteSync(recursive: true));
      final b = Directory(p.join(root.path, 'pluginB', 'files'))
        ..createSync(recursive: true);
      File(p.join(b.path, 'manifest.json')).writeAsStringSync(
          '{"type":"file-source","script":"d.py","files":[{"name":"fl"}]}');

      final orch = DataOrchestrator();
      final r = registerDataSourcesFromManifest(
          orch: orch, pluginDir: p.join(root.path, 'pluginB'), projectRoot: '.');
      expect(r, isEmpty);
      expect(orch.typeByName('fl') != null, isFalse);
    });
  });
}
