/// HTML 静态预览渲染器（M4 `tech-planner`）。
///
/// Dart 端 `TechPlannerSlot` 是交互式技术规划编辑器（WebView 预览 / 导出）。
/// 按 M4 决策，HTML 端允许「注册对应组件后占位降级」：此处渲染一个静态预览卡片，
/// 展示标题与简介，不实现编辑器本身（R9 优雅降级）。
library;
import 'package:evergreen_base/renderer/components/shared/html_helpers.dart';

String renderTechPlanner(Map<String, dynamic> comp) {
  final rawCfg = comp['config'];
  final cfg = rawCfg is Map ? rawCfg.cast<String, dynamic>() : <String, dynamic>{};
  final title = esc(cfg['title'] as String? ?? '技术规划');
  final note = esc(cfg['note'] as String? ??
      '交互式技术规划编辑器（Markdown 撰写 / AI 调研 / 导出），HTML 端以静态预览呈现');
  return '''
<div class="evg-comp evg-comp-tech">
  <div class="evg-tech-title">📐 $title</div>
  <div class="evg-tech-note">$note</div>
</div>''';
}
