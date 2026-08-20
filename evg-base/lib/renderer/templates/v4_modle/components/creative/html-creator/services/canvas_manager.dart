/// 画布管理器 —— 创建、加载、列出、删除 HTML 创作画布。
///
/// 画布存储在 `.greenix/workspaces/html-creator/canvases/{canvasId}/` 下，
/// 每个画布包含 meta.json + index.html + style.css + script.js。
library canvas_manager;

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:evergreen_base/core/utils/greenix_path.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/creative/html-creator/models/html_project.dart';

/// 画布元数据（轻量，不含 HTML/CSS/JS 内容）。
class CanvasMeta {
  final String id;
  String name;
  final DateTime createdAt;
  DateTime updatedAt;

  /// 与该画布绑定的插件 ID（首次导出时确定，之后手动/AI 导出均复用，
  /// 避免同一画布多次导出生成多个插件）。null = 尚未导出过。
  String? pluginId;

  /// 侧边栏导航分组（如「自定义」「工具」「学习」）。
  /// 重新导出时写入 manifest 的 nav.sidebar.section。
  String navSection;

  /// 画布绑定的数据源名（null = 未绑定）。
  ///
  /// 随画布持久化：切板/重启后自动恢复，AI 会话的「当前绑定的数据源」
  /// 与数据面板选中态均以它为锚（绑定随板走，T1）。
  String? selectedDataSource;

  /// 画板绑定的实例 ID（画板 ↔ 实例 1:1 锚点，I1）。
  ///
  /// 实例在画板创作之处固定分配、id 不可变（名字可改）；会话文件
  /// 按实例隔离并双向绑定（session.boardId == 画板 id &&
  /// session.instanceId == 实例 id 才承认，孤儿会话不恢复）。
  /// null = 老画板尚未分配实例（首次加载时自动创建，见 [CanvasManager.ensureInstance]）。
  String? instanceId;

  CanvasMeta({
    required this.id,
    required this.name,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.pluginId,
    this.navSection = '自定义',
    this.selectedDataSource,
    this.instanceId,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory CanvasMeta.fromJson(Map<String, dynamic> json) => CanvasMeta(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '未命名画布',
        createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt'] as String) : null,
        updatedAt: json['updatedAt'] != null ? DateTime.tryParse(json['updatedAt'] as String) : null,
        pluginId: json['pluginId'] as String?,
        navSection: json['navSection'] as String? ?? '自定义',
        selectedDataSource: json['selectedDataSource'] as String?,
        instanceId: json['instanceId'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        if (pluginId != null) 'pluginId': pluginId,
        'navSection': navSection,
        if (selectedDataSource != null) 'selectedDataSource': selectedDataSource,
        if (instanceId != null) 'instanceId': instanceId,
      };
}

/// 实例元数据 —— 一会话一份历史记忆的载体（I1）。
///
/// 与 scraper 的会话模型对齐：实例 id 在画板创作之处固定分配、**不可变**；
/// 实例名可自定义重命名（重命名不丢会话、不动 id）。每个实例独占一份
/// 会话文件（消息 + UI 快照），会话文件内双向绑定 boardId + instanceId，
/// 加载时校验一致，孤儿（不匹配）不承认、可清理。
class InstanceMeta {
  /// 实例 ID（固定不可变；重命名只改 [name]）。
  final String id;

  /// 实例名（可自定义重命名；默认取画板名）。
  String name;

  /// 所属画板 ID（画板 ↔ 实例 1:1 锚点）。
  final String boardId;

  final DateTime createdAt;
  DateTime updatedAt;

  InstanceMeta({
    required this.id,
    required this.name,
    required this.boardId,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory InstanceMeta.fromJson(Map<String, dynamic> json) => InstanceMeta(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '未命名实例',
        boardId: json['boardId'] as String? ?? '',
        createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt'] as String) : null,
        updatedAt: json['updatedAt'] != null ? DateTime.tryParse(json['updatedAt'] as String) : null,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'boardId': boardId,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };
}

/// 实例 + 所属画板名的轻量组合（左侧栏「实例」视图平铺用）。
class InstanceRef {
  final InstanceMeta instance;
  final String boardName;
  const InstanceRef({required this.instance, required this.boardName});
}

/// 画布完整数据（含 HTML/CSS/JS 内容）。
class CanvasData {
  final CanvasMeta meta;
  final String htmlContent;
  final String cssContent;
  final String jsContent;

  const CanvasData({
    required this.meta,
    required this.htmlContent,
    this.cssContent = '',
    this.jsContent = '',
  });

  /// 转换为 HtmlProject 用于导出。
  HtmlProject toProject() => HtmlProject(
        pluginId: meta.pluginId ?? _sanitizeId(meta.name),
        pluginName: meta.name,
        htmlContent: htmlContent,
      );
}

/// 画布目录根。
String get _canvasRoot => '${greenixWorkspaceDir('html-creator')}/canvases';

/// 获取画布目录。
String _canvasDir(String canvasId) => p.join(_canvasRoot, canvasId);

/// 画布会话文件路径（并入画布目录，与画布同生命周期）。
///
/// ⚠️ I1 起为**旧布局**：会话已按实例隔离到
/// `canvases/{canvasId}/instances/{instanceId}/session.json`（见
/// [instanceSessionsPath]）。本函数仅用于老数据迁移识别旧文件
/// （ensureInstance 时一次性迁入实例目录后删除）。
String canvasSessionsPath(String canvasId) => p.join(_canvasDir(canvasId), 'session.json');

/// 实例目录（`canvases/{boardId}/instances/{instanceId}/`）。
String instanceDir(String boardId, String instanceId) =>
    p.join(_canvasDir(boardId), 'instances', instanceId);

/// 实例 meta 文件路径。
String instanceMetaPath(String boardId, String instanceId) =>
    p.join(instanceDir(boardId, instanceId), 'meta.json');

/// 实例会话文件路径 —— 一会话一份历史记忆（I1）。
///
/// 会话按实例隔离（消息 + UI 快照），随画板目录生命周期：
/// 删除画布 = 删除整个 canvas 目录 = 实例会话一并清理。
/// HtmlAiService 通过注入的 [resolveSessionsPath] 回调使用本约定。
String instanceSessionsPath(String boardId, String instanceId) =>
    p.join(instanceDir(boardId, instanceId), 'session.json');

/// 生成唯一画布 ID。
String _newCanvasId() => 'canvas_${DateTime.now().millisecondsSinceEpoch}_${_random4()}';

/// 生成唯一实例 ID（创作之处固定，永不改变）。
String _newInstanceId() => 'instance_${DateTime.now().millisecondsSinceEpoch}_${_random4()}';
String _random4() => (DateTime.now().microsecondsSinceEpoch % 10000).toString().padLeft(4, '0');

/// 将名称转为安全的 plugin ID（小写+连字符）。
String _sanitizeId(String name) {
  return name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff\-]'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '')
      .isEmpty
      ? 'my-plugin'
      : name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff\-]'), '-').replaceAll(RegExp(r'-+'), '-').replaceAll(RegExp(r'^-|-$'), '');
}

class CanvasManager {
  /// 画布是否存在（目录 + meta.json 均在场）。
  bool hasCanvas(String canvasId) {
    final dir = Directory(_canvasDir(canvasId));
    return dir.existsSync() && File(p.join(dir.path, 'meta.json')).existsSync();
  }

  /// 列出所有画布元数据（按更新时间倒序）。
  List<CanvasMeta> listCanvases() {
    final root = Directory(_canvasRoot);
    if (!root.existsSync()) return [];

    final result = <CanvasMeta>[];
    for (final entity in root.listSync()) {
      if (entity is! Directory) continue;
      final metaFile = File(p.join(entity.path, 'meta.json'));
      if (!metaFile.existsSync()) continue;
      try {
        final json = jsonDecode(metaFile.readAsStringSync()) as Map<String, dynamic>;
        result.add(CanvasMeta.fromJson(json));
      } catch (e) {
        debugPrint('[CanvasManager] ⚠ 解析 meta.json 失败: ${entity.path} $e');
      }
    }
    result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return result;
  }

  /// 创建新画布。
  CanvasData createCanvas({
    String name = '未命名画布',
    String htmlContent = '',
    String cssContent = '',
    String jsContent = '',
    String navSection = '自定义',
  }) {
    final id = _newCanvasId();
    final dir = Directory(_canvasDir(id));
    dir.createSync(recursive: true);

    final meta = CanvasMeta(id: id, name: name, navSection: navSection);

    _writeCanvasFiles(dir, meta, htmlContent, cssContent, jsContent);
    debugPrint('[CanvasManager] ✅ 创建画布: $id "$name"');

    return CanvasData(meta: meta, htmlContent: htmlContent, cssContent: cssContent, jsContent: jsContent);
  }

  /// 加载画布完整数据。
  CanvasData? loadCanvas(String canvasId) {
    final dir = Directory(_canvasDir(canvasId));
    if (!dir.existsSync()) return null;

    final metaFile = File(p.join(dir.path, 'meta.json'));
    if (!metaFile.existsSync()) return null;

    try {
      final metaJson = jsonDecode(metaFile.readAsStringSync()) as Map<String, dynamic>;
      final meta = CanvasMeta.fromJson(metaJson);

      final htmlFile = File(p.join(dir.path, 'index.html'));
      final cssFile = File(p.join(dir.path, 'style.css'));
      final jsFile = File(p.join(dir.path, 'script.js'));

      return CanvasData(
        meta: meta,
        htmlContent: htmlFile.existsSync() ? htmlFile.readAsStringSync() : '',
        cssContent: cssFile.existsSync() ? cssFile.readAsStringSync() : '',
        jsContent: jsFile.existsSync() ? jsFile.readAsStringSync() : '',
      );
    } catch (e) {
      debugPrint('[CanvasManager] ❌ 加载画布失败: $canvasId $e');
      return null;
    }
  }

  /// 保存画布数据（更新文件）。
  void saveCanvas(String canvasId, {
    String? name,
    String? htmlContent,
    String? cssContent,
    String? jsContent,
    String? navSection,
  }) {
    final dir = Directory(_canvasDir(canvasId));
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final data = loadCanvas(canvasId);
    final meta = data?.meta ?? CanvasMeta(id: canvasId, name: name ?? '未命名画布');

    if (name != null) meta.name = name;
    if (navSection != null && navSection.isNotEmpty) meta.navSection = navSection;
    meta.updatedAt = DateTime.now();

    _writeCanvasFiles(
      dir,
      meta,
      htmlContent ?? data?.htmlContent ?? '',
      cssContent ?? data?.cssContent ?? '',
      jsContent ?? data?.jsContent ?? '',
    );
    debugPrint('[CanvasManager] 💾 保存画布: $canvasId "${meta.name}"');
  }

  /// 删除画布。
  void deleteCanvas(String canvasId) {
    final dir = Directory(_canvasDir(canvasId));
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
      debugPrint('[CanvasManager] 🗑 删除画布: $canvasId');
    }
  }

  /// 重命名画布。
  void renameCanvas(String canvasId, String newName) {
    saveCanvas(canvasId, name: newName);
  }

  /// 绑定画布到插件 ID（首次导出时调用，之后导出均复用该 ID）。
  void bindPluginId(String canvasId, String pluginId) {
    final dir = Directory(_canvasDir(canvasId));
    if (!dir.existsSync()) return;
    final metaFile = File(p.join(dir.path, 'meta.json'));
    if (!metaFile.existsSync()) return;
    try {
      final json = jsonDecode(metaFile.readAsStringSync()) as Map<String, dynamic>;
      json['pluginId'] = pluginId;
      metaFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(json));
      debugPrint('[CanvasManager] 🔗 绑定画布 → 插件: $canvasId → $pluginId');
    } catch (e) {
      debugPrint('[CanvasManager] ⚠ 绑定插件 ID 失败: $canvasId $e');
    }
  }

  /// 绑定画布到数据源名（写入 meta.json 的 selectedDataSource）。
  ///
  /// 独立于 saveCanvas：数据面板点选绑定源时只更新绑定字段，
  /// 不触碰编辑器内容（避免触发大文件重写）。sourceName 为 null 解绑。
  void bindDataSource(String canvasId, String? sourceName) {
    final dir = Directory(_canvasDir(canvasId));
    if (!dir.existsSync()) return;
    final metaFile = File(p.join(dir.path, 'meta.json'));
    if (!metaFile.existsSync()) return;
    try {
      final json = jsonDecode(metaFile.readAsStringSync()) as Map<String, dynamic>;
      if (sourceName != null && sourceName.isNotEmpty) {
        json['selectedDataSource'] = sourceName;
      } else {
        json.remove('selectedDataSource');
      }
      metaFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(json));
      debugPrint('[CanvasManager] 🔗 绑定画布 → 数据源: $canvasId → $sourceName');
    } catch (e) {
      debugPrint('[CanvasManager] ⚠ 绑定数据源失败: $canvasId $e');
    }
  }

  // ═══════ I1 · 会话-实例模型 ═══════

  /// 读取画布 meta.json（轻量，不读 HTML/CSS/JS 内容）。
  CanvasMeta? _readMetaFile(String canvasId) {
    final metaFile = File(p.join(_canvasDir(canvasId), 'meta.json'));
    if (!metaFile.existsSync()) return null;
    try {
      return CanvasMeta.fromJson(jsonDecode(metaFile.readAsStringSync()) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('[CanvasManager] ⚠ 解析 meta.json 失败: $canvasId $e');
      return null;
    }
  }

  /// 读取实例元数据（不存在 → null）。
  InstanceMeta? loadInstance(String boardId, String instanceId) {
    final file = File(instanceMetaPath(boardId, instanceId));
    if (!file.existsSync()) return null;
    try {
      return InstanceMeta.fromJson(jsonDecode(file.readAsStringSync()) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('[CanvasManager] ⚠ 解析实例 meta 失败: $boardId/$instanceId $e');
      return null;
    }
  }

  /// 读取画板当前实例（轻量；画板尚无实例 → null）。
  ///
  /// 左侧栏「实例」视图 / 实例索引用；不创建实例（创建走 [ensureInstance]）。
  InstanceMeta? tryLoadInstanceOf(String boardId) {
    final meta = _readMetaFile(boardId);
    final iid = meta?.instanceId;
    if (iid == null || iid.isEmpty) return null;
    return loadInstance(boardId, iid);
  }

  /// 确保画板有且只有一个实例（画板 ↔ 实例 1:1，I1）。
  ///
  /// 幂等：画板已有实例 → 直接返回；没有 → 创建（id 固定不可变、
  /// 名默认取画板名）、回写画布 meta.instanceId 锚点、并把旧布局会话
  /// （T1 的 `canvases/{id}/session.json`）一次性迁入实例目录
  /// （补写 boardId/instanceId 双向字段后删除旧文件）。
  InstanceMeta ensureInstance(String boardId) {
    var meta = _readMetaFile(boardId);
    if (meta == null) {
      // 画板 meta 缺失（异常路径）：自愈重建最小 meta，避免实例锚点丢失
      meta = CanvasMeta(id: boardId, name: '未命名画布');
      final dir = Directory(_canvasDir(boardId));
      dir.createSync(recursive: true);
      File(p.join(dir.path, 'meta.json'))
          .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(meta.toJson()));
      debugPrint('[CanvasManager] ⚠ 画板 meta 缺失，自愈重建: $boardId');
    }

    var instance = meta.instanceId != null ? loadInstance(boardId, meta.instanceId!) : null;
    if (instance == null) {
      final instanceId = _newInstanceId();
      instance = InstanceMeta(
        id: instanceId,
        name: meta.name,
        boardId: boardId,
      );
      final dir = Directory(instanceDir(boardId, instanceId));
      dir.createSync(recursive: true);
      File(instanceMetaPath(boardId, instanceId))
          .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(instance.toJson()));
      // 回写画板 meta.instanceId（画板 ↔ 实例 1:1 锚点，独立写回不动编辑器内容）
      _writeMetaField(boardId, 'instanceId', instanceId);
      // 迁移旧布局会话（T1：canvases/{id}/session.json）→ 实例目录
      _migrateCanvasSessionToInstance(boardId, instanceId);
      debugPrint('[CanvasManager] 🆕 创建实例: $instanceId (board=$boardId, name=${instance.name})');
    }
    return instance;
  }

  /// 重命名实例（id 永不改；重命名不丢会话）。
  void renameInstance(String boardId, String instanceId, String newName) {
    final instance = loadInstance(boardId, instanceId);
    if (instance == null) return;
    final name = newName.trim();
    if (name.isEmpty || name == instance.name) return;
    instance.name = name;
    instance.updatedAt = DateTime.now();
    File(instanceMetaPath(boardId, instanceId))
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(instance.toJson()));
    debugPrint('[CanvasManager] ✏️ 重命名实例: $instanceId → "$name" (id 不变)');
  }

  /// 列出全部实例（跨画板平铺，含所属画板名；左侧栏「实例」视图用）。
  List<InstanceRef> listInstances() {
    final result = <InstanceRef>[];
    for (final board in listCanvases()) {
      final instance = tryLoadInstanceOf(board.id);
      if (instance != null) {
        result.add(InstanceRef(instance: instance, boardName: board.name));
      }
    }
    return result;
  }

  /// 写入 meta.json 的单个字段（独立写回，不动编辑器内容）。
  void _writeMetaField(String canvasId, String key, String value) {
    final metaFile = File(p.join(_canvasDir(canvasId), 'meta.json'));
    if (!metaFile.existsSync()) return;
    try {
      final json = jsonDecode(metaFile.readAsStringSync()) as Map<String, dynamic>;
      json[key] = value;
      metaFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(json));
    } catch (e) {
      debugPrint('[CanvasManager] ⚠ 写回 meta 字段失败: $canvasId $key $e');
    }
  }

  /// 迁移 T1 旧布局会话（`canvases/{id}/session.json`）→ 实例目录。
  ///
  /// 一次性：旧文件存在而实例会话缺失时，读入旧内容补写 boardId/instanceId
  /// 双向绑定字段后写入实例目录，再删除旧文件（避免残留孤儿）。
  void _migrateCanvasSessionToInstance(String boardId, String instanceId) {
    final legacy = File(canvasSessionsPath(boardId));
    if (!legacy.existsSync()) return;
    try {
      final target = File(instanceSessionsPath(boardId, instanceId));
      if (target.existsSync()) {
        // 实例会话已存在：旧文件纯属孤儿，直接删除
        legacy.deleteSync();
        return;
      }
      Directory(target.parent.path).createSync(recursive: true);
      Map<String, dynamic> content;
      try {
        content = jsonDecode(legacy.readAsStringSync()) as Map<String, dynamic>;
      } catch (_) {
        content = <String, dynamic>{};
      }
      content['boardId'] = boardId;
      content['instanceId'] = instanceId;
      target.writeAsStringSync(jsonEncode(content));
      legacy.deleteSync();
      debugPrint('[CanvasManager] 📦 迁移画布会话 → 实例: $boardId → $instanceId');
    } catch (e) {
      debugPrint('[CanvasManager] ⚠ 迁移画布会话失败: $boardId $e');
    }
  }

  void _writeCanvasFiles(Directory dir, CanvasMeta meta, String html, String css, String js) {
    File(p.join(dir.path, 'meta.json')).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(meta.toJson()),
    );
    File(p.join(dir.path, 'index.html')).writeAsStringSync(html);
    File(p.join(dir.path, 'style.css')).writeAsStringSync(css);
    File(p.join(dir.path, 'script.js')).writeAsStringSync(js);
  }
}
