/// 真实 composite 渲染预览框 —— 把设计文档编译为 manifest，
/// 用真实的 [CompositeView] 渲染，达成"所见即所得"。
///
/// 与旧版 mock 卡片预览不同，本组件走与线上完全一致的渲染管线
/// （[SlotDispatch] → 各组件视图），因此预览效果 == 导出后运行效果。
library;

import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/composite_view.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/models/design_document.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/services/design_to_manifest.dart';

/// 真实渲染预览框。
///
/// [document] 为 null 时渲染空态；编译或解析失败时渲染错误卡片，
/// 不向上抛出（保证设计器主视图稳定）。
class CompositePreviewFrame extends StatelessWidget {
  final DesignDocument? document;

  const CompositePreviewFrame({super.key, this.document});

  @override
  Widget build(BuildContext context) {
    final doc = document;
    if (doc == null) {
      return _centeredHint('请先创建或加载设计文档');
    }
    if (doc.pages.isEmpty) {
      return _centeredHint('暂无页面，请在画布中添加页面');
    }

    late final ModuleDescriptor descriptor;
    try {
      final manifest = DesignToManifest.compile(doc);
      descriptor = ModuleDescriptor.fromJson(_sanitize(manifest));
    } catch (e, st) {
      debugPrint('[CompositePreviewFrame] 编译/解析失败: $e\n$st');
      return _errorCard('编译失败', e.toString());
    }

    // 预览态：不挂载真实后端进程（workingDirectory 置空），
    // 组件按需走优雅空态；需要后端的组件在预览中显示空态而非崩溃。
    return CompositeView(descriptor: descriptor);
  }

  /// 预览态净化：剔除未绑定组件的空 Slot，避免 [CompositeView]
  /// 对 `component!` 的空断言崩溃（线上 manifest 的 slot 必带 component，
  /// 但设计过程中允许存在空 Slot）。
  Map<String, dynamic> _sanitize(Map<String, dynamic> manifest) {
    final pages = (manifest['pages'] as List?)?.map((p) {
      final page = Map<String, dynamic>.from(p as Map);
      final layout = Map<String, dynamic>.from(page['layout'] as Map);
      final slots = Map<String, dynamic>.from(layout['slots'] as Map);
      slots.removeWhere((_, v) => (v as Map)['component'] == null);
      layout['slots'] = slots;
      page['layout'] = layout;
      return page;
    }).toList();
    return <String, dynamic>{...manifest, 'pages': pages};
  }

  Widget _centeredHint(String message) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.web_asset_outlined, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(message, style: const TextStyle(color: Colors.grey)),
          ],
        ),
      );

  Widget _errorCard(String title, String detail) => Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 36, color: Colors.red),
              const SizedBox(height: 8),
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, color: Colors.red)),
              const SizedBox(height: 4),
              Text(detail,
                  style: const TextStyle(fontSize: 11, color: Colors.red),
                  textAlign: TextAlign.center,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      );
}
