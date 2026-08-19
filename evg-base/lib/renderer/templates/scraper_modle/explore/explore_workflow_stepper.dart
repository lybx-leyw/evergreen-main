/// ExploreWorkflowStepper — 探索模式工作流横向步骤条（Phase 7）。
///
/// 修复：探索模式此前顶部复用 [ScraperWorkflowStepper]（绑定定向抓取 workflow），
/// 而探索模式实际驱动 [ExploreWorkflow] → 顶部步骤条永远停在「抓包中」。
/// 本组件展示探索 6 阶段（exploring→categorizing→confirming→building→
/// registering→done），当前阶段高亮、已完成打勾、失败红叉。
///
/// 颜色全部从全局 colorScheme 派生（主题规约：不硬编码）。
library explore_workflow_stepper;

import 'package:flutter/material.dart';

import 'explore_workflow.dart';

/// 步骤条显示的探索阶段顺序。
const List<ExplorePhase> _stepOrder = [
  ExplorePhase.exploring,
  ExplorePhase.categorizing,
  ExplorePhase.confirming,
  ExplorePhase.building,
  ExplorePhase.registering,
  ExplorePhase.done,
];

/// 探索模式工作流步骤条。
class ExploreWorkflowStepper extends StatelessWidget {
  final ExploreWorkflow workflow;
  final bool compact;

  const ExploreWorkflowStepper({
    super.key,
    required this.workflow,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final phase = workflow.phase;
    final failed = phase == ExplorePhase.failed;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 16,
        vertical: compact ? 4 : 8,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          if (!compact) ...[
            Icon(_phaseIcon(phase), size: 14, color: _phaseColor(phase, scheme)),
            const SizedBox(width: 6),
            Text(
              _phaseLabel(phase),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _phaseColor(phase, scheme),
              ),
            ),
            const SizedBox(width: 16),
          ],
          Expanded(
            child: Row(
              children: [
                for (var i = 0; i < _stepOrder.length; i++) ...[
                  if (i > 0)
                    Expanded(
                      child: _buildConnector(scheme, i, failed),
                    ),
                  _buildStep(scheme, _stepOrder[i], failed),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnector(ColorScheme scheme, int idx, bool failed) {
    final prev = _stepOrder[idx - 1];
    final completed =
        _isBeforeOrAt(prev, workflow.phase) && !failed;
    return Container(
      height: 2,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: completed ? scheme.primary : scheme.outlineVariant,
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }

  Widget _buildStep(ColorScheme scheme, ExplorePhase step, bool failed) {
    final current = workflow.phase == step;
    final completed = _isBeforeOrAt(step, workflow.phase) && !failed;

    final color = completed
        ? scheme.primary
        : current
            ? scheme.primary
            : scheme.outlineVariant;

    return Tooltip(
      message: _stepFullName(step),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: compact ? 18 : 22,
            height: compact ? 18 : 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: current
                  ? scheme.primaryContainer
                  : completed
                      ? scheme.primary.withValues(alpha: 0.15)
                      : scheme.surfaceContainerHighest,
              border: Border.all(
                color: current ? scheme.primary : color,
                width: current ? 2 : 1,
              ),
            ),
            child: Center(
              child: current
                  ? TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.6, end: 1.0),
                      duration: const Duration(milliseconds: 800),
                      curve: Curves.easeInOut,
                      builder: (ctx, v, _) => Container(
                        width: (compact ? 6 : 8) * v,
                        height: (compact ? 6 : 8) * v,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: scheme.primary,
                        ),
                      ),
                    )
                  : completed
                      ? Icon(Icons.check_rounded,
                          size: compact ? 10 : 12, color: scheme.primary)
                      : Container(
                          width: compact ? 5 : 6,
                          height: compact ? 5 : 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: scheme.outlineVariant,
                          ),
                        ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            _stepShortName(step),
            style: TextStyle(
              fontSize: compact ? 8.5 : 10,
              fontWeight: current ? FontWeight.w600 : FontWeight.normal,
              color: current
                  ? scheme.primary
                  : completed
                      ? scheme.onSurface
                      : scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  bool _isBeforeOrAt(ExplorePhase step, ExplorePhase current) {
    final order = <ExplorePhase>[
      ExplorePhase.idle,
      ExplorePhase.exploring,
      ExplorePhase.categorizing,
      ExplorePhase.confirming,
      ExplorePhase.building,
      ExplorePhase.registering,
      ExplorePhase.done,
    ];
    final si = order.indexOf(step);
    final ci = order.indexOf(current);
    if (si < 0 || ci < 0) return false;
    return si <= ci;
  }

  static String _stepShortName(ExplorePhase p) => switch (p) {
        ExplorePhase.exploring => '探索',
        ExplorePhase.categorizing => '归类',
        ExplorePhase.confirming => '确认',
        ExplorePhase.building => '构建',
        ExplorePhase.registering => '注册',
        ExplorePhase.done => '完成',
        _ => '',
      };

  static String _stepFullName(ExplorePhase p) => switch (p) {
        ExplorePhase.exploring => '探索（枚举链接 + GET 导航）',
        ExplorePhase.categorizing => '归类（候选数据源）',
        ExplorePhase.confirming => '用户确认（多选/改名）',
        ExplorePhase.building => '逐源构建插件',
        ExplorePhase.registering => '批量注册 + 验证',
        ExplorePhase.done => '完成',
        _ => '',
      };

  static String _phaseLabel(ExplorePhase p) => switch (p) {
        ExplorePhase.idle => '探索待机',
        ExplorePhase.exploring => '探索中',
        ExplorePhase.categorizing => '归类中',
        ExplorePhase.confirming => '等待确认',
        ExplorePhase.building => '构建中',
        ExplorePhase.registering => '注册中',
        ExplorePhase.done => '✅ 探索完成',
        ExplorePhase.failed => '❌ 探索失败',
      };

  static IconData _phaseIcon(ExplorePhase p) => switch (p) {
        ExplorePhase.idle => Icons.travel_explore_rounded,
        ExplorePhase.exploring => Icons.radar_rounded,
        ExplorePhase.categorizing => Icons.category_rounded,
        ExplorePhase.confirming => Icons.checklist_rounded,
        ExplorePhase.building => Icons.construction_rounded,
        ExplorePhase.registering => Icons.link_rounded,
        ExplorePhase.done => Icons.check_circle_rounded,
        ExplorePhase.failed => Icons.error_rounded,
      };

  static Color _phaseColor(ExplorePhase p, ColorScheme scheme) => switch (p) {
        ExplorePhase.exploring => scheme.tertiary,
        ExplorePhase.categorizing ||
        ExplorePhase.confirming ||
        ExplorePhase.building ||
        ExplorePhase.registering =>
          scheme.secondary,
        ExplorePhase.done => scheme.primary,
        ExplorePhase.failed => scheme.error,
        _ => scheme.outline,
      };
}
