/// UI 范式调度器（V2）——根据 renderMode + ModuleDescriptor 内容返回对应视图。
///
/// V2: 不再使用 `descriptor.ui` 字段。改为：
/// - 有 pages → [CompositeView]（多页面 + Slot 调度）
/// - 有 workspace → [EditorView]
/// - 其他 → [DefaultView]（兜底，不崩溃）
///
/// 公开类：[ModuleDispatch]
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/renderer/templates/template_registry.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/code_editor_slot.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/data/card_list_slot.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/interaction/chat/chat_controller_view.dart';

/// UI 范式调度器——按模块内容自动选择视图。
/// 未知配置静默回退到 [DefaultView]。
class ModuleDispatch extends StatelessWidget {
  final ModuleDescriptor descriptor;
  final String? workingDirectory;
  final String renderMode;
  /// 来自路由的 AI 预填 prompt（AI 笔记按钮跳转带入），仅 ai-assistant 使用。
  final String? initialPrompt;

  const ModuleDispatch({
    super.key,
    required this.descriptor,
    this.workingDirectory,
    this.renderMode = 'dart',
    this.initialPrompt,
  });

  @override
  Widget build(BuildContext context) {
    // V2: AI 助手模块 → 全屏 ChatControllerView（含抽屉/全局记忆/Skill/工作区）
    if (descriptor.id == 'ai-assistant') {
      debugPrint('[ModuleDispatch] ${descriptor.id}: chat → ChatControllerView');
      return ChatControllerView(
        descriptor: descriptor,
        initialPrompt: initialPrompt,
      );
    }

    // V2: 非默认模板（如 classroom-modle）→ 按 manifest `template` 路由，
    // 即使无 pages 也走模板（自定义模板不依赖 pages 结构）。
    if (descriptor.template != 'v4' && descriptor.template.isNotEmpty) {
      debugPrint('[ModuleDispatch] ${descriptor.id}: template="${descriptor.template}" (no-pages modle)');
      return TemplateRegistry.render(
        context,
        descriptor: descriptor,
        workingDirectory: workingDirectory,
      );
    }

    // V2: 有 pages → 按 manifest `template` 路由到对应 modle 渲染器（默认 v4）
    if (descriptor.pages.isNotEmpty) {
      debugPrint('[ModuleDispatch] ${descriptor.id}: ${descriptor.pages.length} pages → template="${descriptor.template}"');
      return TemplateRegistry.render(
        context,
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
