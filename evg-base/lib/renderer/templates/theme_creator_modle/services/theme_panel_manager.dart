/// 主题面板管理器 —— 面板 ↔ 实例 ↔ 会话 双向绑定（对齐 html-creator CanvasManager）。
///
/// 数据模型（与 scraper / html-creator 对齐）：
/// - **一面板一实例**：面板创建之处即分配固定实例，实例 ID 永不改变；
/// - **实例 ID == 主题 ID（themeId）**：不单独生成 `instance_xxx`，
///   避免 html-creator 早期「两个 ID 分叉」的问题；导出时 [bindThemeId]
///   把实例对齐到最终主题 ID（含旧目录/会话迁移）；
/// - **一会话一固定历史，按实例隔离**：会话文件
///   `panels/{panelId}/instances/{instanceId}/session.json`，
///   文件内双向绑定 `panelId + instanceId`，加载时校验一致，
///   孤儿会话不恢复、可清理；
/// - **删除面板 = 递归删除整个面板目录**：实例与会话一并清理。
///
/// 目录结构：
/// ```text
/// {greenixWorkspaceDir('theme-creator')}/panels/
/// └── theme_panel_xxx/
///     ├── meta.json                  // ThemePanelMeta
///     ├── draft.json                 // 当前主题草稿
///     └── instances/{themeId}/
///         ├── meta.json              // ThemeInstanceMeta
///         └── session.json           // 消息 + UI 快照 + 断点续做数据
/// ```
///
/// 旧数据迁移（[migrateLegacyIfNeeded]）：
/// - 老版无面板模型：`drafts/*.json` 每个草稿 → 一个面板；
/// - 老版单例 `ThemeChatStore`（`chats/chat.json`）→ 迁入首个面板的实例
///   `session.json`（补写双向字段 + 草稿快照），随后改名防重复迁移。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:evergreen_base/core/utils/greenix_path.dart';

import '../models/theme_draft.dart';

// ═══════════════════════════════════════════════════════════════════════════
// 路径约定
// ═══════════════════════════════════════════════════════════════════════════

/// 面板根目录（`{greenixWorkspaceDir('theme-creator')}/panels`）。
String get _panelsRoot => p.join(_workspaceRoot, 'panels');

/// 主题创作工作区根（迁移标记/旧数据所在）。
String get _workspaceRoot => greenixWorkspaceDir('theme-creator');

/// 面板目录。
String panelDir(String panelId) => p.join(_panelsRoot, panelId);

/// 面板 meta 文件路径。
String panelMetaPath(String panelId) => p.join(panelDir(panelId), 'meta.json');

/// 面板草稿文件路径（当前配色状态，断点续做时恢复 UI）。
String panelDraftPath(String panelId) => p.join(panelDir(panelId), 'draft.json');

/// 实例目录（`panels/{panelId}/instances/{instanceId}/`）。
String instanceDir(String panelId, String instanceId) =>
    p.join(panelDir(panelId), 'instances', instanceId);

/// 实例 meta 文件路径。
String instanceMetaPath(String panelId, String instanceId) =>
    p.join(instanceDir(panelId, instanceId), 'meta.json');

/// 实例会话文件路径 —— 一会话一份历史记忆。
///
/// 会话按实例隔离（消息 + UI 快照 + 草稿快照），随面板目录生命周期：
/// 删除面板 = 删除整个面板目录 = 实例会话一并清理。
/// ThemeAiService 通过注入的 [ThemePanelManager.resolveSessionsPath] 使用本约定。
String instanceSessionsPath(String panelId, String instanceId) =>
    p.join(instanceDir(panelId, instanceId), 'session.json');

// ═══════════════════════════════════════════════════════════════════════════
// 元数据模型
// ═══════════════════════════════════════════════════════════════════════════

/// 面板元数据（对应 html-creator 的 [CanvasMeta]）。
class ThemePanelMeta {
  /// 面板唯一 ID：`theme_panel_xxx`，固定不可变。
  final String id;

  /// 面板名（可重命名，不改 id）。
  String name;

  /// 绑定的实例 ID（面板 ↔ 实例 1:1 锚点）。null = 老面板尚未分配实例
  /// （首次加载时 [ThemePanelManager.ensureInstance] 自动创建）。
  String? instanceId;

  /// 主题 ID == 实例 ID（可保留，但必须恒等于 [instanceId]，杜绝分叉）。
  String? themeId;

  /// 当前草稿/方案 ID，随面板保存。
  String? selectedDraftId;

  final DateTime createdAt;
  DateTime updatedAt;

  ThemePanelMeta({
    required this.id,
    required this.name,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.instanceId,
    this.themeId,
    this.selectedDraftId,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory ThemePanelMeta.fromJson(Map<String, dynamic> json) => ThemePanelMeta(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '未命名面板',
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'] as String)
            : null,
        updatedAt: json['updatedAt'] != null
            ? DateTime.tryParse(json['updatedAt'] as String)
            : null,
        instanceId: json['instanceId'] as String?,
        themeId: json['themeId'] as String?,
        selectedDraftId: json['selectedDraftId'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        if (instanceId != null) 'instanceId': instanceId,
        if (themeId != null) 'themeId': themeId,
        if (selectedDraftId != null) 'selectedDraftId': selectedDraftId,
      };
}

/// 实例元数据 —— 一会话一份历史记忆的载体。
///
/// 与 scraper / html-creator 对齐：实例 ID == 主题 ID（[ThemePanelMeta.themeId]），
/// 固定不可变；实例名可自定义重命名（重命名不丢会话、不动 id）。每个实例独占
/// 一份会话文件（消息 + UI 快照 + 草稿快照），文件内双向绑定 panelId + instanceId，
/// 加载时校验一致，孤儿（不匹配）不承认、可清理。
class ThemeInstanceMeta {
  /// 实例 ID（== 主题 ID；重命名只改 [name]）。
  final String id;

  /// 实例名（可自定义重命名；默认取面板名）。
  String name;

  /// 所属面板 ID（面板 ↔ 实例 1:1 锚点）。
  final String panelId;

  final DateTime createdAt;
  DateTime updatedAt;

  ThemeInstanceMeta({
    required this.id,
    required this.name,
    required this.panelId,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory ThemeInstanceMeta.fromJson(Map<String, dynamic> json) =>
      ThemeInstanceMeta(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '未命名实例',
        panelId: json['panelId'] as String? ?? '',
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'] as String)
            : null,
        updatedAt: json['updatedAt'] != null
            ? DateTime.tryParse(json['updatedAt'] as String)
            : null,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'panelId': panelId,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };
}

/// 实例 + 所属面板名的轻量组合（左栏「实例」视图平铺用）。
class ThemeInstanceRef {
  final ThemeInstanceMeta instance;
  final String panelName;
  const ThemeInstanceRef({required this.instance, required this.panelName});
}

/// 面板完整数据（meta + 当前草稿）。
class ThemePanelData {
  final ThemePanelMeta meta;
  final ThemeDraft? draft;

  const ThemePanelData({required this.meta, this.draft});
}

// ═══════════════════════════════════════════════════════════════════════════
// ID / 名称工具
// ═══════════════════════════════════════════════════════════════════════════

/// 生成唯一面板 ID。
String _newPanelId() =>
    'theme_panel_${DateTime.now().millisecondsSinceEpoch}_${_random4()}';

String _random4() => (DateTime.now().microsecondsSinceEpoch % 10000)
    .toString()
    .padLeft(4, '0');

/// 将名称/描述转为安全的主题 ID（snake_case：小写字母/数字/下划线）。
String sanitizeThemeId(String name) {
  var id = name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff_]'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
  if (id.isEmpty) id = 'my_theme';
  // 不以字母开头时补前缀（主题 id 要求 snake_case 开头字母）
  if (!RegExp(r'^[a-z]').hasMatch(id)) id = 'theme_$id';
  return id;
}

// ═══════════════════════════════════════════════════════════════════════════
// ThemePanelManager
// ═══════════════════════════════════════════════════════════════════════════

/// 主题面板管理器：创建/加载/列出/删除面板 + 实例与会话绑定。
class ThemePanelManager {
  /// 工作区根目录（可注入便于测试；默认 [greenixWorkspaceDir]('theme-creator'），
  /// 生产环境与顶层路径约定一致）。
  final String rootDir;

  ThemePanelManager({String? rootDir})
      : rootDir = rootDir ?? greenixWorkspaceDir('theme-creator');

  // ── 实例级路径（rootDir 可注入；生产与顶层路径约定一致） ──

  String get _panelsRoot => p.join(rootDir, 'panels');
  String get _workspaceRoot => rootDir;
  String panelDir(String panelId) => p.join(_panelsRoot, panelId);
  String panelMetaPath(String panelId) => p.join(panelDir(panelId), 'meta.json');
  String panelDraftPath(String panelId) => p.join(panelDir(panelId), 'draft.json');
  String instanceDir(String panelId, String instanceId) =>
      p.join(panelDir(panelId), 'instances', instanceId);
  String instanceMetaPath(String panelId, String instanceId) =>
      p.join(instanceDir(panelId, instanceId), 'meta.json');
  String instanceSessionsPath(String panelId, String instanceId) =>
      p.join(instanceDir(panelId, instanceId), 'session.json');
  String get _legacyMarkerPath => p.join(rootDir, '.legacy_migrated');
  String get _legacyDraftsRoot => p.join(rootDir, 'drafts');
  String get _legacyChatFile => p.join(rootDir, 'chats', 'chat.json');

  /// 是否已有面板（目录 + meta.json 均在场）。
  bool hasPanel(String panelId) {
    final dir = Directory(panelDir(panelId));
    return dir.existsSync() && File(panelMetaPath(panelId)).existsSync();
  }

  /// 列出所有面板元数据（按更新时间倒序）。
  List<ThemePanelMeta> listPanels() {
    final root = Directory(_panelsRoot);
    if (!root.existsSync()) return [];

    final result = <ThemePanelMeta>[];
    for (final entity in root.listSync()) {
      if (entity is! Directory) continue;
      final metaFile = File(p.join(entity.path, 'meta.json'));
      if (!metaFile.existsSync()) continue;
      try {
        final json = jsonDecode(metaFile.readAsStringSync()) as Map<String, dynamic>;
        result.add(ThemePanelMeta.fromJson(json));
      } catch (e) {
        debugPrint('[ThemePanelManager] ⚠ 解析 meta.json 失败: ${entity.path} $e');
      }
    }
    result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return result;
  }

  /// 创建新面板（含草稿起步值；实例在 [ensureInstance] 时分配）。
  ThemePanelData createPanel({String name = '未命名面板', ThemeDraft? seedDraft}) {
    final id = _newPanelId();
    final dir = Directory(panelDir(id));
    dir.createSync(recursive: true);

    final draft = seedDraft ??
        ThemeDraft(
          id: sanitizeThemeId(name),
          name: name,
        );
    final meta = ThemePanelMeta(id: id, name: name, selectedDraftId: draft.id);

    _writePanelFiles(dir, meta, draft);
    debugPrint('[ThemePanelManager] ✅ 创建面板: $id "$name" (草稿 ${draft.id})');
    return ThemePanelData(meta: meta, draft: draft);
  }

  /// 加载面板完整数据（meta + 草稿；草稿缺失 → null）。
  ThemePanelData? loadPanel(String panelId) {
    final dir = Directory(panelDir(panelId));
    if (!dir.existsSync()) return null;

    final metaFile = File(panelMetaPath(panelId));
    if (!metaFile.existsSync()) return null;

    try {
      final meta =
          ThemePanelMeta.fromJson(jsonDecode(metaFile.readAsStringSync()) as Map<String, dynamic>);
      ThemeDraft? draft;
      final draftFile = File(panelDraftPath(panelId));
      if (draftFile.existsSync()) {
        try {
          draft = ThemeDraft.fromJson(
              jsonDecode(draftFile.readAsStringSync()) as Map<String, dynamic>);
        } catch (e) {
          debugPrint('[ThemePanelManager] ⚠ 解析草稿失败: $panelId $e');
        }
      }
      return ThemePanelData(meta: meta, draft: draft);
    } catch (e) {
      debugPrint('[ThemePanelManager] ❌ 加载面板失败: $panelId $e');
      return null;
    }
  }

  /// 保存面板（更新 meta：name/selectedDraftId/updatedAt + 草稿内容）。
  ///
  /// [draft] 为 null 时只更新 meta 不重写草稿文件。
  void savePanel(String panelId, {ThemeDraft? draft, String? name}) {
    final dir = Directory(panelDir(panelId));
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final data = loadPanel(panelId);
    final meta = data?.meta ?? ThemePanelMeta(id: panelId, name: name ?? '未命名面板');
    if (name != null && name.isNotEmpty) meta.name = name;
    if (draft != null) meta.selectedDraftId = draft.id;
    meta.updatedAt = DateTime.now();

    _writePanelFiles(dir, meta, draft ?? data?.draft);
    debugPrint('[ThemePanelManager] 💾 保存面板: $panelId "${meta.name}"');
  }

  /// 删除面板（递归删除整个面板目录 = 实例 + 会话一并清理）。
  void deletePanel(String panelId) {
    final dir = Directory(panelDir(panelId));
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
      debugPrint('[ThemePanelManager] 🗑 删除面板: $panelId');
    }
  }

  /// 重命名面板（只改名字，不改 id，不丢草稿/会话）。
  void renamePanel(String panelId, String newName) {
    final name = newName.trim();
    if (name.isEmpty) return;
    savePanel(panelId, name: name);
    // 同步实例名（实例名默认取面板名；改名不丢会话、不动 id）
    final meta = _readMetaFile(panelId);
    final iid = meta?.instanceId;
    if (iid != null && iid.isNotEmpty) {
      final inst = loadInstance(panelId, iid);
      if (inst != null) renameInstance(panelId, iid, name);
    }
  }

  // ═══════ 实例（一面板一实例） ═══════

  /// 读取面板 meta.json（轻量）。
  ThemePanelMeta? _readMetaFile(String panelId) {
    final metaFile = File(panelMetaPath(panelId));
    if (!metaFile.existsSync()) return null;
    try {
      return ThemePanelMeta.fromJson(
          jsonDecode(metaFile.readAsStringSync()) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('[ThemePanelManager] ⚠ 解析 meta.json 失败: $panelId $e');
      return null;
    }
  }

  /// 读取实例元数据（不存在 → null）。
  ThemeInstanceMeta? loadInstance(String panelId, String instanceId) {
    final file = File(instanceMetaPath(panelId, instanceId));
    if (!file.existsSync()) return null;
    try {
      return ThemeInstanceMeta.fromJson(
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('[ThemePanelManager] ⚠ 解析实例 meta 失败: $panelId/$instanceId $e');
      return null;
    }
  }

  /// 读取面板当前实例（轻量；面板尚无实例 → null）。
  ThemeInstanceMeta? tryLoadInstanceOf(String panelId) {
    final meta = _readMetaFile(panelId);
    final iid = meta?.instanceId;
    if (iid == null || iid.isEmpty) return null;
    return loadInstance(panelId, iid);
  }

  /// 确保面板有且只有一个实例（面板 ↔ 实例 1:1，幂等）。
  ///
  /// 实例 ID 固定不可变，且 == 主题 ID：未导出时由面板草稿 id 派生
  /// （草稿缺失回退面板名派生）；已有实例时直接复用并做对齐。
  /// 老面板（meta 无 instanceId）首次加载自动创建实例。
  ThemeInstanceMeta ensureInstance(String panelId) {
    var meta = _readMetaFile(panelId);
    if (meta == null) {
      // 面板 meta 缺失（异常路径）：自愈重建最小 meta，避免实例锚点丢失
      meta = ThemePanelMeta(id: panelId, name: '未命名面板');
      final dir = Directory(panelDir(panelId));
      dir.createSync(recursive: true);
      File(panelMetaPath(panelId))
          .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(meta.toJson()));
      debugPrint('[ThemePanelManager] ⚠ 面板 meta 缺失，自愈重建: $panelId');
    }

    // 主题 ID = 面板已绑定 themeId/instanceId；均无 → 用草稿 id / 面板名派生。
    final themeId = meta.themeId ??
        meta.instanceId ??
        _draftIdOf(panelId) ??
        sanitizeThemeId(meta.name);
    return _alignInstanceToThemeId(panelId, themeId);
  }

  /// 将面板的实例 id 对齐到指定主题 ID（两者必须相同）。
  ///
  /// 兼容旧数据：早期版本可能生成了独立的 `instance_xxx` 实例 id。
  /// 本方法会把旧实例目录/会话迁移到主题 ID 目录，并更新 meta 中的
  /// instanceId/themeId，保证后续加载按同一 id 找到历史和主题。
  ThemeInstanceMeta _alignInstanceToThemeId(String panelId, String themeId) {
    final meta = _readMetaFile(panelId) ?? ThemePanelMeta(id: panelId, name: '未命名面板');
    if (themeId.isEmpty) {
      return _alignInstanceToThemeId(panelId, sanitizeThemeId(meta.name));
    }

    final oldIid = meta.instanceId;
    if (oldIid != null && oldIid.isNotEmpty && oldIid != themeId) {
      final oldDir = Directory(instanceDir(panelId, oldIid));
      final newDir = Directory(instanceDir(panelId, themeId));
      if (oldDir.existsSync()) {
        if (!newDir.existsSync()) {
          oldDir.renameSync(newDir.path);
          debugPrint('[ThemePanelManager] 🔀 实例目录对齐主题 ID: $oldIid → $themeId');
        } else {
          // 目标目录已存在（例如已经按主题 id 建过实例）：保留目标，
          // 把旧目录中独有的会话/meta 合并过去后清理旧目录。
          _mergeInstanceDir(panelId, oldDir, newDir, oldIid, themeId);
        }
      }
      // 修正实例 meta 与会话文件内的 id 双向绑定。
      _patchInstanceMetaId(panelId, themeId, themeId);
      _patchSessionInstanceId(panelId, themeId, themeId);
    }

    // 回写 meta：主题 ID 与实例 ID 始终一致。
    _writeMetaField(panelId, 'themeId', themeId);
    _writeMetaField(panelId, 'instanceId', themeId);

    var instance = loadInstance(panelId, themeId);
    if (instance == null) {
      final dir = Directory(instanceDir(panelId, themeId));
      dir.createSync(recursive: true);
      instance = ThemeInstanceMeta(id: themeId, name: meta.name, panelId: panelId);
      File(instanceMetaPath(panelId, themeId))
          .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(instance.toJson()));
      debugPrint('[ThemePanelManager] 🆕 创建实例: $themeId (panel=$panelId, name=${instance.name})');
    }

    // 旧单例 ThemeChatStore 历史 → 迁入实例会话（一次性）。
    _migrateLegacyChatToInstance(panelId, themeId);
    return instance;
  }

  /// 合并旧实例目录到新实例目录：只搬移新目录缺失的文件。
  void _mergeInstanceDir(String panelId, Directory oldDir, Directory newDir,
      String oldIid, String newIid) {
    try {
      newDir.createSync(recursive: true);
      final oldSessionFile = File(instanceSessionsPath(panelId, oldIid));
      final newSessionFile = File(instanceSessionsPath(panelId, newIid));
      if (oldSessionFile.existsSync() && !newSessionFile.existsSync()) {
        oldSessionFile.renameSync(newSessionFile.path);
      }
      final oldMetaFile = File(instanceMetaPath(panelId, oldIid));
      final newMetaFile = File(instanceMetaPath(panelId, newIid));
      if (oldMetaFile.existsSync() && !newMetaFile.existsSync()) {
        oldMetaFile.renameSync(newMetaFile.path);
      }
      oldDir.deleteSync(recursive: true);
      debugPrint('[ThemePanelManager] 🔀 合并旧实例目录: $oldIid → $newIid');
    } catch (e) {
      debugPrint('[ThemePanelManager] ⚠ 合并实例目录失败: $oldIid → $newIid $e');
    }
  }

  /// 修正实例 meta.json 内的 id 字段。
  void _patchInstanceMetaId(String panelId, String instanceId, String newId) {
    try {
      final file = File(instanceMetaPath(panelId, instanceId));
      if (!file.existsSync()) return;
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      json['id'] = newId;
      file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(json));
    } catch (e) {
      debugPrint('[ThemePanelManager] ⚠ 修正实例 meta id 失败: $panelId/$instanceId $e');
    }
  }

  /// 修正实例会话文件内的 instanceId 双向绑定字段。
  void _patchSessionInstanceId(String panelId, String instanceId, String newId) {
    try {
      final file = File(instanceSessionsPath(panelId, instanceId));
      if (!file.existsSync()) return;
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      json['instanceId'] = newId;
      file.writeAsStringSync(jsonEncode(json));
    } catch (e) {
      debugPrint('[ThemePanelManager] ⚠ 修正会话 instanceId 失败: $panelId/$instanceId $e');
    }
  }

  /// 重命名实例（id 永不改；重命名不丢会话）。
  void renameInstance(String panelId, String instanceId, String newName) {
    final instance = loadInstance(panelId, instanceId);
    if (instance == null) return;
    final name = newName.trim();
    if (name.isEmpty || name == instance.name) return;
    instance.name = name;
    instance.updatedAt = DateTime.now();
    File(instanceMetaPath(panelId, instanceId))
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(instance.toJson()));
    debugPrint('[ThemePanelManager] ✏️ 重命名实例: $instanceId → "$name" (id 不变)');
  }

  /// 列出全部实例（跨面板平铺，含所属面板名；左栏「实例」视图用）。
  List<ThemeInstanceRef> listInstances() {
    final result = <ThemeInstanceRef>[];
    for (final panel in listPanels()) {
      final instance = tryLoadInstanceOf(panel.id);
      if (instance != null) {
        result.add(ThemeInstanceRef(instance: instance, panelName: panel.name));
      }
    }
    return result;
  }

  /// 面板当前实例会话的消息数（列表徽标用；无实例/无会话 → 0）。
  int sessionMessageCountOf(String panelId) {
    final instance = tryLoadInstanceOf(panelId);
    if (instance == null) return 0;
    final file = File(instanceSessionsPath(panelId, instance.id));
    if (!file.existsSync()) return 0;
    try {
      final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      return (data['agentSession'] as List<dynamic>?)?.length ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// 绑定主题 ID（导出时调用）：主题 ID 即实例 ID，同步对齐实例。
  ///
  /// 修改主题 ID 时同步迁移实例目录/会话，确保二者永远是同一个 id，
  /// 避免会话与主题身份分叉。
  void bindThemeId(String panelId, String themeId) {
    if (themeId.isEmpty) return;
    _alignInstanceToThemeId(panelId, themeId);
    debugPrint('[ThemePanelManager] 🔗 绑定面板 → 主题/实例: $panelId → $themeId');
  }

  /// 读取面板草稿的 id（草稿缺失 → null）。
  String? _draftIdOf(String panelId) {
    final draftFile = File(panelDraftPath(panelId));
    if (!draftFile.existsSync()) return null;
    try {
      final json = jsonDecode(draftFile.readAsStringSync()) as Map<String, dynamic>;
      final id = json['id'] as String?;
      return (id == null || id.isEmpty) ? null : id;
    } catch (_) {
      return null;
    }
  }

  /// 写入 meta.json 的单个字段（独立写回，不动草稿内容）。
  void _writeMetaField(String panelId, String key, String value) {
    final metaFile = File(panelMetaPath(panelId));
    if (!metaFile.existsSync()) return;
    try {
      final json = jsonDecode(metaFile.readAsStringSync()) as Map<String, dynamic>;
      json[key] = value;
      metaFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(json));
    } catch (e) {
      debugPrint('[ThemePanelManager] ⚠ 写回 meta 字段失败: $panelId $key $e');
    }
  }

  void _writePanelFiles(Directory dir, ThemePanelMeta meta, ThemeDraft? draft) {
    File(panelMetaPath(meta.id)).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(meta.toJson()),
    );
    if (draft != null) {
      File(panelDraftPath(meta.id)).writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(draft.toJson()),
        flush: true,
      );
    }
  }

  // ═══════ 旧数据迁移 ═══════

  /// 一次性迁移老数据 → 面板/实例/会话模型。幂等：迁移后写标记文件，
  /// 已迁移过的环境直接跳过，绝不重复建面板。
  void migrateLegacyIfNeeded() {
    try {
      if (File(_legacyMarkerPath).existsSync()) {
        // 已迁移：仅兜底处理残留旧聊天（老版升级中断的极端情况）
        _migrateLegacyChatIntoFirstPanel();
        return;
      }

      // 老版草稿 → 面板（仅当尚无任何面板时执行，避免重复转换）
      if (listPanels().isEmpty) {
        _convertLegacyDraftsToPanels();
      }

      _migrateLegacyChatIntoFirstPanel();
      Directory(_workspaceRoot).createSync(recursive: true);
      File(_legacyMarkerPath).writeAsStringSync(
        'migrated at ${DateTime.now().toIso8601String()}\n',
      );
      debugPrint('[ThemePanelManager] 📦 旧数据迁移完成 (marker=$_legacyMarkerPath)');
    } catch (e) {
      debugPrint('[ThemePanelManager] ⚠ 旧数据迁移失败: $e');
    }
  }

  /// 老版 `drafts/*.json` 每个草稿 → 一个面板（草稿 id 作实例/主题 id）。
  void _convertLegacyDraftsToPanels() {
    final dir = Directory(_legacyDraftsRoot);
    if (!dir.existsSync()) return;
    final drafts = <ThemeDraft>[];
    for (final f in dir.listSync().whereType<File>()) {
      if (!f.path.endsWith('.json')) continue;
      try {
        drafts.add(ThemeDraft.fromJson(
            jsonDecode(f.readAsStringSync()) as Map<String, dynamic>));
      } catch (e) {
        debugPrint('[ThemePanelManager] ⚠ 跳过损坏草稿 ${f.path}: $e');
      }
    }
    if (drafts.isEmpty) return;

    drafts.sort((a, b) => a.id.compareTo(b.id));
    for (final d in drafts) {
      final data = createPanel(name: d.name, seedDraft: d);
      ensureInstance(data.meta.id); // 立即分配实例（id == 草稿 id）
    }
    debugPrint('[ThemePanelManager] 📦 老草稿 → 面板: ${drafts.length} 个');
  }

  /// 老版单例聊天历史 → 首个面板的实例会话（补写双向字段 + 草稿快照），
  /// 完成后把 chat.json 改名 `.migrated` 防重复迁移。
  void _migrateLegacyChatIntoFirstPanel() {
    final chatFile = File(_legacyChatFile);
    if (!chatFile.existsSync()) return;

    final panels = listPanels();
    if (panels.isEmpty) {
      // 无面板可承载 → 保留文件，等面板创建后再迁（不删数据）
      return;
    }
    final panel = panels.first;
    final instance = tryLoadInstanceOf(panel.id);
    if (instance == null) {
      ensureInstance(panel.id);
      _migrateLegacyChatIntoFirstPanel();
      return;
    }
    _migrateLegacyChatToInstance(panel.id, instance.id);
  }

  /// 将老版 chat.json 内容迁入指定实例的会话文件（一次性）。
  void _migrateLegacyChatToInstance(String panelId, String instanceId) {
    final chatFile = File(_legacyChatFile);
    if (!chatFile.existsSync()) return;
    try {
      final target = File(instanceSessionsPath(panelId, instanceId));
      if (target.existsSync()) {
        // 实例会话已存在：旧文件纯属孤儿，改名归档避免重复迁移
        _archiveLegacyChat(chatFile);
        return;
      }
      Directory(target.parent.path).createSync(recursive: true);

      List<Map<String, dynamic>> rounds;
      try {
        final raw = jsonDecode(chatFile.readAsStringSync());
        rounds = (raw as List<dynamic>)
            .whereType<Map<String, dynamic>>()
            .toList();
      } catch (_) {
        rounds = [];
      }

      // UI 消息：user → user，assistant → ai
      final uiMessages = rounds.map((m) {
        final role = m['role'] == 'assistant' ? 'ai' : 'user';
        return {
          'role': role,
          'text': m['content'] as String? ?? '',
        };
      }).toList();

      // 草稿快照：当前面板草稿（断点续做时恢复 UI 状态）
      final draft = loadPanel(panelId)?.draft;

      target.writeAsStringSync(jsonEncode({
        'panelId': panelId,
        'instanceId': instanceId,
        'updatedAt': DateTime.now().toIso8601String(),
        'agentSession': rounds,
        'uiMessages': uiMessages,
        if (draft != null) 'draftSnapshot': draft.toJson(),
      }));
      _archiveLegacyChat(chatFile);
      debugPrint('[ThemePanelManager] 📦 迁移旧聊天 → 实例会话: $panelId → $instanceId '
          '(${rounds.length} 条)');
    } catch (e) {
      debugPrint('[ThemePanelManager] ⚠ 迁移旧聊天失败: $e');
    }
  }

  /// 把 chat.json 归档为 `.migrated`（防重复迁移，不删用户数据）。
  void _archiveLegacyChat(File chatFile) {
    try {
      final archived = File('${chatFile.path}.migrated');
      if (!archived.existsSync()) {
        chatFile.renameSync(archived.path);
      } else {
        chatFile.deleteSync();
      }
    } catch (e) {
      debugPrint('[ThemePanelManager] ⚠ 归档旧聊天失败: $e');
    }
  }
}
