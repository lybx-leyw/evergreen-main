/// 同步中心导入端（t16 / 总规划 t-C3，core-module 域）——把 `.egsync.zip` fail-closed
/// 校验后落盘并注册（插件 / 数据源 / 主题），含版本感知冲突策略。
///
/// 契约依据：`docs/superpowers/specs/egsync-sync-center-spec-v1.md`（t11，core-config 产出）。
///
/// # 职责边界
/// - 本服务只做**落盘与注册回放**：插件 → `resolvePluginsRoot()/<id>/` +
///   `ModuleRegistry.reloadModule`；数据源（模型 A）→ 落盘 + `registerDataSourcesFromManifest`；
///   主题 → 落盘 + `ThemeStore.register`；sessions/memories → 原样落盘（合并算法属 t-C4/core-agent）。
/// - 配置（config.evgconfig）导入由 core-config 的 `importConfigAndSync` 负责——本服务通过
///   注入的 [configImporter] 回调交接；未注入时记录 skipped 项（不静默）。
/// - 数据源模型 B（HTTP .exe 长驻）回放属 core-data 域（DataSourceLoader），本服务只落盘并
///   在 item 消息中标注交接。
///
/// # Fail-closed 校验清单
/// 1. 包级（违反 → 整体拒绝，返回 Err）：
///    - `manifest.json` 根文件必存在且 `type == "egsync"`。
///    - `version` 为 int 且在 `[1..kEgsyncCurrentVersion]`，更高版本拒绝（提示升级应用）。
///    - 任意 ZIP 条目路径不安全（绝对路径 / `..` / 反斜杠 / 盘符 / 空段）→ 整体拒绝，**不静默跳过**。
/// 2. 资源级（违反 → 该项记为 error，不阻断其余资源）：
///    - `resources` 声明的资源目录在包内必须存在（缺失 → 该项 error）。
///    - 插件：`module/manifest.json` 必须可经 `ModuleDescriptor.fromJson` 解析；.plugin 信封
///      （`plugins/<id>/manifest.json` + 可选 `files:{relPath:sha256}` + 可选 `.signature`）
///      校验 type/必填字段、逐文件哈希、签名（SHA-256 常数时间比对）。
///    - 数据源：`data/manifest.json` 必须可解析且 `type == "data-source"`。
///    - 主题：`theme/theme.json` 必须可经 `ThemeDescriptor.fromJson` 解析（8 必填色）。
///    - 未知资源类型 → 静默跳过（沿用「未知静默忽略」约定）。
///
/// # 冲突策略（版本感知，`SyncImportPolicy`）
/// - 目标不存在 → 直接导入。
/// - 同版本同内容（目录指纹一致）→ no-op（不落盘不注册）。
/// - 新版（compareVersions > 0）→ 覆盖：先备份旧 `config/` 到 `.config_backup_<ts>`，
///   解包后恢复（用户 config 保留）。
/// - 同版本不同内容 / 版本回退 → 默认返回 [SyncConflict] 清单**不自动破坏**；
///   `applyConflicts: true` 时按 `overwriteSameVersion` / `allowDowngrade` 开关执行
///   （开关为关 → 该项 skip，不落盘）。
/// - 主题（纯数据、无版本）默认不同内容即覆盖（`overwriteThemes` 可关）。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../data/orchestrator.dart';
import '../data/plugin/data_source_loader.dart';
import '../data/plugin/data_source_manifest.dart';
import '../data/register_data_source.dart';
import '../errors.dart';
import '../log.dart';
import '../module/module_descriptor.dart';
import '../module/module_registry.dart';
import '../result.dart';
import '../theme/theme_descriptor.dart';
import '../theme/theme_store.dart';
import '../utils/greenix_path.dart';
import 'plugin_installer.dart' show compareVersions;

/// 当前支持的 .egsync 包格式版本（manifest.version 上限）。
const int kEgsyncCurrentVersion = 1;

/// 同步中心导入的资源配置类型（与 manifest.resources 一一对应）。
enum SyncResourceType {
  config,
  sessions,
  memories,
  plugins,
  data,
  themes;

  /// 资源类型 → .egsync.zip 顶层目录名。
  String get topDir => switch (this) {
        SyncResourceType.config => 'config',
        SyncResourceType.sessions => 'sessions',
        SyncResourceType.memories => 'memories',
        SyncResourceType.plugins => 'plugins',
        SyncResourceType.data => 'data',
        SyncResourceType.themes => 'themes',
      };

  /// 从资源类型字符串解析；未知返回 null（调用方静默跳过）。
  static SyncResourceType? tryParse(String raw) {
    for (final t in SyncResourceType.values) {
      if (t.name == raw) return t;
    }
    return null;
  }
}

/// 单个资源的导入动作。
enum SyncImportAction {
  /// 已落盘并（如适用）注册。
  imported,

  /// 内容一致，跳过（no-op）。
  noop,

  /// 未处理（等待其它 OWNER 接入 / 未知类型被忽略 / 冲突被策略跳过）。
  skipped,

  /// 冲突，等待用户决策（未落盘）。
  conflict,

  /// 校验失败或落盘失败（未落盘）。
  error,
}

/// 单个资源的导入结果条目。
class SyncImportItem {
  final SyncResourceType type;
  final String id;
  final SyncImportAction action;
  final String? message;

  /// 目标版本（插件/数据源，主题无版本时为 null）。
  final String? version;

  const SyncImportItem({
    required this.type,
    required this.id,
    required this.action,
    this.message,
    this.version,
  });
}

/// 需用户决策的冲突（默认不自动破坏）。
class SyncConflict {
  final SyncResourceType type;
  final String id;

  /// 已安装版本（'0.0.0' 表示读不到）。
  final String existingVersion;

  /// 导入包内版本。
  final String incomingVersion;

  /// 'same-version-different'（同版本内容不同）| 'downgrade'（版本回退）| 'newer-blocked'。
  final String reason;

  const SyncConflict({
    required this.type,
    required this.id,
    required this.existingVersion,
    required this.incomingVersion,
    required this.reason,
  });
}

/// 导入冲突策略（版本感知）。
class SyncImportPolicy {
  /// 新版（版本号更大）自动覆盖（覆盖前备份旧 config/）。默认 true。
  final bool overwriteNewer;

  /// 同版本但内容不同：false（默认）→ 冲突清单；true → 覆盖。
  final bool overwriteSameVersion;

  /// 允许版本回退（导入版本 < 已装版本）。默认 false → 冲突清单。
  final bool allowDowngrade;

  /// 是否自动执行冲突决策（按上面三个开关）。false（默认）→ 冲突仅返回清单不落盘。
  final bool applyConflicts;

  /// 主题（纯数据）同 id 不同内容是否直接覆盖。默认 true。
  final bool overwriteThemes;

  /// sessions/memories 等运行时数据已存在且内容不同时是否覆盖。默认 false → 冲突清单。
  final bool overwriteRuntimeData;

  const SyncImportPolicy({
    this.overwriteNewer = true,
    this.overwriteSameVersion = false,
    this.allowDowngrade = false,
    this.applyConflicts = false,
    this.overwriteThemes = true,
    this.overwriteRuntimeData = false,
  });
}

/// 导入结果汇总。
class SyncImportResult {
  final List<SyncImportItem> items;
  final List<SyncConflict> conflicts;
  final Map<SyncResourceType, int> counts;

  const SyncImportResult({
    required this.items,
    required this.conflicts,
    required this.counts,
  });

  bool get hasConflicts => conflicts.isNotEmpty;

  bool get hasErrors => items.any((i) => i.action == SyncImportAction.error);

  int countOf(SyncImportAction action) =>
      items.where((i) => i.action == action).length;
}

/// 冲突决策纯逻辑枚举（库级私有）。
enum _ConflictDecision { import, noop, conflict, skipped }

/// 解包安全拒绝信号（zip-slip 双保险触发）。
class SyncImportRejected implements Exception {
  final String message;
  SyncImportRejected(this.message);
  @override
  String toString() => message;
}

/// 同步中心导入服务。
///
/// 纯 Dart（根包 context 使用真实 archive/crypto；lib/core stub 隔离可独立 analyze）。
/// 用法：
/// ```dart
/// final service = SyncImportService(
///   registry: moduleRegistry,            // 插件注册回放（reloadModule）
///   themeStore: themeStore,              // 主题热注册
///   orch: dataOrchestrator,              // 数据源（模型 A）热注册
///   configImporter: importConfigAndSync, // core-config 配置导入回调
/// );
/// final result = await service.importZip('sync.egsync.zip');
/// if (result.hasConflicts) { /* 展示冲突清单，用户确认后以 applyConflicts 重导 */ }
/// ```
class SyncImportService {
  /// 模块注册中心（插件回放；可空 = 只落盘不注册）。
  final ModuleRegistry? registry;

  /// 主题存储（主题热注册；可空 = 只落盘不注册）。
  final ThemeStore? themeStore;

  /// 数据中枢（数据源模型 A 热注册；可空 = 只落盘不注册）。
  final DataOrchestrator? orch;

  /// 数据源 CLI fetcher 的 --project-root（缺省 [resolveProjectRoot]）。
  final String? projectRoot;

  /// 插件落盘根目录（缺省 [resolvePluginsRoot]，跨平台运行时解析）。
  final String? pluginsRoot;

  /// sessions 落盘目录（缺省 [greenixSessionsDir]；测试可注入临时目录）。
  final String? sessionsRoot;

  /// memories 落盘目录（缺省 [greenixMemoriesDir]；测试可注入临时目录）。
  final String? memoriesRoot;

  /// 配置导入回调（core-config：importConfigAndSync）。入参为解包出的 config/
  /// 临时目录路径；返回 null 表示成功，非 null 为错误消息。
  final Future<String?> Function(String configDirPath)? configImporter;

  SyncImportService({
    this.registry,
    this.themeStore,
    this.orch,
    this.projectRoot,
    this.pluginsRoot,
    this.sessionsRoot,
    this.memoriesRoot,
    this.configImporter,
  });

  String get _pluginsRoot => pluginsRoot ?? resolvePluginsRoot();
  String get _projectRoot =>
      projectRoot ?? resolveProjectRoot() ?? Directory.current.path;

  // ═══════════════════════════════════════════════════════════════
  // 公开入口
  // ═══════════════════════════════════════════════════════════════

  /// 导入一个 .egsync.zip。
  ///
  /// 包级 fail-closed 违规（type/version 非法、ZIP 路径越界）→ 返回 Err（整体拒绝）。
  /// 资源级问题 → 记为对应 item 的 error/conflict，其余资源继续导入。
  Future<Result<SyncImportResult>> importZip(
    String zipPath, {
    SyncImportPolicy policy = const SyncImportPolicy(),
  }) async {
    try {
      final bytes = File(zipPath).readAsBytesSync();
      final archive = ZipDecoder().decodeBytes(bytes);

      // ── 1. 路径安全：全部条目校验（fail-closed，越界整体拒绝） ──
      final files = <String, List<int>>{}; // relPath → bytes（仅文件）
      final dirs = <String>{};
      for (final f in archive.files) {
        if (!_isSafeZipPath(f.name, isDir: !f.isFile)) {
          Log().error('SyncImport: 拒绝不安全路径 ${f.name}（整体拒绝）');
          return Err(DataIntegrityError.logicalError(
              'egsync', '包内含不安全路径 ${f.name}，拒绝导入'));
        }
        if (f.isFile) {
          files[f.name] = f.content;
        } else {
          dirs.add(f.name);
        }
      }

      // ── 2. 包级 manifest 校验（fail-closed） ──
      final pkgManifest = files['manifest.json'];
      if (pkgManifest == null) {
        return Err(DataIntegrityError.missingField('egsync/manifest.json', 'file'));
      }
      final decoded = jsonDecode(utf8.decode(pkgManifest));
      if (decoded is! Map<String, dynamic>) {
        return Err(ValidationError.invalid(
            'egsync.manifest', 'must_be_object', '顶层必须是对象'));
      }
      if (decoded['type'] != 'egsync') {
        return Err(ValidationError.invalid('egsync.manifest.type', 'must_be_egsync',
            'type 必须为 "egsync"（收到 ${decoded['type']}）'));
      }
      final version = decoded['version'];
      if (version is! int || version < 1 || version > kEgsyncCurrentVersion) {
        return Err(ValidationError.invalid(
            'egsync.manifest.version',
            'unsupported',
            '包格式版本 $version 不受支持（支持 1..$kEgsyncCurrentVersion），'
                '请升级应用后再导入'));
      }
      final resourcesRaw = decoded['resources'];
      if (resourcesRaw is! List) {
        return Err(ValidationError.invalid(
            'egsync.manifest.resources', 'must_be_array', 'resources 必须是数组'));
      }

      // ── 3. 资源级导入 ──
      final items = <SyncImportItem>[];
      final conflicts = <SyncConflict>[];
      final counts = <SyncResourceType, int>{};

      void record(SyncImportItem item) {
        items.add(item);
        counts[item.type] = (counts[item.type] ?? 0) + 1;
      }

      // 顶层目录集合（resources 一致性校验用）
      final topDirs = <String>{};
      for (final key in files.keys) {
        if (key.contains('/')) topDirs.add(key.split('/').first);
      }
      topDirs.addAll(dirs
          .map((d) => d.replaceAll(RegExp(r'/+$'), '').split('/').first));

      for (final raw in resourcesRaw) {
        if (raw is! String) {
          record(SyncImportItem(
              type: SyncResourceType.plugins,
              id: '<malformed>',
              action: SyncImportAction.error,
              message: 'resources 条目非字符串'));
          continue;
        }
        final type = SyncResourceType.tryParse(raw);
        if (type == null) {
          // 未知资源类型：静默跳过（沿用「未知静默忽略」约定）
          Log().info('SyncImport: 未知资源类型 "$raw"，跳过');
          record(SyncImportItem(
              type: SyncResourceType.plugins,
              id: raw,
              action: SyncImportAction.skipped,
              message: '未知资源类型，跳过'));
          continue;
        }
        final dir = type.topDir;
        final dirFiles = _entriesUnder(files, '$dir/');
        if (dirFiles.isEmpty) {
          record(SyncImportItem(
              type: type,
              id: dir,
              action: SyncImportAction.error,
              message: 'manifest 声明了 "$dir" 但包内无对应目录'));
          continue;
        }
        switch (type) {
          case SyncResourceType.plugins:
            await _importPlugins(dirFiles, policy, record, conflicts);
          case SyncResourceType.data:
            await _importDataSources(dirFiles, policy, record, conflicts);
          case SyncResourceType.themes:
            await _importThemes(dirFiles, policy, record, conflicts);
          case SyncResourceType.config:
            await _importConfig(dirFiles, record);
          case SyncResourceType.sessions:
            await _importRuntimeFiles(dirFiles, SyncResourceType.sessions,
                _sessionsRoot(), policy, record, conflicts);
          case SyncResourceType.memories:
            await _importRuntimeFiles(dirFiles, SyncResourceType.memories,
                _memoriesRoot(), policy, record, conflicts);
        }
      }

      Log().info('SyncImport: 导入完成 items=${items.length} conflicts=${conflicts.length}');
      return Ok(SyncImportResult(items: items, conflicts: conflicts, counts: counts));
    } catch (e, st) {
      if (e is SyncImportRejected) {
        Log().error('SyncImport: 解包安全拒绝: ${e.message}');
        return Err(DataIntegrityError.logicalError('egsync', e.message));
      }
      Log().error('SyncImport: 导入异常', error: e, stack: st);
      return Err(UnknownError.from(e));
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // 插件导入
  // ═══════════════════════════════════════════════════════════════

  Future<void> _importPlugins(
    Map<String, List<int>> dirFiles,
    SyncImportPolicy policy,
    void Function(SyncImportItem) record,
    List<SyncConflict> conflicts,
  ) async {
    final byId = _groupById(dirFiles);
    for (final entry in byId.entries) {
      final id = entry.key;
      final rel = entry.value; // <rest> → bytes
      final outcome = _validatePlugin(id, rel);
      if (outcome.error != null) {
        record(SyncImportItem(
            type: SyncResourceType.plugins,
            id: id,
            action: SyncImportAction.error,
            message: outcome.error));
        continue;
      }

      final target = p.join(_pluginsRoot, id);
      final version = outcome.version;
      final fingerprint = _fingerprint(rel);

      // 冲突决策（版本感知）
      final existing = Directory(target);
      final decision = existing.existsSync()
          ? _decideConflict(
              policy: policy,
              cmp: compareVersions(version, _existingVersion(target)),
              sameContent: _dirFingerprint(target) == fingerprint,
            )
          : _ConflictDecision.import;
      if (decision == _ConflictDecision.noop) {
        record(SyncImportItem(
            type: SyncResourceType.plugins,
            id: id,
            action: SyncImportAction.noop,
            version: version,
            message: '同版本同内容，跳过'));
        continue;
      }
      if (decision == _ConflictDecision.conflict) {
        conflicts.add(SyncConflict(
            type: SyncResourceType.plugins,
            id: id,
            existingVersion: _existingVersion(target),
            incomingVersion: version,
            reason: _conflictReason(
                cmp: compareVersions(version, _existingVersion(target)))));
        record(SyncImportItem(
            type: SyncResourceType.plugins,
            id: id,
            action: SyncImportAction.conflict,
            version: version,
            message: '冲突，等待用户决策'));
        continue;
      }
      if (decision == _ConflictDecision.skipped) {
        record(SyncImportItem(
            type: SyncResourceType.plugins,
            id: id,
            action: SyncImportAction.skipped,
            version: version,
            message: '冲突被策略跳过（未落盘）'));
        continue;
      }

      // decision == import（含覆盖）：备份旧 config
      if (existing.existsSync()) _backupConfig(target);

      // 落盘（先删旧目录保证干净，config 已备份）
      if (Directory(target).existsSync()) {
        Directory(target).deleteSync(recursive: true);
      }
      Directory(target).createSync(recursive: true);
      try {
        _extractTo(rel, target);
      } catch (e) {
        record(SyncImportItem(
            type: SyncResourceType.plugins,
            id: id,
            action: SyncImportAction.error,
            version: version,
            message: '落盘失败: $e'));
        continue;
      }
      // 恢复旧 config
      _restoreConfigBackup(target);

      // 注册回放
      final moduleManifest = rel['module/manifest.json'];
      if (moduleManifest != null && registry != null) {
        try {
          final descriptor =
              ModuleDescriptor.fromJsonString(utf8.decode(moduleManifest));
          final ok = registry!.reloadModule(descriptor);
          if (!ok) {
            record(SyncImportItem(
                type: SyncResourceType.plugins,
                id: id,
                action: SyncImportAction.error,
                version: version,
                message: '落盘成功但注册失败（依赖缺失），重启后生效'));
            continue;
          }
        } catch (e) {
          Log().warn('SyncImport: 插件注册失败 $id', error: e);
        }
      }
      record(SyncImportItem(
          type: SyncResourceType.plugins,
          id: id,
          action: SyncImportAction.imported,
          version: version,
          message: '已落盘 ${p.relative(target, from: _pluginsRoot)}'));
    }
  }

  /// 插件校验（fail-closed）：返回错误信息或版本。
  ({String? error, String version}) _validatePlugin(
      String id, Map<String, List<int>> rel) {
    // .plugin 信封：plugins/<id>/manifest.json（type:"plugin"）
    final envelope = rel['manifest.json'];
    if (envelope != null) {
      try {
        final m = jsonDecode(utf8.decode(envelope)) as Map<String, dynamic>;
        if (m['type'] != 'plugin') {
          return (error: '插件 $id 信封 manifest.type 必须为 "plugin"', version: '0.0.0');
        }
        final vid = m['id'] as String?;
        final name = m['name'] as String?;
        final version = m['version'] as String?;
        if (vid == null || vid.isEmpty || name == null || name.isEmpty ||
            version == null || version.isEmpty) {
          return (error: '插件 $id 信封 manifest 缺 id/name/version', version: '0.0.0');
        }
        if (vid != id) {
          return (error: '插件 $id 信封 manifest.id($vid) 与目录名不一致', version: '0.0.0');
        }
        // 内容寻址完整性：files:{relPath:sha256}
        final filesMap = m['files'];
        if (filesMap is Map) {
          final err = _verifyFileHashes(filesMap, rel);
          if (err != null) return (error: err, version: '0.0.0');
        }
        // 签名（若带 .signature）：SHA-256(manifest.json 原始字节) 常数时间比对
        final sig = rel['.signature'];
        if (sig != null) {
          final expected = utf8.decode(sig).trim();
          final computed = sha256.convert(envelope).toString();
          if (!_constantTimeEquals(expected, computed)) {
            return (error: '插件 $id 签名校验失败', version: '0.0.0');
          }
        }
        return (error: null, version: version);
      } catch (e) {
        return (error: '插件 $id 信封 manifest 解析失败: $e', version: '0.0.0');
      }
    }

    // 运行时形态：module/manifest.json 必须可解析（fail-closed）
    final moduleManifest = rel['module/manifest.json'];
    if (moduleManifest != null) {
      try {
        final d = ModuleDescriptor.fromJsonString(utf8.decode(moduleManifest));
        return (error: null, version: d.version);
      } catch (e) {
        return (error: '插件 $id 的 module/manifest.json 无法解析: $e', version: '0.0.0');
      }
    }
    // 无 module 能力的插件（agent/data/theme/config/skill 单能力）允许
    if (rel.keys.any((k) =>
        k.startsWith('agent/') ||
        k.startsWith('theme/') ||
        k.startsWith('data/') ||
        k.startsWith('config/') ||
        k.startsWith('skill/'))) {
      return (error: null, version: '0.0.0');
    }
    return (error: '插件 $id 无任何能力子目录（module/agent/data/theme/config/skill）',
        version: '0.0.0');
  }

  String? _verifyFileHashes(dynamic filesMap, Map<String, List<int>> rel) {
    final map = filesMap as Map;
    for (final e in map.entries) {
      final relPath = e.key.toString();
      final expected = e.value.toString();
      final bytes = rel[relPath];
      if (bytes == null) {
        return '插件内容寻址缺失文件 $relPath';
      }
      final actual = sha256.convert(bytes).toString();
      if (actual != expected) {
        return '插件内容寻址校验失败: $relPath';
      }
    }
    return null;
  }

  // ═══════════════════════════════════════════════════════════════
  // 数据源导入
  // ═══════════════════════════════════════════════════════════════

  Future<void> _importDataSources(
    Map<String, List<int>> dirFiles,
    SyncImportPolicy policy,
    void Function(SyncImportItem) record,
    List<SyncConflict> conflicts,
  ) async {
    final byId = _groupById(dirFiles);
    for (final entry in byId.entries) {
      final id = entry.key;
      final rel = entry.value;
      final manifestBytes = rel['data/manifest.json'];
      if (manifestBytes == null) {
        record(SyncImportItem(
            type: SyncResourceType.data,
            id: id,
            action: SyncImportAction.error,
            message: '缺少 data/manifest.json'));
        continue;
      }
      late Map<String, dynamic> manifest;
      try {
        final m = jsonDecode(utf8.decode(manifestBytes)) as Map<String, dynamic>;
        if (m['type'] != 'data-source') {
          record(SyncImportItem(
              type: SyncResourceType.data,
              id: id,
              action: SyncImportAction.error,
              message: 'data/manifest.json type 必须为 "data-source"'));
          continue;
        }
        manifest = m;
      } catch (e) {
        record(SyncImportItem(
            type: SyncResourceType.data,
            id: id,
            action: SyncImportAction.error,
            message: 'data/manifest.json 无法解析: $e'));
        continue;
      }

      final version = manifest['version'] as String? ?? '0.0.0';
      final target = p.join(_pluginsRoot, id);
      final fingerprint = _fingerprint(rel);

      // 冲突决策（与插件同构，版本感知）
      final existing = Directory(target);
      final decision = existing.existsSync()
          ? _decideConflict(
              policy: policy,
              cmp: compareVersions(version, _existingVersion(target)),
              sameContent: _dirFingerprint(target) == fingerprint,
            )
          : _ConflictDecision.import;
      if (decision == _ConflictDecision.noop) {
        record(SyncImportItem(
            type: SyncResourceType.data,
            id: id,
            action: SyncImportAction.noop,
            version: version,
            message: '同版本同内容，跳过'));
        continue;
      }
      if (decision == _ConflictDecision.conflict) {
        conflicts.add(SyncConflict(
            type: SyncResourceType.data,
            id: id,
            existingVersion: _existingVersion(target),
            incomingVersion: version,
            reason: _conflictReason(
                cmp: compareVersions(version, _existingVersion(target)))));
        record(SyncImportItem(
            type: SyncResourceType.data,
            id: id,
            action: SyncImportAction.conflict,
            version: version,
            message: '冲突，等待用户决策'));
        continue;
      }
      if (decision == _ConflictDecision.skipped) {
        record(SyncImportItem(
            type: SyncResourceType.data,
            id: id,
            action: SyncImportAction.skipped,
            version: version,
            message: '冲突被策略跳过（未落盘）'));
        continue;
      }

      if (existing.existsSync()) _backupConfig(target);
      if (Directory(target).existsSync()) {
        Directory(target).deleteSync(recursive: true);
      }
      Directory(target).createSync(recursive: true);
      try {
        _extractTo(rel, target);
      } catch (e) {
        record(SyncImportItem(
            type: SyncResourceType.data,
            id: id,
            action: SyncImportAction.error,
            version: version,
            message: '落盘失败: $e'));
        continue;
      }
      _restoreConfigBackup(target);

      // 注册回放：模型 A（CLI）→ registerDataSourcesFromManifest；
      // 模型 B（HTTP 长驻 .exe，legacy）→ DataSourceLoader 回放（best-effort，失败仅降级不阻断包）。
      final isModelB = manifest['process'] != null && manifest['script'] == null;
      String replayNote;
      if (orch == null) {
        replayNote = '已落盘（未注册：未提供 orch）';
      } else if (isModelB) {
        try {
          final loader = DataSourceLoader(
            manifest: DataSourceManifest.fromJsonString(jsonEncode(manifest)),
            workingDirectory: p.join(target, 'data'),
            projectRoot: _projectRoot,
          );
          await loader.start(orch!);
          replayNote = '已落盘并回放模型 B（DataSourceLoader）';
        } catch (e) {
          // 跨平台常见：安卓 Chaquopy 无法 exec 桌面 PE 二进制 → 回放失败仅降级提示
          Log().warn('SyncImport: 数据源 $id 模型 B 回放失败（已降级为仅落盘）', error: e);
          replayNote = '已落盘（模型 B 回放失败: $e，可手动启动）';
        }
      } else {
        final replayed = registerDataSourcesFromManifest(
          orch: orch!,
          pluginDir: target,
          projectRoot: _projectRoot,
        );
        replayNote = replayed.isNotEmpty ? '已落盘并注册数据源' : '已落盘（未注册：无 dataTypes）';
      }
      record(SyncImportItem(
          type: SyncResourceType.data,
          id: id,
          action: SyncImportAction.imported,
          version: version,
          message: replayNote));
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // 主题导入
  // ═══════════════════════════════════════════════════════════════

  Future<void> _importThemes(
    Map<String, List<int>> dirFiles,
    SyncImportPolicy policy,
    void Function(SyncImportItem) record,
    List<SyncConflict> conflicts,
  ) async {
    final byId = _groupById(dirFiles);
    for (final entry in byId.entries) {
      final id = entry.key;
      final rel = entry.value;
      final themeBytes = rel['theme/theme.json'];
      if (themeBytes == null) {
        record(SyncImportItem(
            type: SyncResourceType.themes,
            id: id,
            action: SyncImportAction.error,
            message: '缺少 theme/theme.json'));
        continue;
      }
      late ThemeDescriptor theme;
      try {
        theme = ThemeDescriptor.fromJson(
            jsonDecode(utf8.decode(themeBytes)) as Map<String, dynamic>);
      } catch (e) {
        record(SyncImportItem(
            type: SyncResourceType.themes,
            id: id,
            action: SyncImportAction.error,
            message: 'theme.json 无法解析（8 必填色校验失败）: $e'));
        continue;
      }

      final targetFile = p.join(_pluginsRoot, id, 'theme', 'theme.json');
      final fingerprint = sha256.convert(themeBytes).toString();
      if (File(targetFile).existsSync()) {
        final existingFp =
            sha256.convert(File(targetFile).readAsBytesSync()).toString();
        if (existingFp == fingerprint) {
          record(SyncImportItem(
              type: SyncResourceType.themes,
              id: id,
              action: SyncImportAction.noop,
              message: '同内容，跳过'));
          continue;
        }
        if (!policy.overwriteThemes) {
          if (policy.applyConflicts) {
            record(SyncImportItem(
                type: SyncResourceType.themes,
                id: id,
                action: SyncImportAction.skipped,
                message: '主题内容不同，被策略跳过'));
            continue;
          }
          conflicts.add(SyncConflict(
              type: SyncResourceType.themes,
              id: id,
              existingVersion: '0.0.0',
              incomingVersion: '0.0.0',
              reason: 'same-version-different'));
          record(SyncImportItem(
              type: SyncResourceType.themes,
              id: id,
              action: SyncImportAction.conflict,
              message: '主题内容不同，等待用户决策'));
          continue;
        }
      }

      File(targetFile).parent.createSync(recursive: true);
      File(targetFile).writeAsBytesSync(themeBytes);

      // 注册回放：ThemeStore 热注册（同 id 后者覆盖）
      if (themeStore != null) {
        themeStore!.register(theme);
      }
      record(SyncImportItem(
          type: SyncResourceType.themes,
          id: id,
          action: SyncImportAction.imported,
          message: '已落盘 plugins/$id/theme/theme.json'));
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // config / sessions / memories
  // ═══════════════════════════════════════════════════════════════

  Future<void> _importConfig(
      Map<String, List<int>> dirFiles, void Function(SyncImportItem) record) async {
    if (configImporter == null) {
      record(SyncImportItem(
          type: SyncResourceType.config,
          id: 'config',
          action: SyncImportAction.skipped,
          message: '配置导入由 core-config importConfigAndSync 负责，本端未注入回调'));
      return;
    }
    // 解包到临时目录后交给 core-config
    final staging = Directory.systemTemp.createTempSync('egsync_config_');
    try {
      _extractTo(dirFiles, staging.path);
      final err = await configImporter!(staging.path);
      record(SyncImportItem(
          type: SyncResourceType.config,
          id: 'config',
          action: err == null ? SyncImportAction.imported : SyncImportAction.error,
          message: err ?? '配置已导入'));
    } catch (e) {
      record(SyncImportItem(
          type: SyncResourceType.config,
          id: 'config',
          action: SyncImportAction.error,
          message: '配置导入失败: $e'));
    } finally {
      try {
        staging.deleteSync(recursive: true);
      } catch (_) {}
    }
  }

  Future<void> _importRuntimeFiles(
    Map<String, List<int>> dirFiles,
    SyncResourceType type,
    String targetRoot,
    SyncImportPolicy policy,
    void Function(SyncImportItem) record,
    List<SyncConflict> conflicts,
  ) async {
    Directory(targetRoot).createSync(recursive: true);
    var landed = 0;
    var noop = 0;
    for (final e in dirFiles.entries) {
      final relPath = e.key; // sessions/<file> 或 memories/<file>（含顶层目录段）
      final baseName = p.basename(relPath);
      final target = p.join(targetRoot, baseName);
      if (File(target).existsSync()) {
        if (_bytesEqual(File(target).readAsBytesSync(), e.value)) {
          noop++;
          continue;
        }
        if (!policy.overwriteRuntimeData) {
          if (policy.applyConflicts) {
            continue; // 策略跳过：不落盘、不进冲突清单
          }
          conflicts.add(SyncConflict(
              type: type,
              id: baseName,
              existingVersion: '0.0.0',
              incomingVersion: '0.0.0',
              reason: 'same-version-different'));
          record(SyncImportItem(
              type: type,
              id: baseName,
              action: SyncImportAction.conflict,
              message: '已存在且内容不同，等待用户决策'));
          continue;
        }
      }
      File(target).writeAsBytesSync(e.value);
      landed++;
    }
    if (landed > 0 || noop > 0) {
      record(SyncImportItem(
          type: type,
          id: type.name,
          action: SyncImportAction.imported,
          message: '落盘 $landed 个文件（$noop 个同内容跳过）'));
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // 冲突决策纯逻辑
  // ═══════════════════════════════════════════════════════════════

  /// 版本感知冲突决策（纯函数，可单测）。
  ///
  /// [cmp] = compareVersions(导入版本, 已装版本)；[sameContent] = 内容指纹一致。
  _ConflictDecision _decideConflict({
    required SyncImportPolicy policy,
    required int cmp,
    required bool sameContent,
  }) {
    if (cmp == 0 && sameContent) return _ConflictDecision.noop;
    final overwrite = cmp > 0
        ? policy.overwriteNewer
        : (cmp < 0 ? policy.allowDowngrade : policy.overwriteSameVersion);
    if (overwrite) return _ConflictDecision.import;
    // 冲突：applyConflicts=true 且开关为关 → 跳过（不落盘）；否则返回冲突清单
    return policy.applyConflicts
        ? _ConflictDecision.skipped
        : _ConflictDecision.conflict;
  }

  String _conflictReason({required int cmp}) {
    if (cmp > 0) return 'newer-blocked';
    if (cmp < 0) return 'downgrade';
    return 'same-version-different';
  }

  // ═══════════════════════════════════════════════════════════════
  // 工具
  // ═══════════════════════════════════════════════════════════════

  String _sessionsRoot() => sessionsRoot ?? greenixSessionsDir;
  String _memoriesRoot() => memoriesRoot ?? greenixMemoriesDir;

  /// ZIP 条目路径安全校验（fail-closed）：拒绝绝对路径 / `..` / 反斜杠 / 盘符 / 非法空段。
  bool _isSafeZipPath(String name, {required bool isDir}) {
    if (name.isEmpty) return false;
    if (name.contains('\\')) return false; // Windows 分隔符混入一律拒绝
    if (name.startsWith('/')) return false;
    if (RegExp(r'^[A-Za-z]:').hasMatch(name)) return false;
    final segs = name.split('/');
    for (var i = 0; i < segs.length; i++) {
      final s = segs[i];
      if (s.isEmpty) {
        // 仅允许目录条目末尾的尾随斜杠段
        if (isDir && i == segs.length - 1) continue;
        return false;
      }
      if (s == '..' || s == '.') return false;
    }
    return true;
  }

  /// 取顶层目录下的条目：'dir/<rest>' → <rest> → bytes。
  Map<String, List<int>> _entriesUnder(Map<String, List<int>> files, String prefix) {
    final out = <String, List<int>>{};
    for (final e in files.entries) {
      if (e.key.startsWith(prefix)) {
        out[e.key.substring(prefix.length)] = e.value;
      }
    }
    return out;
  }

  /// 按插件 id 分组：'<id>/<rest>'。
  Map<String, Map<String, List<int>>> _groupById(Map<String, List<int>> rel) {
    final out = <String, Map<String, List<int>>>{};
    for (final e in rel.entries) {
      final slash = e.key.indexOf('/');
      if (slash <= 0) continue;
      final id = e.key.substring(0, slash);
      final rest = e.key.substring(slash + 1);
      out.putIfAbsent(id, () => <String, List<int>>{})[rest] = e.value;
    }
    return out;
  }

  /// 落盘（相对路径 → 目标根；调用前已保证路径安全）。
  void _extractTo(Map<String, List<int>> rel, String targetRoot) {
    for (final e in rel.entries) {
      final dest = p.joinAll([targetRoot, ...e.key.split('/')]);
      // 防御：规范化后必须仍在目标根内（zip-slip 双保险）
      final canonicalTarget = p.canonicalize(targetRoot);
      final canonicalDest = p.canonicalize(dest);
      if (canonicalDest != canonicalTarget &&
          !canonicalDest.startsWith('$canonicalTarget${p.separator}')) {
        throw SyncImportRejected('解包越界路径 ${e.key}');
      }
      File(dest).parent.createSync(recursive: true);
      File(dest).writeAsBytesSync(e.value);
    }
  }

  /// 插件内容指纹：全部文件按相对路径排序后拼接哈希（确定性）。
  String _fingerprint(Map<String, List<int>> rel) {
    final sorted = rel.keys.toList()..sort();
    final buf = BytesBuilder();
    for (final k in sorted) {
      buf.add(utf8.encode('$k\n'));
      buf.add(rel[k]!);
      buf.addByte(0);
    }
    return sha256.convert(buf.toBytes()).toString();
  }

  /// 已安装插件目录指纹（同 [_fingerprint] 算法）。
  String _dirFingerprint(String dirPath) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return '';
    final files = <String>[];
    void walk(Directory d, String prefix) {
      for (final e in d.listSync()) {
        final rel =
            prefix.isEmpty ? p.basename(e.path) : '$prefix/${p.basename(e.path)}';
        if (e is File) {
          files.add(rel);
        } else if (e is Directory) {
          walk(e, rel);
        }
      }
    }

    walk(dir, '');
    files.sort();
    final buf = BytesBuilder();
    for (final f in files) {
      buf.add(utf8.encode('$f\n'));
      try {
        buf.add(File(p.join(dirPath, f)).readAsBytesSync());
      } catch (_) {}
      buf.addByte(0);
    }
    return sha256.convert(buf.toBytes()).toString();
  }

  /// 读取已装插件版本：优先 .manifest 元数据，其次各能力 manifest（module/data）。
  String _existingVersion(String target) {
    try {
      final meta = File(p.join(target, '.manifest'));
      if (meta.existsSync()) {
        final m = jsonDecode(meta.readAsStringSync()) as Map<String, dynamic>;
        final v = m['version'] as String?;
        if (v != null && v.isNotEmpty) return v;
      }
      for (final rel in const ['module/manifest.json', 'data/manifest.json']) {
        final f = File(p.join(target, rel));
        if (f.existsSync()) {
          final m = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
          final v = m['version'] as String?;
          if (v != null && v.isNotEmpty) return v;
        }
      }
    } catch (_) {}
    return '0.0.0';
  }

  /// 覆盖前备份旧 config/ → `.config_backup_<ts>`（保留用户配置）。
  void _backupConfig(String target) {
    final configDir = Directory(p.join(target, 'config'));
    if (!configDir.existsSync()) return;
    try {
      final ts = DateTime.now().millisecondsSinceEpoch;
      final backup = Directory(p.join(target, '.config_backup_$ts'));
      configDir.renameSync(backup.path);
      Log().info('SyncImport: 已备份旧 config → ${backup.path}');
    } catch (e) {
      Log().warn('SyncImport: config 备份失败', error: e);
    }
  }

  /// 覆盖后恢复旧 config。
  void _restoreConfigBackup(String target) {
    final backups = Directory(target)
        .listSync()
        .whereType<Directory>()
        .where((d) => p.basename(d.path).startsWith('.config_backup_'))
        .toList();
    if (backups.isEmpty) return;
    try {
      final backup = backups.first;
      final configDir = Directory(p.join(target, 'config'));
      if (configDir.existsSync()) {
        configDir.deleteSync(recursive: true);
      }
      backup.renameSync(configDir.path);
      Log().info('SyncImport: 已恢复旧 config');
    } catch (e) {
      Log().warn('SyncImport: config 恢复失败', error: e);
    }
  }

  bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// 常数时间比较（防时序攻击，与 plugin_installer 一致）。
  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }
}
