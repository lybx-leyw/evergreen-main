/// 同步中心导出端 —— 按用户勾选把资源打包为 `.egsync.zip`（pack_sync）。
///
/// 契约：`docs/superpowers/specs/egsync-sync-center-spec-v1.md`
/// - §二 .egsync.zip 包结构（manifest.json + config/config.evgconfig + sessions/ +
///   memories/ + plugins/<id>/ + data/<id>/ + themes/<id>/）
/// - §三 manifest.json 契约（type/version/exportedAt/platform/resources/options）
/// - §五 同步选项模型（资源类型 × 插件分组双维勾选）
/// - §六 跨平台路径规则（包内全部相对路径，不序列化绝对路径）
///
/// 纯 Dart（不引用 Flutter Widget）；所有根路径由调用方注入——运行期来自
/// `core/utils/greenix_path.dart`（greenixPath 系 / resolvePluginsRoot()），
/// 保持本模块与 Flutter/平台层解耦（分层红线）。
///
/// 说明：
/// - 本服务只做「按现状打包」；记忆拼接 / 会话合并（包含则删小/分化都保留）在导入端/
///   合并任务（t-C4）处理。若未来需要导出合并后数据，调用方先把合并结果落盘到
///   [sessionsDir]/[memoriesDir] 再调用本服务（预留了注入路径）。
/// - 未引入 UI：导出入口 API 即本服务；勾选 UI（t-C2）由调用方（renderer）接入。
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'config_http_server.dart';
import 'settings.dart';

/// .egsync 包格式版本（manifest.version，.egsync 规格 §三）。
const int kEgsyncPackageVersion = 1;

/// 同步资源类型（与 .egsync 规格 §5 一致；`manifest.resources` 值取 [name]）。
enum SyncResourceType { config, sessions, memories, plugins, data, themes }

/// 用户勾选（资源类型 × 插件分组双维）。
///
/// [pluginGroups] 为空 = 全部插件；非空 = 仅勾选分组（builtins / 插件 id）。
/// [merge] 写入 `manifest.options.merge`（导入端冲突策略参考：merge 合并 / overwrite 覆盖）。
class SyncSelection {
  final Set<SyncResourceType> resources;
  final Set<String> pluginGroups;
  final bool includeSecure;
  final String merge;

  const SyncSelection({
    required this.resources,
    this.pluginGroups = const {},
    this.includeSecure = false,
    this.merge = 'merge',
  });

  bool includes(SyncResourceType t) => resources.contains(t);

  bool get hasPluginFilter => pluginGroups.isNotEmpty;

  /// 插件 id 是否被勾选（无插件过滤时恒 true）。
  bool groupSelected(String id) => !hasPluginFilter || pluginGroups.contains(id);
}

/// 导出结果。
class SyncExportResult {
  final bool success;
  final String? outputPath;
  final int fileCount;
  final Map<String, Object?> manifest;
  final String? error;

  const SyncExportResult.success({
    required this.outputPath,
    required this.fileCount,
    required this.manifest,
  })  : success = true,
        error = null;

  const SyncExportResult.failure(this.error)
      : success = false,
        outputPath = null,
        fileCount = 0,
        manifest = const {};

  @override
  String toString() => success
      ? 'SyncExportResult(success, $fileCount 文件 → $outputPath)'
      : 'SyncExportResult(failure: $error)';
}

/// `.egsync.zip` 导出服务。
///
/// 用法（运行期）：
/// ```dart
/// final svc = SyncExportService(
///   greenixRoot: greenixRoot,          // .greenix 根（greenix_path.dart）
///   pluginsRoot: resolvePluginsRoot(),
///   appPrefsCandidates: {'active_theme_id': '应用主题', ...},
/// );
/// final res = await svc.export(
///   prefs: prefs,
///   outputPath: '.../evergreen-sync.egsync.zip',
///   selection: SyncSelection(resources: {SyncResourceType.config, SyncResourceType.sessions, ...}),
///   configServer: configServer,        // 提供 dynamicSettingKeys 枚举
/// );
/// ```
class SyncExportService {
  /// `.greenix` 根目录（运行期来自 `greenix_path.dart`；注入以保持纯 Dart）。
  final String greenixRoot;

  /// 插件根目录（运行期来自 `resolvePluginsRoot()`）。
  final String pluginsRoot;

  /// 会话目录（默认 `$greenixRoot/sessions`）。
  final String sessionsDir;

  /// 全局记忆目录（默认 `$greenixRoot/memories`）。
  final String memoriesDir;

  /// 未声明应用偏好候选（key → 说明），随 config 导出为 `appPrefs` 段。
  final Map<String, String> appPrefsCandidates;

  /// 导出端应用版本（可选，写入 manifest.appVersion 供导入端兼容提示）。
  final String? appVersion;

  SyncExportService({
    required this.greenixRoot,
    required this.pluginsRoot,
    String? sessionsDir,
    String? memoriesDir,
    this.appPrefsCandidates = const {},
    this.appVersion,
  })  : sessionsDir = sessionsDir ?? p.join(greenixRoot, 'sessions'),
        memoriesDir = memoriesDir ?? p.join(greenixRoot, 'memories');

  // ═══════════════════════════════════════════════════════════════════════
  // 公开入口
  // ═══════════════════════════════════════════════════════════════════════

  /// 按 [selection] 勾选导出 `.egsync.zip` 到 [outputPath]。
  ///
  /// [configServer] 可选：提供动态注册项枚举（`dynamicSettingKeys`），
  /// 缺省时动态段为空（仍导出声明式设置/权限/源/appPrefs）。
  /// [aiMemory] 可选：随 config 导出（由 Agent 模块提供）。
  Future<SyncExportResult> export({
    required SharedPreferences prefs,
    required String outputPath,
    required SyncSelection selection,
    ConfigHttpServer? configServer,
    Map<String, dynamic>? aiMemory,
  }) async {
    try {
      final entries = <String, List<int>>{};
      final resources = <String>[];

      // ── config（config.evgconfig v2，复用 t11 实现）──
      if (selection.includes(SyncResourceType.config)) {
        final cfg = await _buildConfig(prefs, selection, configServer, aiMemory);
        entries['config/config.evgconfig'] = utf8.encode(jsonEncode(cfg));
        resources.add('config');
      }

      // ── sessions（.greenix/sessions/*.json 原始拷贝）──
      if (selection.includes(SyncResourceType.sessions)) {
        if (_collectTree(sessionsDir, 'sessions', entries) > 0) {
          resources.add('sessions');
        }
      }

      // ── memories（.greenix/memories/** 原始拷贝）──
      if (selection.includes(SyncResourceType.memories)) {
        if (_collectTree(memoriesDir, 'memories', entries) > 0) {
          resources.add('memories');
        }
      }

      // ── plugins / data / themes（都来自 pluginsRoot，按插件分组过滤）──
      final wantPluginLike = selection.includes(SyncResourceType.plugins) ||
          selection.includes(SyncResourceType.data) ||
          selection.includes(SyncResourceType.themes);
      if (wantPluginLike) {
        for (final id in _listPluginIds()) {
          if (!selection.groupSelected(id)) continue;
          if (selection.includes(SyncResourceType.plugins) &&
              _collectPlugin(id, entries)) {
            resources.add('plugins');
          }
          if (selection.includes(SyncResourceType.data) &&
              _collectDataSource(id, entries)) {
            resources.add('data');
          }
          if (selection.includes(SyncResourceType.themes) &&
              _collectTheme(id, entries)) {
            resources.add('themes');
          }
        }
      }

      // ── manifest.json ──
      final manifest = _buildManifest(selection, resources);
      entries['manifest.json'] = utf8.encode(jsonEncode(manifest));

      // ── zip 打包 ──
      final archive = Archive();
      final sortedNames = entries.keys.toList()..sort();
      for (final name in sortedNames) {
        final bytes = entries[name]!;
        archive.addFile(ArchiveFile(name, bytes.length, bytes));
      }
      final zipBytes = ZipEncoder().encode(archive);
      if (zipBytes == null) {
        return const SyncExportResult.failure('zip 编码失败');
      }
      final out = File(outputPath);
      out.parent.createSync(recursive: true);
      await out.writeAsBytes(zipBytes, flush: true);

      return SyncExportResult.success(
        outputPath: outputPath,
        fileCount: entries.length - 1, // 不含 manifest.json
        manifest: manifest,
      );
    } catch (e, st) {
      stderr.writeln('[SyncExport] ❌ 导出失败: $e\n$st');
      return SyncExportResult.failure('$e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // config 资源
  // ═══════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> _buildConfig(
    SharedPreferences prefs,
    SyncSelection selection,
    ConfigHttpServer? configServer,
    Map<String, dynamic>? aiMemory,
  ) async {
    final cfg = await exportConfig(
      prefs,
      aiMemory: aiMemory,
      dynamicKeys: configServer?.dynamicSettingKeys ?? const <String>[],
      includePermissions: true,
      appPrefs: appPrefsCandidates,
      includeSecure: selection.includeSecure,
    );

    // 插件分组过滤：settings 按来源插件 id、permissions 按 pluginId 裁剪
    if (selection.hasPluginFilter) {
      final sources = getSettingSources();
      final settings = cfg['settings'] as Map<String, dynamic>? ?? const {};
      cfg['settings'] = <String, dynamic>{
        for (final e in settings.entries)
          if (sources[e.key] != null && selection.pluginGroups.contains(sources[e.key]))
            e.key: e.value,
      };
      final perms = cfg['permissions'] as Map<String, dynamic>?;
      if (perms != null) {
        cfg['permissions'] = <String, dynamic>{
          for (final e in perms.entries)
            if (selection.pluginGroups.contains(e.key)) e.key: e.value,
        };
      }
      // dynamicSettings（运行期注册，无法按插件归属）与 appPrefs（应用级）保持原样
    }
    return cfg;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 文件资源收集
  // ═══════════════════════════════════════════════════════════════════════

  /// 递归拷贝目录树到 zip 条目（前缀如 `sessions`、`memories`），返回文件数。
  /// 隐藏项（`.` 开头，如 .cookies）不入包。
  int _collectTree(String dirPath, String prefix, Map<String, List<int>> out) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return 0;
    var n = 0;
    for (final entity in dir.listSync()) {
      final name = p.basename(entity.path);
      if (name.startsWith('.')) continue;
      final zipPath = '$prefix/${name.replaceAll('\\', '/')}';
      if (entity is File) {
        out[zipPath] = entity.readAsBytesSync();
        n++;
      } else if (entity is Directory) {
        n += _collectTree(entity.path, zipPath, out);
      }
    }
    return n;
  }

  /// 插件导出排除清单（.egsync 规格 §二 / t7 探索）：
  /// 安装元数据（.manifest/.signature/.released_manifest.json/.config_backup——
  /// 导入端重新生成）、构建产物（__pycache__/build/dist/node_modules/.dart_tool/
  /// *.spec）、VCS（.git）与嵌套草稿目录（drafts/backup）。
  static const Set<String> _excludedBasenames = {
    '.manifest',
    '.signature',
    '.released_manifest.json',
    '.config_backup',
    '__pycache__',
    'node_modules',
    '.dart_tool',
    '.git',
    'build',
    'dist',
    'drafts',
    'backup',
  };

  static const Set<String> _excludedExtensions = {'.spec'};

  /// 列出插件根下具有能力标记的插件 id（无标记的草稿目录跳过）。
  List<String> _listPluginIds() {
    final root = Directory(pluginsRoot);
    if (!root.existsSync()) return const [];
    final ids = <String>[];
    for (final entity in root.listSync()) {
      if (entity is! Directory) continue;
      final id = p.basename(entity.path);
      if (id.startsWith('.')) continue;
      if (_hasCapabilityMarkers(entity.path)) ids.add(id);
    }
    ids.sort();
    return ids;
  }

  /// 能力标记：根 manifest.json 或能力子目录（module/agent/data/skill/config/theme）。
  bool _hasCapabilityMarkers(String dirPath) {
    if (File(p.join(dirPath, 'manifest.json')).existsSync()) return true;
    for (final cap in const ['module', 'agent', 'data', 'skill', 'config', 'theme']) {
      if (Directory(p.join(dirPath, cap)).existsSync()) return true;
    }
    return false;
  }

  /// 拷贝插件目录树（应用排除清单），zip 前缀 `plugins/<id>/`。返回文件数。
  bool _collectPlugin(String id, Map<String, List<int>> out) {
    final src = p.join(pluginsRoot, id);
    return _copyTreeFiltered(src, 'plugins/$id', out) > 0;
  }

  /// 数据源：`data/<id>/data/` + `data/<id>/config/`（.egsync 规格 §二）。
  bool _collectDataSource(String id, Map<String, List<int>> out) {
    var n = 0;
    final dataDir = p.join(pluginsRoot, id, 'data');
    if (Directory(dataDir).existsSync()) {
      n += _copyTreeFiltered(dataDir, 'data/$id/data', out);
    }
    final configDir = p.join(pluginsRoot, id, 'config');
    if (Directory(configDir).existsSync()) {
      n += _copyTreeFiltered(configDir, 'data/$id/config', out);
    }
    return n > 0;
  }

  /// 主题：`themes/<id>/theme/theme.json`（.egsync 规格 §二）。
  bool _collectTheme(String id, Map<String, List<int>> out) {
    final file = File(p.join(pluginsRoot, id, 'theme', 'theme.json'));
    if (!file.existsSync()) return false;
    out['themes/$id/theme/theme.json'] = file.readAsBytesSync();
    return true;
  }

  /// 带排除清单的树拷贝（插件/数据源用），返回文件数。
  int _copyTreeFiltered(String dirPath, String prefix, Map<String, List<int>> out) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return 0;
    var n = 0;
    for (final entity in dir.listSync()) {
      final name = p.basename(entity.path);
      if (name.startsWith('.') || _excludedBasenames.contains(name)) continue;
      if (_excludedExtensions.contains(p.extension(name))) continue;
      final zipPath = '$prefix/${name.replaceAll('\\', '/')}';
      if (entity is File) {
        out[zipPath] = entity.readAsBytesSync();
        n++;
      } else if (entity is Directory) {
        n += _copyTreeFiltered(entity.path, zipPath, out);
      }
    }
    return n;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // manifest
  // ═══════════════════════════════════════════════════════════════════════

  Map<String, Object?> _buildManifest(SyncSelection selection, List<String> resources) {
    final selectedResources = selection.resources.map((r) => r.name).toList()..sort();
    return <String, Object?>{
      'type': 'egsync',
      'version': kEgsyncPackageVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      if (appVersion != null) 'appVersion': appVersion,
      'platform': Platform.operatingSystem,
      'resources': resources,
      'options': <String, Object?>{
        'selections': <String, Object?>{
          'resources': selectedResources,
          'pluginGroups': selection.pluginGroups.toList()..sort(),
        },
        'includeSecure': selection.includeSecure,
        'merge': selection.merge,
      },
    };
  }
}
