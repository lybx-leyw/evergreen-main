/// SkinLoader 全量测试——scanSkins / loadSkins / scanSkinFile / 失败跳过。
library;

import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;

import '../skin_descriptor.dart';
import '../skin_loader.dart';
import '../skin_store.dart';

// ═══════ helpers ═══════

/// 临时目录 + 逐文件清理。
Directory _tmpDir(String name) {
  final dir = Directory(
      p.join(Directory.systemTemp.path, 'skin_loader_test_$name'));
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  dir.createSync(recursive: true);
  return dir;
}

void _writeSkin(Directory pluginDir, String json) {
  final skinDir = Directory(p.join(pluginDir.path, 'skin'));
  skinDir.createSync(recursive: true);
  File(p.join(skinDir.path, 'manifest.json')).writeAsStringSync(json);
}

Map<String, dynamic> _manifest(String id, [String name = '']) => {
      'type': 'skin',
      'id': id,
      'name': name.isEmpty ? id : name,
      'background': {'type': 'solid', 'color': '#FFFFFF'},
    };

void main() {
  group('scanSkins', () {
    test('不存在的目录返回空列表', () {
      expect(scanSkins('/nonexistent/path/12345'), isEmpty);
    });

    test('空目录返回空列表', () {
      final dir = _tmpDir('empty');
      addTearDown(() => dir.deleteSync(recursive: true));
      expect(scanSkins(dir.path), isEmpty);
    });

    test('扫描到合法皮肤包并填充 sourceDir', () {
      final root = _tmpDir('scan_ok');
      addTearDown(() => root.deleteSync(recursive: true));
      _writeSkin(Directory(p.join(root.path, 'green_skin')),
          jsonEncode(_manifest('green_skin', '绿意皮肤')));

      final skins = scanSkins(root.path);
      expect(skins.length, 1);
      expect(skins.first.id, 'green_skin');
      expect(skins.first.sourceDir,
          p.join(root.path, 'green_skin')); // 插件目录
      expect(skins.first.backgroundColor, '#FFFFFF');
    });

    test('type 非 skin 的 manifest 跳过', () {
      final root = _tmpDir('skip_type');
      addTearDown(() => root.deleteSync(recursive: true));
      _writeSkin(Directory(p.join(root.path, 'not_skin')),
          jsonEncode({'type': 'theme', 'id': 'x', 'name': 'X'}));

      expect(scanSkins(root.path), isEmpty);
    });

    test('坏 manifest（type 非法）失败跳过、不阻塞其它包', () {
      final root = _tmpDir('bad_manifest');
      addTearDown(() => root.deleteSync(recursive: true));
      _writeSkin(Directory(p.join(root.path, 'bad')),
          jsonEncode({'type': 'config', 'id': 'bad'}));
      _writeSkin(Directory(p.join(root.path, 'good')),
          jsonEncode(_manifest('good')));

      final skins = scanSkins(root.path);
      expect(skins.length, 1);
      expect(skins.first.id, 'good'); // 坏包被跳过，好包正常加载
    });

    test('非 JSON 内容失败跳过', () {
      final root = _tmpDir('bad_json');
      addTearDown(() => root.deleteSync(recursive: true));
      _writeSkin(Directory(p.join(root.path, 'bad')), 'not json at all');

      expect(scanSkins(root.path), isEmpty);
    });

    test('无 skin 子目录的插件目录被跳过', () {
      final root = _tmpDir('no_skin_dir');
      addTearDown(() => root.deleteSync(recursive: true));
      Directory(p.join(root.path, 'no_skin')).createSync(recursive: true);

      expect(scanSkins(root.path), isEmpty);
    });
  });

  group('loadSkins', () {
    test('扫描并注册到 store', () {
      final root = _tmpDir('load');
      addTearDown(() => root.deleteSync(recursive: true));
      _writeSkin(Directory(p.join(root.path, 'a')), jsonEncode(_manifest('a')));
      _writeSkin(Directory(p.join(root.path, 'b')), jsonEncode(_manifest('b')));

      final store = SkinStore();
      loadSkins(root.path, store);
      expect(store.all.length, 2);
      expect(store.findById('a'), isNotNull);
      expect(store.findById('b'), isNotNull);
    });

    test('同 id 后者覆盖（插件覆盖内置默认包）', () {
      final root = _tmpDir('load_override');
      addTearDown(() => root.deleteSync(recursive: true));
      _writeSkin(Directory(p.join(root.path, 'skin-default')),
          jsonEncode(_manifest('skin-default', '插件版默认')));

      final store = SkinStore();
      store.register(
          const SkinDescriptor(id: 'skin-default', name: '内置默认皮肤'));
      loadSkins(root.path, store);
      expect(store.findById('skin-default')?.name, '插件版默认');
    });
  });

  group('scanSkinFile', () {
    test('文件不存在抛 FileSystemException', () {
      expect(
        () => scanSkinFile('/nonexistent/manifest.json'),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('加载单个合法 manifest', () {
      final root = _tmpDir('single');
      addTearDown(() => root.deleteSync(recursive: true));
      _writeSkin(Directory(p.join(root.path, 'a')), jsonEncode(_manifest('a')));
      final file = p.join(root.path, 'a', 'skin', 'manifest.json');
      final s = scanSkinFile(file);
      expect(s.id, 'a');
      expect(s.sourceDir, isNull); // scanSkinFile 不填充 sourceDir
    });
  });
}
