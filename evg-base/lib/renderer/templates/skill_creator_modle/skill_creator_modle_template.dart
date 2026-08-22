/// skill-creator-modle 模板入口（Phase B）。
///
/// Skill 创作中心：多 agent 流水线（规划 agent 询问需求 → 按来源派深寻
/// agents 采集（web/PDF/OCR）→ 验收交涉 → 整合报告 → skill 创造 →
/// 终验 → 导出到 `plugins/<id>/skill/`），按「几个一」规格实现
/// 一面板一实例一固定 ID、一会话一固定历史、断点续做。
library;

import 'package:flutter/widgets.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/renderer/templates/template.dart';

import 'skill_creator_view.dart';

/// Skill 创作中心模板渲染器。
class SkillCreatorModleTemplate extends ModleRenderer {
  const SkillCreatorModleTemplate();

  @override
  Widget build(
    BuildContext context, {
    required ModuleDescriptor descriptor,
    String? workingDirectory,
  }) {
    return SkillCreatorView(
      descriptor: descriptor,
      workingDirectory: workingDirectory,
    );
  }
}
