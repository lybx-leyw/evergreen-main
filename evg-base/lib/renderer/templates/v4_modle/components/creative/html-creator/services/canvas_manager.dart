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

  CanvasMeta({
    required this.id,
    required this.name,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.pluginId,
    this.navSection = '自定义',
    this.selectedDataSource,
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
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        if (pluginId != null) 'pluginId': pluginId,
        'navSection': navSection,
        if (selectedDataSource != null) 'selectedDataSource': selectedDataSource,
      };
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
/// 删除画布 = 删除整个 canvas 目录 = 会话一并清理，杜绝孤儿会话文件；
/// 与 AI 会话恢复保持同一路径约定（HtmlAiService 通过注入的回调使用）。
String canvasSessionsPath(String canvasId) => p.join(_canvasDir(canvasId), 'session.json');

/// 生成唯一画布 ID。
String _newCanvasId() => 'canvas_${DateTime.now().millisecondsSinceEpoch}_${_random4()}';
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

  void _writeCanvasFiles(Directory dir, CanvasMeta meta, String html, String css, String js) {
    File(p.join(dir.path, 'meta.json')).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(meta.toJson()),
    );
    File(p.join(dir.path, 'index.html')).writeAsStringSync(html);
    File(p.join(dir.path, 'style.css')).writeAsStringSync(css);
    File(p.join(dir.path, 'script.js')).writeAsStringSync(js);
  }
}
