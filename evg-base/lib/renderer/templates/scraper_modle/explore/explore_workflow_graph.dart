/// ExploreWorkflowGraph — 探索模式工作流完整流程图（workflow 视图）。
///
/// 与定向抓取（[ScraperWorkflowGraph]）并列：探索模式驱动的是
/// [ExploreWorkflow]，此前 workflow 视图固定渲染定向抓取流程图 → 探索模式下
/// 永远停在「抓包中」，形同虚设（用户反馈 bug）。本组件展示探索 7 阶段
/// （idle→exploring→categorizing→confirming→building→registering→done/failed），
/// 当前阶段高亮、已完成打勾、失败红叉，并叠加实时计数
/// （已访问页 / 已捕获请求 / 候选 / 已确认 / 熔断状态）。
///
/// 数据源：[ExploreWorkflow.phase] + 计数。颜色全部从 colorScheme 派生。
library explore_workflow_graph;

import 'package:flutter/material.dart';

import 'explore_workflow.dart';

/// 流程图节点。
class _ExploreGraphNode {
  final ExplorePhase phase;
  final String label;
  final String detail;
  final bool reached;
  final bool current;

  const _ExploreGraphNode({
    required this.phase,
    required this.label,
    required this.detail,
    required this.reached,
    required this.current,
  });
}

/// 探索模式工作流流程图。
class ExploreWorkflowGraph extends StatelessWidget {
  final ExploreWorkflow workflow;

  const ExploreWorkflowGraph({super.key, required this.workflow});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final phase = workflow.phase;
    final failed = phase == ExplorePhase.failed;

    final order = <ExplorePhase>[
      ExplorePhase.idle,
      ExplorePhase.exploring,
      ExplorePhase.categorizing,
      ExplorePhase.confirming,
      ExplorePhase.building,
      ExplorePhase.registering,
      // 终态：正常完成显示 done，失败时用 failed 替代 done，使失败节点
      // 也能作为当前/末节点高亮，而不是所有节点都变成未到达。
      failed ? ExplorePhase.failed : ExplorePhase.done,
    ];
    final curIdx = order.indexOf(phase);

    final nodes = <_ExploreGraphNode>[
      for (var i = 0; i < order.length; i++)
        _ExploreGraphNode(
          phase: order[i],
          label: _label(order[i]),
          detail: _detail(order[i], workflow),
          reached: i <= curIdx,
          current: i == curIdx,
        ),
    ];

    return Container(
      color: scheme.surface,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── 标题行 ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.travel_explore_rounded,
                        size: 16, color: scheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      '探索工作流',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                    if (workflow.baseHost.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: scheme.tertiary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          workflow.baseHost,
                          style: TextStyle(
                            fontSize: 10,
                            color: scheme.tertiary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                    if (workflow.stallDetected) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: scheme.error.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '⚡ 空转熔断',
                          style: TextStyle(
                            fontSize: 10,
                            color: scheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 24),
                // ── 节点列（垂直流程）──
                for (var i = 0; i < nodes.length; i++) ...[
                  _buildNodeCard(context, scheme, nodes[i], failed),
                  if (i < nodes.length - 1)
                    _buildEdge(context, scheme, nodes[i], nodes[i + 1]),
                ],
                // ── 图例 ──
                const SizedBox(height: 24),
                _buildLegend(scheme),
                // ── 阶段错误（failed 原因）──
                if (workflow.errorMessage.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.errorContainer.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: scheme.error.withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      '❌ ${workflow.errorMessage}',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNodeCard(
      BuildContext context, ColorScheme scheme, _ExploreGraphNode node, bool failed) {
    final borderColor = node.current
        ? scheme.primary
        : node.reached
            ? scheme.primary.withValues(alpha: 0.4)
            : scheme.outlineVariant;
    final bg = node.current
        ? scheme.primaryContainer.withValues(alpha: 0.3)
        : node.reached
            ? scheme.surfaceContainerLow
            : scheme.surfaceContainerLowest;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: node.current ? 2 : 1),
        boxShadow: node.current
            ? [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: 0.15),
                  blurRadius: 8,
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          Icon(
            node.current
                ? Icons.radio_button_checked_rounded
                : node.reached
                    ? (failed && node.phase == workflow.phase
                        ? Icons.error_rounded
                        : Icons.check_circle_rounded)
                    : Icons.radio_button_unchecked_rounded,
            size: 18,
            color: node.current
                ? scheme.primary
                : node.reached
                    ? (failed && node.phase == workflow.phase
                        ? scheme.error
                        : scheme.primary)
                    : scheme.outline,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  node.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: node.current
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: node.reached
                        ? scheme.onSurface
                        : scheme.onSurfaceVariant,
                  ),
                ),
                if (node.detail.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    node.detail,
                    style: TextStyle(
                      fontSize: 10,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (node.current)
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.5, end: 1.0),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeInOut,
              builder: (ctx, v, _) => Container(
                width: 10 * v,
                height: 10 * v,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEdge(BuildContext context, ColorScheme scheme,
      _ExploreGraphNode from, _ExploreGraphNode to) {
    final active = from.reached;
    return SizedBox(
      height: 28,
      child: Row(
        children: [
          const SizedBox(width: 9),
          Expanded(
            child: CustomPaint(
              painter: _ExploreEdgePainter(
                active: active,
                color: active ? scheme.primary : scheme.outlineVariant,
              ),
            ),
          ),
          const SizedBox(width: 9),
        ],
      ),
    );
  }

  Widget _buildLegend(ColorScheme scheme) {
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        _legendItem(scheme, scheme.primary, '已完成'),
        _legendItem(scheme, scheme.outline, '未到达'),
      ],
    );
  }

  Widget _legendItem(ColorScheme scheme, Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
      ],
    );
  }

  /// 每个阶段的实时详情（计数/状态）。
  static String _detail(ExplorePhase p, ExploreWorkflow wf) {
    switch (p) {
      case ExplorePhase.idle:
        return wf.baseHost.isEmpty
            ? '等待点击「开始探索」'
            : '已锁定域名 ${wf.baseHost}（等待开始）';
      case ExplorePhase.exploring:
        return '已访问 ${wf.uniquePages}/${wf.limits.maxPages} 页 · '
            '已捕获 ${wf.requestsCaptured}/${wf.limits.maxRequests} 请求'
            '${wf.stallDetected ? ' · ⚡ 空转熔断: ${wf.stallMessage}' : ''}';
      case ExplorePhase.categorizing:
        return 'AI 正在把探索到的接口归类为候选数据源';
      case ExplorePhase.confirming:
        return '候选 ${wf.candidates.length} 个，等待用户勾选/改名确认'
            '${wf.selected.isNotEmpty ? '（已确认 ${wf.selected.length} 个）' : ''}';
      case ExplorePhase.building:
        return '逐源构建 data-{name} 插件（已确认 ${wf.selected.length} 个）';
      case ExplorePhase.registering:
        return '批量热注册 + orch.get 拉取验证';
      case ExplorePhase.done:
        return '✅ 全部注册验证完成';
      case ExplorePhase.failed:
        return '❌ 无法继续：${wf.errorMessage.isEmpty ? '未知原因' : wf.errorMessage}';
    }
  }

  static String _label(ExplorePhase p) => switch (p) {
        ExplorePhase.idle => '待机',
        ExplorePhase.exploring => '探索（枚举链接 + GET 导航）',
        ExplorePhase.categorizing => '归类（候选数据源）',
        ExplorePhase.confirming => '用户确认（多选/改名）',
        ExplorePhase.building => '逐源构建插件',
        ExplorePhase.registering => '批量注册 + 验证',
        ExplorePhase.done => '✅ 完成',
        ExplorePhase.failed => '❌ 失败',
      };
}

/// 边绘制器：正常实线 + 箭头。
class _ExploreEdgePainter extends CustomPainter {
  final bool active;
  final Color color;

  _ExploreEdgePainter({required this.active, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(0, midY), Offset(size.width - 2, midY), paint);
    final arrow = Path()
      ..moveTo(size.width - 4, midY - 4)
      ..lineTo(size.width, midY)
      ..lineTo(size.width - 4, midY + 4);
    canvas.drawPath(arrow, paint..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(covariant _ExploreEdgePainter old) =>
      old.active != active || old.color != color;
}
