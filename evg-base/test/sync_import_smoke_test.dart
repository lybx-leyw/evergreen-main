// 同步中心导入端冒烟验证（t16）：构造最小 .egsync.zip（插件 + 数据源 + 主题），
// 验证 fail-closed 校验、版本感知冲突策略与注册回放。
// 运行：flutter test test/sync_import_smoke_test.dart（仅单文件，不跑全量）。
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:evergreen_base/core/data/orchestrator.dart';
import 'package:evergreen_base/core/data/type.dart';
import 'package:evergreen_base/core/module/module_registry.dart';
import 'package:evergreen_base/core/result.dart';
import 'package:evergreen_base/core/services/sync_import_service.dart';
import 'package:evergreen_base/core/theme/theme_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// 构造 .egsync.zip 字节（entries: 包内相对路径 → 内容字符串）。
List<int> _buildEgsyncZip(Map<String, String> entries) {
  final archive = Archive();
  for (final e in entries.entries) {
    archive.addFile(ArchiveFile(e.key, utf8.encode(e.value).length,
        utf8.encode(e.value)));
  }
  return ZipEncoder().encode(archive)!;
}

void _writeZip(String path, Map<String, String> entries) {
  File(path).writeAsBytesSync(_buildEgsyncZip(entries));
}

final _pluginManifest = '''
{
  "schemaVersion": "2.0",
  "type": "module",
  "id": "sync-demo",
  "name": "同步演示插件",
  "template": "html",
  "version": "1.0.0",
  "route": "/sync-demo",
  "nav": { "sidebar": { "section": "同步", "order": 99 } }
}''';

final _pluginIndexHtml = '<!doctype html><html><body>sync demo</body></html>';

final _themeJson = '''
{
  "type": "theme",
  "id": "sync-ocean",
  "name": "同步海洋",
  "colors": {
    "background": "#0B1D33",
    "surface": "#132A45",
    "border": "#1F3B5C",
    "text": "#E8F1FA",
    "textSecondary": "#9DB4CC",
    "accent": "#3FA9F5",
    "error": "#F25C5C",
    "others": "#2C4A6B"
  }
}''';

final _dataManifest = '''
{
  "type": "data-source",
  "id": "sync-ds",
  "name": "同步数据源",
  "version": "1.0.0",
  "script": "fetch.py",
  "dataTypes": [
    { "name": "sync_demo_data", "typeArg": "sync_demo_data", "category": "同步", "displayName": "同步数据" }
  ]
}''';

Map<String, String> _baseEntries() => {
      'manifest.json': jsonEncode({
        'type': 'egsync',
        'version': 1,
        'exportedAt': '2026-08-25T12:00:00.000Z',
        'appVersion': '2.0.0-rc.1',
        'platform': 'windows',
        'resources': ['plugins', 'data', 'themes'],
      }),
      'plugins/sync-demo/module/manifest.json': _pluginManifest,
      'plugins/sync-demo/module/index.html': _pluginIndexHtml,
      'data/sync-ds/data/manifest.json': _dataManifest,
      'data/sync-ds/data/fetch.py': 'print("{}")',
      'themes/sync-ocean/theme/theme.json': _themeJson,
    };

void main() {
  late Directory temp;
  late ModuleRegistry registry;
  late ThemeStore themeStore;
  late DataOrchestrator orch;
  late String pluginsRoot;
  late String sessionsRoot;
  late String memoriesRoot;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('egsync_smoke_');
    pluginsRoot = '${temp.path}/plugins';
    sessionsRoot = '${temp.path}/sessions';
    memoriesRoot = '${temp.path}/memories';
    Directory(pluginsRoot).createSync(recursive: true);
    registry = ModuleRegistry();
    registry.seal(); // 查询需要 seal；导入经 reloadModule 仍可热注册
    themeStore = ThemeStore();
    orch = DataOrchestrator();
  });

  tearDown(() {
    try {
      temp.deleteSync(recursive: true);
    } catch (_) {}
  });

  SyncImportService _service() => SyncImportService(
        registry: registry,
        themeStore: themeStore,
        orch: orch,
        pluginsRoot: pluginsRoot,
        sessionsRoot: sessionsRoot,
        memoriesRoot: memoriesRoot,
        projectRoot: temp.path,
      );

  test('导入：插件 + 数据源 + 主题落盘并注册（imported）', () async {
    final zip = '${temp.path}/a.egsync.zip';
    _writeZip(zip, _baseEntries());

    final result = await _service().importZip(zip);
    expect(result, isA<Ok<SyncImportResult>>());
    final r = result.unwrap();
    expect(r.hasConflicts, isFalse);
    expect(r.hasErrors, isFalse);

    // 插件：落盘 + 注册
    expect(
        File('$pluginsRoot/sync-demo/module/manifest.json').existsSync(), isTrue);
    expect(
        File('$pluginsRoot/sync-demo/module/index.html').existsSync(), isTrue);
    expect(registry.findById('sync-demo'), isNotNull,
        reason: '插件应注册进 ModuleRegistry');

    // 数据源：落盘 + 注册（模型 A）
    expect(File('$pluginsRoot/sync-ds/data/manifest.json').existsSync(), isTrue);
    expect(orch.isRegistered(const DataType(name: 'sync_demo_data')), isTrue,
        reason: '数据源应注册进 DataOrchestrator');

    // 主题：落盘 + 注册
    expect(
        File('$pluginsRoot/sync-ocean/theme/theme.json').existsSync(), isTrue);
    expect(themeStore.findById('sync-ocean'), isNotNull,
        reason: '主题应注册进 ThemeStore');

    final actions = r.items.map((i) => i.action).toSet();
    expect(actions, contains(SyncImportAction.imported));
    expect(r.countOf(SyncImportAction.error), 0);
  });

  test('重复导入同版本同内容 → no-op（不重复落盘不报冲突）', () async {
    final zip = '${temp.path}/b.egsync.zip';
    _writeZip(zip, _baseEntries());
    final service = _service();

    final first = await service.importZip(zip);
    expect(first.unwrap().countOf(SyncImportAction.imported), greaterThan(0));

    final second = await service.importZip(zip);
    expect(second.unwrap().hasConflicts, isFalse);
    expect(second.unwrap().countOf(SyncImportAction.noop), greaterThan(0));
    expect(second.unwrap().countOf(SyncImportAction.imported), 0,
        reason: '同版本同内容不应重复落盘');
  });

  test('同版本不同内容 → 冲突清单（不自动破坏），applyConflicts 后可覆盖', () async {
    final zip = '${temp.path}/c.egsync.zip';
    _writeZip(zip, _baseEntries());
    final service = _service();
    await service.importZip(zip);

    // 修改 index.html 后重导（同版本 1.0.0）
    final changed = _baseEntries();
    changed['plugins/sync-demo/module/index.html'] =
        '<!doctype html><html><body>changed</body></html>';
    final zip2 = '${temp.path}/c2.egsync.zip';
    _writeZip(zip2, changed);

    // 默认策略：返回冲突清单，文件不被覆盖
    final r2 = await service.importZip(zip2);
    expect(r2.unwrap().hasConflicts, isTrue);
    final pluginConflict = r2.unwrap().conflicts
        .where((c) => c.type == SyncResourceType.plugins && c.id == 'sync-demo');
    expect(pluginConflict, isNotEmpty);
    expect(pluginConflict.first.reason, 'same-version-different');
    expect(
        File('$pluginsRoot/sync-demo/module/index.html')
            .readAsStringSync()
            .contains('changed'),
        isFalse,
        reason: '冲突未解决前不得覆盖');

    // applyConflicts + overwriteSameVersion → 覆盖
    final r3 = await service.importZip(zip2,
        policy: const SyncImportPolicy(
            applyConflicts: true, overwriteSameVersion: true));
    expect(r3.unwrap().hasConflicts, isFalse);
    expect(
        File('$pluginsRoot/sync-demo/module/index.html')
            .readAsStringSync()
            .contains('changed'),
        isTrue);
  });

  test('fail-closed：包级 type 非法 → 整体拒绝（Err）', () async {
    final zip = '${temp.path}/d.egsync.zip';
    final entries = _baseEntries();
    entries['manifest.json'] = jsonEncode({
      'type': 'evil',
      'version': 1,
      'exportedAt': '2026-08-25T12:00:00.000Z',
      'resources': ['plugins'],
    });
    _writeZip(zip, entries);
    final result = await _service().importZip(zip);
    expect(result, isA<Err<SyncImportResult>>(), reason: 'type 非法应整体拒绝');
  });

  test('fail-closed：zip-slip（../ 越界条目）→ 整体拒绝', () async {
    final zip = '${temp.path}/e.egsync.zip';
    final entries = _baseEntries();
    entries['plugins/../evil.txt'] = 'evil';
    _writeZip(zip, entries);
    final result = await _service().importZip(zip);
    expect(result, isA<Err<SyncImportResult>>(), reason: '越界路径应整体拒绝');
    expect(File('${temp.path}/evil.txt').existsSync(), isFalse);
  });

  test('fail-closed：.plugin 信封 files 哈希不一致 → 该项 error 不落盘', () async {
    final zip = '${temp.path}/f.egsync.zip';
    final manifestStr = jsonEncode({
      'type': 'plugin',
      'id': 'env-plugin',
      'name': '信封插件',
      'version': '1.0.0',
      'files': {
        'module/index.html': 'deadbeef', // 错误哈希
      },
    });
    final entries = {
      'manifest.json': jsonEncode({
        'type': 'egsync',
        'version': 1,
        'exportedAt': '2026-08-25T12:00:00.000Z',
        'resources': ['plugins'],
      }),
      'plugins/env-plugin/manifest.json': manifestStr,
      'plugins/env-plugin/module/index.html': '<html>env</html>',
    };
    _writeZip(zip, entries);
    final result = await _service().importZip(zip);
    final r = result.unwrap();
    expect(r.countOf(SyncImportAction.error), 1);
    expect(File('$pluginsRoot/env-plugin/module/index.html').existsSync(),
        isFalse, reason: '哈希校验失败不得落盘');
  });

  test('fail-closed：资源声明的目录缺失 → 该项 error', () async {
    final zip = '${temp.path}/g.egsync.zip';
    final entries = {
      'manifest.json': jsonEncode({
        'type': 'egsync',
        'version': 1,
        'exportedAt': '2026-08-25T12:00:00.000Z',
        'resources': ['themes', 'plugins'],
      }),
      'plugins/sync-demo/module/manifest.json': _pluginManifest,
      'plugins/sync-demo/module/index.html': _pluginIndexHtml,
    };
    _writeZip(zip, entries);
    final r = (await _service().importZip(zip)).unwrap();
    // themes 声明但缺失 → error；plugins 正常导入
    expect(
        r.items.any((i) =>
            i.type == SyncResourceType.themes &&
            i.action == SyncImportAction.error),
        isTrue);
    expect(registry.findById('sync-demo'), isNotNull);
  });

  test('模型 B（HTTP .exe）数据源：回放失败仅降级，不阻断包导入', () async {
    final zip = '${temp.path}/h.egsync.zip';
    final entries = {
      'manifest.json': jsonEncode({
        'type': 'egsync',
        'version': 1,
        'exportedAt': '2026-08-25T12:00:00.000Z',
        'resources': ['data'],
      }),
      // 模型 B：process 声明了 server.exe，但包内无该二进制 → DataSourceLoader 回放失败
      'data/sync-http/data/manifest.json': jsonEncode({
        'type': 'data-source',
        'id': 'sync-http',
        'name': 'HTTP 数据源',
        'process': 'server.exe',
        'dataTypes': [
          {
            'name': 'http_data',
            'category': '同步',
            'displayName': 'HTTP 数据',
            'endpoint': '/api/data',
          }
        ],
      }),
    };
    _writeZip(zip, entries);
    final r = (await _service().importZip(zip)).unwrap();
    // 落盘成功（imported），回放失败仅体现在 message 中；包不 fail、不产生 error item
    final item = r.items.firstWhere((i) => i.id == 'sync-http');
    expect(item.action, SyncImportAction.imported);
    expect(item.message, contains('回放失败'));
    expect(r.hasErrors, isFalse);
    expect(File('$pluginsRoot/sync-http/data/manifest.json').existsSync(), isTrue);
  });
}
