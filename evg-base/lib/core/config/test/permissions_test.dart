/// Config 模块——权限与源管理测试。
library;

import 'package:test/test.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

// ═══════════════════════════════════════════════════════════════════════════
// tests
// ═══════════════════════════════════════════════════════════════════════════

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    prefs = await SharedPreferences.getInstance();
  });

  // ───────────────────────────────────────────────────────────────────────
  // PermissionDecl 构造
  // ───────────────────────────────────────────────────────────────────────

  group('PermissionDecl 构造', () {
    test('所有字段可访问', () {
      final p = PermissionDecl(key: 'NET', label: '网络', description: '访问互联网');
      expect(p.key, 'NET');
      expect(p.label, '网络');
      expect(p.description, '访问互联网');
      expect(p.defaultGranted, true);
    });

    test('defaultGranted 可设为 false', () {
      final p = PermissionDecl(key: 'CAM', label: '摄像头', description: '...', defaultGranted: false);
      expect(p.defaultGranted, false);
    });

    test('getPermissions 回退 defaultGranted=false', () {
      registerPermissions('p_def', [
        const PermissionDecl(key: 'OPT_IN', label: '可选', description: '...', defaultGranted: false),
      ]);
      final perms = getPermissions(prefs, 'p_def');
      expect(perms['OPT_IN'], false);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // registerPermissions + getPermissions
  // ───────────────────────────────────────────────────────────────────────

  group('registerPermissions + getPermissions', () {
    test('注册后 getPermissions 返回全部权限', () {
      registerPermissions('p1', [
        const PermissionDecl(key: 'NET', label: '网络', description: '...'),
        const PermissionDecl(key: 'FS', label: '文件', description: '...'),
      ]);
      final perms = getPermissions(prefs, 'p1');
      expect(perms, hasLength(2));
      expect(perms['NET'], true);
      expect(perms['FS'], true);
    });

    test('未注册的插件返回空 map', () {
      expect(getPermissions(prefs, 'nonexistent_plugin_999'), isEmpty);
    });

    test('重复注册覆盖之前声明', () {
      registerPermissions('p2', [
        const PermissionDecl(key: 'A', label: 'A', description: '...'),
      ]);
      registerPermissions('p2', [
        const PermissionDecl(key: 'B', label: 'B', description: '...'),
        const PermissionDecl(key: 'C', label: 'C', description: '...'),
      ]);
      final perms = getPermissions(prefs, 'p2');
      expect(perms, hasLength(2));
      expect(perms.containsKey('B'), true);
      expect(perms.containsKey('A'), false);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // setPermission
  // ───────────────────────────────────────────────────────────────────────

  group('setPermission', () {
    test('设置权限即时生效', () async {
      registerPermissions('p3', [
        const PermissionDecl(key: 'N', label: 'N', description: '...'),
      ]);
      await setPermission(prefs, 'p3', 'N', false);
      final perms = getPermissions(prefs, 'p3');
      expect(perms['N'], false);
    });

    test('先 false 再 true', () async {
      registerPermissions('p4', [
        const PermissionDecl(key: 'X', label: 'X', description: '...'),
      ]);
      await setPermission(prefs, 'p4', 'X', false);
      await setPermission(prefs, 'p4', 'X', true);
      expect(getPermissions(prefs, 'p4')['X'], true);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // checkPermission
  // ───────────────────────────────────────────────────────────────────────

  group('checkPermission', () {
    test('拒绝时抛出 PermissionDeniedException', () async {
      registerPermissions('p5', [
        const PermissionDecl(key: 'DANGER', label: '危险', description: '...'),
      ]);
      await setPermission(prefs, 'p5', 'DANGER', false);
      expect(
        () => checkPermission(prefs, 'p5', 'DANGER'),
        throwsA(isA<PermissionDeniedException>()),
      );
    });

    test('已授权时不抛异常', () async {
      registerPermissions('p6', [
        const PermissionDecl(key: 'SAFE', label: '安全', description: '...'),
      ]);
      await setPermission(prefs, 'p6', 'SAFE', true);
      expect(
        () => checkPermission(prefs, 'p6', 'SAFE'),
        returnsNormally,
      );
    });

    test('未设置时默认授权不抛异常', () {
      registerPermissions('p7', [
        const PermissionDecl(key: 'DEF', label: '默认', description: '...'),
      ]);
      expect(
        () => checkPermission(prefs, 'p7', 'DEF'),
        returnsNormally,
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // describePermission
  // ───────────────────────────────────────────────────────────────────────

  group('describePermission', () {
    test('生成通俗语言描述', () {
      final desc = describePermission(
        const PermissionDecl(key: 'NET', label: '网络访问', description: '允许插件访问互联网'),
      );
      expect(desc, contains('网络访问'));
      expect(desc, contains('允许插件访问互联网'));
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // getPermissionDecls
  // ───────────────────────────────────────────────────────────────────────

  group('getPermissionDecls', () {
    test('返回注册的声明列表', () {
      registerPermissions('p8', [
        const PermissionDecl(key: 'A', label: 'A', description: 'a'),
      ]);
      final decls = getPermissionDecls('p8');
      expect(decls, isNotNull);
      expect(decls!.length, 1);
      expect(decls.first.key, 'A');
    });

    test('未注册返回 null', () {
      expect(getPermissionDecls('no_such_plugin'), isNull);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // PluginSource + 源管理
  // ───────────────────────────────────────────────────────────────────────

  group('PluginSource', () {
    test('构造', () {
      final s = PluginSource(url: 'https://x.com', name: 'X');
      expect(s.url, 'https://x.com');
      expect(s.name, 'X');
      expect(s.isDefault, false);
    });
  });

  group('getSources', () {
    test('默认源始终在列表首位', () {
      final sources = getSources(prefs);
      expect(sources, isNotEmpty);
      expect(sources.first.isDefault, true);
      expect(sources.first.url, defaultSourceUrl);
    });
  });

  group('addSource', () {
    test('添加自定义源成功', () async {
      await addSource(prefs, 'https://test.example.com/plugins.json', '测试源');
      final sources = getSources(prefs);
      expect(sources.any((s) => s.url == 'https://test.example.com/plugins.json'), true);
    });

    test('重复 URL 抛出 SourceDuplicateException', () async {
      await addSource(prefs, 'https://dup.example.com/plugins.json', '源A');
      expect(
        () => addSource(prefs, 'https://dup.example.com/plugins.json', '源B'),
        throwsA(isA<SourceDuplicateException>()),
      );
    });
  });

  group('removeSource', () {
    test('删除自定义源成功', () async {
      await addSource(prefs, 'https://del.example.com/plugins.json', '待删除');
      await removeSource(prefs, 'https://del.example.com/plugins.json');
      final sources = getSources(prefs);
      expect(sources.any((s) => s.url == 'https://del.example.com/plugins.json'), false);
    });

    test('默认源不可删除', () async {
      expect(
        () => removeSource(prefs, defaultSourceUrl),
        throwsA(isA<ConfigValidationException>()),
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // 异常 toString
  // ───────────────────────────────────────────────────────────────────────

  group('异常 toString', () {
    test('PermissionDeniedException', () {
      final e = PermissionDeniedException('plugin', 'perm');
      expect(e.toString(), contains('plugin'));
      expect(e.toString(), contains('perm'));
    });

    test('SourceDuplicateException', () {
      final e = SourceDuplicateException('https://dup.url');
      expect(e.toString(), contains('https://dup.url'));
    });
  });
}
