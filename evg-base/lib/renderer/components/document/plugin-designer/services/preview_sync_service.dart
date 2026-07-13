/// 预览同步服务 —— 编排变更 → manifest.json 写入 → 热加载触发。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/design_document.dart';

/// 预览同步回调：通知上游需要热加载的插件 ID。
typedef PreviewRefreshCallback = void Function(String pluginId);

/// 预览同步服务 —— 将 DesignDocument 编译写入 manifest.json
/// 并通知 UI 刷新预览。
class PreviewSyncService {
  final String _pluginsDir;
  final PreviewRefreshCallback _onRefresh;
  Timer? _debounceTimer;

  PreviewSyncService(this._pluginsDir, this._onRefresh);

  /// 同步设计文档到 manifest.json（带 300ms 防抖）。
  Future<void> sync(DesignDocument doc) async {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () async {
      await _writeManifest(doc);
    });
  }

  /// 立即同步（不防抖）。
  Future<void> syncNow(DesignDocument doc) async {
    _debounceTimer?.cancel();
    await _writeManifest(doc);
  }

  Future<void> _writeManifest(DesignDocument doc) async {
    final manifestPath = p.join(
        _pluginsDir, doc.pluginId, 'module', 'manifest.json');
    final file = File(manifestPath);
    final dir = file.parent;
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final manifest = _compileManifest(doc);
    final json = const JsonEncoder.withIndent('  ').convert(manifest);
    await file.writeAsString(json);

    _onRefresh(doc.pluginId);
  }

  /// 将 DesignDocument 编译为 manifest.json 结构。
  ///
  /// 输出格式符合 manifest V2 schema。
  Map<String, dynamic> _compileManifest(DesignDocument doc) {
    final pages = <Map<String, dynamic>>[];
    for (final designPage in doc.pages) {
      final slots = <String, Map<String, dynamic>>{};
      for (final slot in designPage.slots) {
        slots[slot.id] = {
          if (slot.label.isNotEmpty) 'label': slot.label,
          'region': slot.region.name,
          if (slot.component != null)
            'component': slot.component!.toJson(),
        };
      }
      pages.add({
        'id': designPage.id,
        'label': designPage.label,
        'layout': {
          'type': designPage.layoutPreset.name,
          'slots': slots,
        },
      });
    }

    return {
      'schemaVersion': '2.0',
      'id': doc.pluginId,
      'name': doc.pluginName,
      if (doc.icon != null) 'icon': doc.icon,
      if (doc.description != null) 'description': doc.description,
      if (doc.route != null) 'route': doc.route,
      'pages': pages,
    };
  }

  void dispose() => _debounceTimer?.cancel();
}
