/// Skill 创作面板管理器——「一面板一实例一固定 ID + 一会话一固定历史」。
///
/// 对齐 theme-creator / html-creator 的既有范式：
/// - 工作区：`.greenix/workspaces/skill-creator/panels/{panelId}/instances/{instanceId}/`；
/// - 实例 ID 固定不可变（== 面板 ID，杜绝分叉）；
/// - 会话文件 `session.json` 内双向绑定 `panelId + instanceId`，
///   加载时校验一致，孤儿会话不恢复并清理；
/// - 会话内容 = 规划 agent 消息历史 + UI 消息 + 工作流快照（断点续做）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:evergreen_base/core/utils/greenix_path.dart';

import '../models/skill_creator_models.dart';

// ═══════ 路径 ═══════

/// 工作区根目录。
String skillCreatorRootDir() => greenixWorkspaceDir('skill-creator');

/// 面板目录。
String skillCreatorPanelDir(String panelId) =>
    p.join(skillCreatorRootDir(), 'panels', panelId);

/// 实例目录。
String skillCreatorInstanceDir(String panelId, String instanceId) =>
    p.join(skillCreatorPanelDir(panelId), 'instances', instanceId);

/// 实例 meta 路径。
String skillCreatorInstanceMetaPath(String panelId, String instanceId) =>
    p.join(skillCreatorInstanceDir(panelId, instanceId), 'meta.json');

/// 实例会话路径（一会话一固定历史）。
String skillCreatorSessionPath(String panelId, String instanceId) =>
    p.join(skillCreatorInstanceDir(panelId, instanceId), 'session.json');

/// 面板 meta 路径。
String _panelMetaPath(String panelId) =>
    p.join(skillCreatorPanelDir(panelId), 'meta.json');

// ═══════ SkillCreatorPanelManager ═══════

/// 面板管理器：创建/加载/列出/删除面板 + 实例与会话绑定。
class SkillCreatorPanelManager {
  /// 工作区根目录（可注入便于测试）。
  final String rootDir;

  SkillCreatorPanelManager({String? rootDir})
      : rootDir = rootDir ?? skillCreatorRootDir();

  String _panelDir(String panelId) =>
      rootDir == skillCreatorRootDir()
          ? skillCreatorPanelDir(panelId)
          : p.join(rootDir, 'panels', panelId);

  String _instanceDir(String panelId, String instanceId) =>
      p.join(_panelDir(panelId), 'instances', instanceId);

  String _instanceMetaPath(String panelId, String instanceId) =>
      p.join(_instanceDir(panelId, instanceId), 'meta.json');

  String _sessionPath(String panelId, String instanceId) =>
      p.join(_instanceDir(panelId, instanceId), 'session.json');

  String _metaPath(String panelId) => p.join(_panelDir(panelId), 'meta.json');

  // ── 面板 CRUD ──

  /// 列出全部面板（按更新时间倒序）。
  List<SkillCreatorPanelMeta> listPanels() {
    final dir = Directory(p.join(rootDir, 'panels'));
    if (!dir.existsSync()) return [];
    final metas = <SkillCreatorPanelMeta>[];
    for (final entry in dir.listSync()) {
      if (entry is! Directory) continue;
      final meta = _loadMeta(entry.path.split(Platform.pathSeparator).last);
      if (meta != null) metas.add(meta);
    }
    metas.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return metas;
  }

  /// 创建新面板（工作流初始为 idle；实例在 [ensureInstance] 时分配）。
  SkillCreatorPanelData createPanel({String name = '未命名面板'}) {
    final id = newSkillPanelId();
    final meta = SkillCreatorPanelMeta(id: id, name: name);
    final dir = Directory(_panelDir(id));
    dir.createSync(recursive: true);
    _saveMeta(meta);
    return SkillCreatorPanelData(
      meta: meta,
      workflow: SkillCreatorWorkflow(),
    );
  }

  /// 加载面板（meta + 工作流；无会话则返回空工作流）。
  SkillCreatorPanelData? loadPanel(String panelId) {
    final meta = _loadMeta(panelId);
    if (meta == null) return null;

    var workflow = SkillCreatorWorkflow();
    final iid = meta.instanceId;
    if (iid != null) {
      final session = _loadSession(panelId, iid);
      if (session != null) workflow = session.workflow;
    }
    return SkillCreatorPanelData(meta: meta, workflow: workflow);
  }

  /// 删除面板（连带实例与会话，不留孤儿文件）。
  void deletePanel(String panelId) {
    final dir = Directory(_panelDir(panelId));
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }

  /// 更新面板名（不改 id / 实例）。
  void renamePanel(String panelId, String name) {
    final meta = _loadMeta(panelId);
    if (meta == null) return;
    _saveMeta(SkillCreatorPanelMeta(
      id: meta.id,
      name: name,
      createdAt: meta.createdAt,
      updatedAt: DateTime.now(),
      instanceId: meta.instanceId,
    ));
  }

  // ── 实例绑定 ──

  /// 确保面板已绑定实例（幂等）。
  ///
  /// 实例 ID 固定 == 面板 ID（面板 ↔ 实例 1:1 锚点），不可变。
  /// 老面板（meta 无 instanceId）首次加载自动创建实例。
  SkillCreatorInstanceMeta ensureInstance(String panelId) {
    final meta = _loadMeta(panelId) ??
        SkillCreatorPanelMeta(id: panelId, name: '未命名面板');
    final iid = meta.instanceId ?? panelId;

    var instance = _loadInstance(panelId, iid);
    if (instance == null) {
      instance = SkillCreatorInstanceMeta(
        id: iid,
        name: meta.name,
        panelId: panelId,
      );
      Directory(_instanceDir(panelId, iid)).createSync(recursive: true);
      _saveInstance(instance);
    }

    // 面板 meta 回写 instanceId（老面板迁移）。
    if (meta.instanceId == null) {
      _saveMeta(SkillCreatorPanelMeta(
        id: meta.id,
        name: meta.name,
        createdAt: meta.createdAt,
        updatedAt: DateTime.now(),
        instanceId: iid,
      ));
    }
    return instance;
  }

  /// 加载实例 meta；不存在返回 null。
  SkillCreatorInstanceMeta? loadInstance(String panelId, String instanceId) =>
      _loadInstance(panelId, instanceId);

  // ── 会话持久化（一会话一固定历史） ──

  /// 保存会话到实例文件（消息历史 + UI 消息 + 工作流快照）。
  ///
  /// 每次 AI 回合/阶段切换后自动调用，供断点续做。
  void saveSession(
    String panelId,
    String instanceId, {
    required List<Map<String, dynamic>> agentSession,
    required List<Map<String, dynamic>> uiMessages,
    required SkillCreatorWorkflow workflow,
  }) {
    final file = File(_sessionPath(panelId, instanceId));
    if (!file.parent.existsSync()) file.parent.createSync(recursive: true);
    try {
      file.writeAsStringSync(jsonEncode({
        'panelId': panelId,
        'instanceId': instanceId,
        'updatedAt': DateTime.now().toIso8601String(),
        'agentSession': agentSession,
        'uiMessages': uiMessages,
        'workflow': workflow.toJson(),
      }));
      _touchMeta(panelId);
    } catch (e) {
      debugPrint('[SkillCreator] ⚠ 保存会话失败: $e');
    }
  }

  /// 从实例文件恢复会话。
  ///
  /// 双向绑定校验：文件内 panelId/instanceId 必须与当前面板/实例一致，
  /// 不一致 = 孤儿会话 → 不恢复并清理文件，保证绝不串台。
  /// 返回 null = 无会话或孤儿（此时调用方按新会话处理）。
  SkillCreatorSession? restoreSession(String panelId, String instanceId) {
    try {
      final file = File(_sessionPath(panelId, instanceId));
      if (!file.existsSync()) return null;
      if (file.lengthSync() > 10 * 1024 * 1024) {
        debugPrint('[SkillCreator] ⚠ 会话文件超过 10MiB，忽略恢复');
        return null;
      }

      final data = decodeJsonMap(file.readAsStringSync());
      final fPanel = data['panelId']?.toString();
      final fInstance = data['instanceId']?.toString();
      if (fPanel != panelId || fInstance != instanceId) {
        debugPrint('[SkillCreator] ⚠ 孤儿会话（panelId=$fPanel instanceId=$fInstance '
            '≠ $panelId/$instanceId），不恢复并清理');
        try {
          file.deleteSync();
        } catch (_) {}
        return null;
      }

      return SkillCreatorSession.fromJson(data);
    } catch (e) {
      debugPrint('[SkillCreator] ⚠ 恢复会话失败: $e');
      return null;
    }
  }

  /// 清空会话（重置为全新工作流），保留实例。
  void resetSession(String panelId, String instanceId) {
    final iid = instanceId;
    try {
      final file = File(_sessionPath(panelId, iid));
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
  }

  // ── 内部 ──

  SkillCreatorPanelMeta? _loadMeta(String panelId) {
    try {
      final file = File(_metaPath(panelId));
      if (!file.existsSync()) return null;
      return SkillCreatorPanelMeta.fromJson(decodeJsonMap(file.readAsStringSync()));
    } catch (e) {
      debugPrint('[SkillCreator] ⚠ 解析面板 meta 失败: $panelId $e');
      return null;
    }
  }

  void _saveMeta(SkillCreatorPanelMeta meta) {
    try {
      final file = File(_metaPath(meta.id));
      if (!file.parent.existsSync()) file.parent.createSync(recursive: true);
      file.writeAsStringSync(jsonEncode(meta.toJson()));
    } catch (e) {
      debugPrint('[SkillCreator] ⚠ 保存面板 meta 失败: $e');
    }
  }

  void _touchMeta(String panelId) {
    final meta = _loadMeta(panelId);
    if (meta == null) return;
    _saveMeta(SkillCreatorPanelMeta(
      id: meta.id,
      name: meta.name,
      createdAt: meta.createdAt,
      updatedAt: DateTime.now(),
      instanceId: meta.instanceId,
    ));
  }

  SkillCreatorInstanceMeta? _loadInstance(String panelId, String instanceId) {
    try {
      final file = File(_instanceMetaPath(panelId, instanceId));
      if (!file.existsSync()) return null;
      return SkillCreatorInstanceMeta.fromJson(
          decodeJsonMap(file.readAsStringSync()));
    } catch (e) {
      debugPrint('[SkillCreator] ⚠ 解析实例 meta 失败: $panelId/$instanceId $e');
      return null;
    }
  }

  void _saveInstance(SkillCreatorInstanceMeta meta) {
    try {
      final file = File(_instanceMetaPath(meta.panelId, meta.id));
      if (!file.parent.existsSync()) file.parent.createSync(recursive: true);
      file.writeAsStringSync(jsonEncode(meta.toJson()));
    } catch (e) {
      debugPrint('[SkillCreator] ⚠ 保存实例 meta 失败: $e');
    }
  }

  SkillCreatorSession? _loadSession(String panelId, String instanceId) =>
      restoreSession(panelId, instanceId);
}
