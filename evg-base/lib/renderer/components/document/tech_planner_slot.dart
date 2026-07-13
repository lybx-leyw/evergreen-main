/// tech-planner Slot 组件。
///
/// 按 manifest 的 ComponentDescriptor 配置渲染 TechPlannerView。
/// 这是 SlotDispatch 中新组件类型的入口点。
library;

import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'tech_planner/tech_planner_view.dart';

/// Tech Planner Slot——按组件描述符渲染技术规划编辑器。
class TechPlannerSlot extends StatelessWidget {
  final ComponentDescriptor component;
  final String moduleId;

  const TechPlannerSlot({
    super.key,
    required this.component,
    required this.moduleId,
  });

  @override
  Widget build(BuildContext context) {
    final cfg = component.config;

    // 从 config 读取初始内容与标题
    final initialContent = cfg?['content'] as String? ?? '';
    final title = cfg?['title'] as String? ?? '未命名技术规划';
    final showAiPanel = cfg?['showAiPanel'] as bool? ?? true;

    // Phase 2：仓库路径（从 config.repoPath 读取）
    final targetRepoPath = cfg?['repoPath'] as String?;

    return TechPlannerView(
      initialContent: initialContent,
      title: title,
      showAiPanel: showAiPanel,
      moduleId: moduleId,
      targetRepoPath: targetRepoPath,
    );
  }
}
