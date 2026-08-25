/// 同步中心导出端（pack_sync）冒烟测试 —— .egsync.zip 结构与勾选过滤。
///
/// 对照契约：docs/superpowers/specs/egsync-sync-center-spec-v1.md
/// - §二 包结构（manifest.json + config/ + sessions/ + memories/ + plugins/ + data/ + themes/）
/// - §三 manifest.json 字段
/// - §五 同步选项（资源类型 × 插件分组）
/// - §六 全相对路径
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../sync_export_service.dart';

void _write(String path, String content) {
  final f = File(path);
  f.parent.createSync(recursive: true);
  f.writeAsStringSync(content);
}

void main() {
  late Directory root;
  late String greenixRoot;
  late String pluginsRoot;
  late SharedPreferences prefs;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('egsync_export_test_');
    greenixRoot = p.join(root.path, '.greenix');
    pluginsRoot = p.join(root.path, 'plugins');
    Directory(p.join(greenixRoot, 'sessions')).createSync(recursive: true);
    Directory(p.join(greenixRoot, 'memories')).createSync(recursive: true);
    Directory(pluginsRoot).createSync(recursive: true);
    prefs = await SharedPreferences.getInstance();

    // ── 会话 / 记忆 ──
    _write(p.join(greenixRoot, 'sessions', 's1.json'),
        jsonEncode({'id': 's1', 'messages': []}));
    _write(p.join(greenixRoot, 'memories', 'm1.md'), '# 用户记忆');

    // ── 插件（HTML 形态）＋ 应排除的安装元数据/构建产物 ──
    _write(p.join(pluginsRoot, 'my-plugin', 'module', 'manifest.json'),
        jsonEncode({'id': 'my-plugin', 'template': 'html'}));
    _write(p.join(pluginsRoot, 'my-plugin', 'module', 'index.html'), '<html>hi</html>');
    _write(p.join(pluginsRoot, 'my-plugin', '.manifest'), '{"id":"my-plugin"}');
    _write(p.join(pluginsRoot, 'my-plugin', '.signature'), 'sig');
    _write(p.join(pluginsRoot, 'my-plugin', '__pycache__', 'x.pyc'), 'pyc');
    _write(p.join(pluginsRoot, 'my-plugin', 'build', 'y.bin'), 'bin');
    _write(p.join(pluginsRoot, 'my-plugin', 'drafts', 'wip', 'note.txt'), 'wip');

    // ── 主题 ──
    _write(p.join(pluginsRoot, 'my-plugin', 'theme', 'theme.json'),
        jsonEncode({
          'type': 'theme',
          'id': 'my-theme',
          'name': 'T',
          'colors': {
            'background': '#000000', 'surface': '#111111', 'border': '#222222',
            'text': '#ffffff', 'textSecondary': '#cccccc', 'accent': '#00aaff',
            'error': '#ff0000', 'others': '#333333',
          },
        }));

    // ── 数据源 ──
    _write(p.join(pluginsRoot, 'data-src', 'data', 'manifest.json'),
        jsonEncode({'id': 'data-src', 'type': 'data'}));
    _write(p.join(pluginsRoot, 'data-src', 'data', 'scraper.py'), 'print(1)');
    _write(p.join(pluginsRoot, 'data-src', 'config', 'config.json'),
        jsonEncode({'id': 'data-src', 'settings': []}));

    // ── 无能力标记的草稿目录（应整体跳过）──
    _write(p.join(pluginsRoot, 'draft-only', 'scratch', 'note.txt'), 'draft');

    // ── 配置插件（config/config.json 声明设置，供 config 资源过滤断言）──
    _write(p.join(pluginsRoot, 'cfg-plugin', 'config', 'config.json'),
        jsonEncode({
          'id': 'cfg-plugin',
          'name': 'C',
          'settings': [
            {'key': 'CFG_A', 'label': 'A', 'default': 'a'},
          ],
        }));
    await initSettings(prefs, pluginDirs: [pluginsRoot]);
  });

  tearDown(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  Map<String, dynamic> _readManifest(String zipPath) {
    final bytes = File(zipPath).readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);
    final entry = archive.files.firstWhere((f) => f.name == 'manifest.json');
    return jsonDecode(utf8.decode(entry.content as List<int>)) as Map<String, dynamic>;
  }

  Set<String> _readNames(String zipPath) {
    final bytes = File(zipPath).readAsBytesSync();
    return ZipDecoder().decodeBytes(bytes).files.map((f) => f.name).toSet();
  }

  test('全量导出：zip 结构符合 .egsync 规格 §二，排除清单生效，全相对路径', () async {
    final out = p.join(root.path, 'out', 'sync.egsync.zip');
    final svc = SyncExportService(greenixRoot: greenixRoot, pluginsRoot: pluginsRoot);
    final res = await svc.export(
      prefs: prefs,
      outputPath: out,
      selection: SyncSelection(resources: SyncResourceType.values.toSet()),
    );
    expect(res.success, isTrue, reason: res.error);
    expect(res.fileCount, greaterThan(0));

    final names = _readNames(out);
    // 包结构（§二）
    expect(names, contains('manifest.json'));
    expect(names, contains('config/config.evgconfig'));
    expect(names, contains('sessions/s1.json'));
    expect(names, contains('memories/m1.md'));
    expect(names, contains('plugins/my-plugin/module/manifest.json'));
    expect(names, contains('plugins/my-plugin/module/index.html'));
    expect(names, contains('themes/my-plugin/theme/theme.json'));
    expect(names, contains('data/data-src/data/manifest.json'));
    expect(names, contains('data/data-src/data/scraper.py'));
    expect(names, contains('data/data-src/config/config.json'));
    expect(names, contains('plugins/cfg-plugin/config/config.json'));

    // 排除清单（t7 探索）：.manifest/.signature/__pycache__/build/drafts/无标记草稿
    expect(names.any((n) => n.contains('.manifest')), isFalse);
    expect(names.any((n) => n.contains('.signature')), isFalse);
    expect(names.any((n) => n.contains('__pycache__')), isFalse);
    expect(names.any((n) => n.contains('/build/')), isFalse);
    expect(names.any((n) => n.contains('/drafts/')), isFalse);
    expect(names.any((n) => n.contains('draft-only')), isFalse);

    // 全相对路径（§六）：无绝对前缀、无反斜杠
    for (final n in names) {
      expect(n.startsWith('/') || RegExp(r'^[A-Za-z]:').hasMatch(n), isFalse,
          reason: '绝对路径泄漏: $n');
      expect(n.contains('\\'), isFalse, reason: '反斜杠路径: $n');
    }

    // manifest 内容（§三）
    final manifest = _readManifest(out);
    expect(manifest['type'], 'egsync');
    expect(manifest['version'], kEgsyncPackageVersion);
    expect(manifest['platform'], isNotNull);
    final resources = (manifest['resources'] as List).cast<String>();
    expect(resources.toSet(),
        containsAll(['config', 'sessions', 'memories', 'plugins', 'data', 'themes']));
    expect(manifest['options']['selections']['resources'], isA<List>());

    // config.evgconfig v2 内容
    final bytes = File(out).readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);
    final cfgEntry = archive.files.firstWhere((f) => f.name == 'config/config.evgconfig');
    final cfg = jsonDecode(utf8.decode(cfgEntry.content as List<int>)) as Map<String, dynamic>;
    expect(cfg['format'], 'evgconfig');
    expect(cfg['version'], kEvgConfigVersion);
    expect((cfg['settings'] as Map)['CFG_A'], 'a');
  });

  test('勾选过滤：仅 config + 指定插件分组（资源 × 分组双维）', () async {
    final out = p.join(root.path, 'out2', 'sync.egsync.zip');
    final svc = SyncExportService(greenixRoot: greenixRoot, pluginsRoot: pluginsRoot);
    final res = await svc.export(
      prefs: prefs,
      outputPath: out,
      selection: SyncSelection(
        resources: {SyncResourceType.config, SyncResourceType.plugins},
        pluginGroups: {'cfg-plugin'},
      ),
    );
    expect(res.success, isTrue, reason: res.error);

    final names = _readNames(out);
    expect(names, contains('manifest.json'));
    expect(names, contains('config/config.evgconfig'));
    expect(names, contains('plugins/cfg-plugin/config/config.json'));
    // 未勾选资源 / 未勾选分组不出现
    expect(names.any((n) => n.startsWith('sessions/')), isFalse);
    expect(names.any((n) => n.startsWith('memories/')), isFalse);
    expect(names.any((n) => n.startsWith('plugins/my-plugin/')), isFalse);
    expect(names.any((n) => n.startsWith('data/') || n.startsWith('themes/')), isFalse);

    final manifest = _readManifest(out);
    expect((manifest['resources'] as List).cast<String>(), ['config', 'plugins']);
    expect(manifest['options']['selections']['pluginGroups'], ['cfg-plugin']);

    // config 子集：仅 cfg-plugin 来源设置被保留
    final bytes = File(out).readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);
    final cfgEntry = archive.files.firstWhere((f) => f.name == 'config/config.evgconfig');
    final cfg = jsonDecode(utf8.decode(cfgEntry.content as List<int>)) as Map<String, dynamic>;
    expect((cfg['settings'] as Map)['CFG_A'], 'a');
  });

  test('空勾选：仅 manifest.json', () async {
    final out = p.join(root.path, 'out3', 'sync.egsync.zip');
    final svc = SyncExportService(greenixRoot: greenixRoot, pluginsRoot: pluginsRoot);
    final res = await svc.export(
      prefs: prefs,
      outputPath: out,
      selection: const SyncSelection(resources: {}),
    );
    expect(res.success, isTrue, reason: res.error);
    expect(res.fileCount, 0);
    expect(_readNames(out), {'manifest.json'});
    expect((_readManifest(out)['resources'] as List), isEmpty);
  });

  test('isSecure 勾选：includeSecure=false 时明文不入包', () async {
    _write(p.join(pluginsRoot, 'sec-plugin', 'config', 'config.json'),
        jsonEncode({
          'id': 'sec-plugin',
          'name': 'S',
          'settings': [
            {'key': 'SEC_KEY', 'label': 'K', 'isSecure': true, 'default': 'topsecret'},
          ],
        }));
    await initSettings(prefs, pluginDirs: [pluginsRoot]);
    // 模拟用户填入密钥
    await prefs.setString('SEC_KEY', 'user-secret');

    final out = p.join(root.path, 'out4', 'sync.egsync.zip');
    final svc = SyncExportService(greenixRoot: greenixRoot, pluginsRoot: pluginsRoot);
    await svc.export(
      prefs: prefs,
      outputPath: out,
      selection: const SyncSelection(resources: {SyncResourceType.config}),
    );
    final bytes = File(out).readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);
    final cfgEntry = archive.files.firstWhere((f) => f.name == 'config/config.evgconfig');
    final cfg = jsonDecode(utf8.decode(cfgEntry.content as List<int>)) as Map<String, dynamic>;
    expect((cfg['settings'] as Map).containsKey('SEC_KEY'), isFalse, reason: 'isSecure 明文不应默认导出');

    // includeSecure=true 时导出
    await svc.export(
      prefs: prefs,
      outputPath: out,
      selection: const SyncSelection(resources: {SyncResourceType.config}, includeSecure: true),
    );
    final bytes2 = File(out).readAsBytesSync();
    final cfg2 = jsonDecode(utf8.decode(ZipDecoder().decodeBytes(bytes2).files
        .firstWhere((f) => f.name == 'config/config.evgconfig').content as List<int>)) as Map<String, dynamic>;
    expect((cfg2['settings'] as Map)['SEC_KEY'], 'user-secret');
  });
}
