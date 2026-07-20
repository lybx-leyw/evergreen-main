/// 预览同步服务 —— 编排变更 → manifest.json 写入 → 热加载触发。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/models/design_document.dart';
import 'design_to_manifest.dart';

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

    // A-P3 B2：复用 DesignToManifest.compile 单一真相源，
    // 保证写入的 manifest 与导出/真实加载器契约完全一致
    // （含 renderMode/type/ui/version/dependencies/nav/process 等），
    // 避免旧版私有 _compileManifest 残缺导致的"导出成功但运行不可用"。
    final manifest = DesignToManifest.compile(doc);
    final json = const JsonEncoder.withIndent('  ').convert(manifest);
    await file.writeAsString(json);

    _onRefresh(doc.pluginId);
  }

  void dispose() => _debounceTimer?.cancel();
}
