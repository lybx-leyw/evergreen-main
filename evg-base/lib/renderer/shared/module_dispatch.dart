/// UI 范式调度器（V2）——根据 renderMode + ModuleDescriptor 内容返回对应视图。
///
/// V2: 不再使用 `descriptor.ui` 字段。改为：
/// - `renderMode == "html"` → [HtmlRenderView]（WebView 内嵌 HTML）
/// - 有 pages → [CompositeView]（多页面 + Slot 调度）
/// - 有 workspace → [EditorView]
/// - 其他 → [DefaultView]（兜底，不崩溃）
///
/// 公开类：[ModuleDispatch]
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'default_view.dart';
import 'editor_view.dart';
import 'composite_view.dart';
import 'html_render_view.dart';
import 'chat_controller_view.dart';

/// UI 范式调度器——按模块内容自动选择视图。
/// 未知配置静默回退到 [DefaultView]。
class ModuleDispatch extends StatelessWidget {
  final ModuleDescriptor descriptor;
  final String? workingDirectory;
  final String renderMode;

  const ModuleDispatch({
    super.key,
    required this.descriptor,
    this.workingDirectory,
    this.renderMode = 'dart',
  });

  @override
  Widget build(BuildContext context) {
    // V2: HTML 模式 → WebView 内嵌渲染
    if (renderMode == 'html') {
      debugPrint('[ModuleDispatch] ${descriptor.id}: HTML → HtmlRenderView');
      return HtmlRenderView(moduleId: descriptor.id);
    }

    // V2: AI 助手模块 → 全屏 ChatControllerView（含抽屉/全局记忆/Skill/工作区）
    if (descriptor.id == 'ai-assistant') {
      debugPrint('[ModuleDispatch] ${descriptor.id}: chat → ChatControllerView');
      return ChatControllerView(descriptor: descriptor);
    }

    // V2: 有 pages → CompositeView（每页独立 layout + slots）
    if (descriptor.pages.isNotEmpty) {
      debugPrint('[ModuleDispatch] ${descriptor.id}: ${descriptor.pages.length} pages → CompositeView');
      return CompositeView(
        descriptor: descriptor,
        workingDirectory: workingDirectory,
      );
    }

    // V2: 有 workspace 配置 → EditorView
    if (descriptor.workspace != null && descriptor.workspace!.enabled) {
      debugPrint('[ModuleDispatch] ${descriptor.id}: workspace → EditorView');
      return EditorView(descriptor: descriptor);
    }

    // 兜底：通用数据绑定视图
    debugPrint('[ModuleDispatch] ${descriptor.id}: fallback → DefaultView');
    return DefaultView(descriptor: descriptor);
  }
}
