/// ScraperWorkflowGraph — 工作流完整流程图（Phase 2 · B1，workflow 视图）。
///
/// 展示：
/// - 阶段节点（含耗时、note）
/// - 主流程边（已完成 primary / 未到达 outline）
/// - **回溯轨迹**（rollbackHistory → 虚线回退边，A14）
/// - **refining 轮次**（循环角标，A16/A19）
/// - 当前阶段呼吸高亮
///
/// 数据源：[ScraperWorkflow.timeline] + [ScraperWorkflow.rollbackHistory] +
/// [ScraperWorkflow.refineCount]。颜色全部从 colorScheme 派生。
library scraper_workflow_graph;

import 'package:flutter/material.dart';

import 'scraper_workflow.dart';

/// 流程图节点。
class _GraphNode {
  final ScraperPhase phase;
  final String label;
  final Duration? elapsed;
  final bool reached;
  final bool current;

  _GraphNode({
    required this.phase,
    required this.label,
    this.elapsed,
    required this.reached,
    required this.current,
  });
}

/// 工作流流程图。
class ScraperWorkflowGraph extends StatelessWidget {
  final ScraperWorkflow workflow;

  const ScraperWorkflowGraph({super.key, required this.workflow});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // ── 构建节点列表（主流程顺序）──
    final order = <ScraperPhase>[
      ScraperPhase.idle,
      ScraperPhase.capturing,
      ScraperPhase.analyzing,
      ScraperPhase.questioning,
      ScraperPhase.generating,
      ScraperPhase.running,
      ScraperPhase.debugging,
      ScraperPhase.done,
    ];
    final curIdx = order.indexOf(workflow.phase);
    final failed = workflow.phase == ScraperPhase.failed;

    final nodes = <_GraphNode>[
      for (var i = 0; i < order.length; i++)
        _GraphNode(
          phase: order[i],
          label: _label(order[i]),
          elapsed: _elapsedFor(order[i]),
          reached: failed
              ? i <= curIdx
              : i <= (curIdx < 0 ? order.length : curIdx),
          current: i == curIdx,
        ),
    ];

    // ── 回退轨迹（rollbackHistory → 回退源/目标对）──
    final rollbackPairs = <(ScraperPhase, ScraperPhase)>[];
    final hist = workflow.rollbackHistory;
    for (var i = 0; i < hist.length; i++) {
      final from = hist[i];
      // 目标 = 下一个被记录的阶段（若有），否则当前阶段
      final to = i + 1 < hist.length ? hist[i + 1] : workflow.phase;
      if (from != to) rollbackPairs.add((from, to));
    }

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
                    Icon(Icons.account_tree_rounded,
                        size: 16, color: scheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      '工作流',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                    if (workflow.refineCount > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '优化第 ${workflow.refineCount} 轮',
                          style: TextStyle(
                            fontSize: 10,
                            color: scheme.primary,
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
                    _buildEdge(context, scheme, nodes[i], nodes[i + 1],
                        rollbackPairs),
                ],
                // ── 图例 ──
                const SizedBox(height: 24),
                _buildLegend(scheme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Duration? _elapsedFor(ScraperPhase phase) {
    final entries = workflow.timeline.where((t) => t.phase == phase);
    if (entries.isEmpty) return null;
    return entries.last.elapsed;
  }

  Widget _buildNodeCard(
      BuildContext context, ColorScheme scheme, _GraphNode node, bool failed) {
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
          // 状态图标
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
                if (node.elapsed != null &&
                    node.elapsed!.inMilliseconds > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    '耗时 ${_fmtDuration(node.elapsed!)}',
                    style: TextStyle(
                      fontSize: 10,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          // 当前节点呼吸动画点
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

  /// 节点间连接：正常边（实线）+ 回溯边（虚线，含回退箭头）。
  Widget _buildEdge(BuildContext context, ColorScheme scheme, _GraphNode from,
      _GraphNode to, List<(ScraperPhase, ScraperPhase)> rollbacks) {
    final active = from.reached;
    final isRollback = rollbacks.any((r) => r.$1 == from.phase && r.$2 == to.phase);

    return SizedBox(
      height: 28,
      child: Row(
        children: [
          const SizedBox(width: 9),
          Expanded(
            child: CustomPaint(
              painter: _EdgePainter(
                active: active,
                isRollback: isRollback,
                color: isRollback
                    ? scheme.tertiary
                    : active
                        ? scheme.primary
                        : scheme.outlineVariant,
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
        _legendItem(scheme, scheme.tertiary, '回退轨迹'),
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
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  static String _label(ScraperPhase p) => switch (p) {
        ScraperPhase.idle => '待机',
        ScraperPhase.capturing => '抓包（用户操作）',
        ScraperPhase.analyzing => 'AI 分析日志',
        ScraperPhase.questioning => 'AI 追问',
        ScraperPhase.generating => 'AI 生成代码',
        ScraperPhase.running => '执行验证',
        ScraperPhase.debugging => '调试',
        ScraperPhase.done => '✅ 完成',
        ScraperPhase.failed => '❌ 失败',
      };

  static String _fmtDuration(Duration d) {
    if (d.inSeconds < 1) return '${d.inMilliseconds}ms';
    if (d.inMinutes < 1) return '${d.inSeconds}s';
    return '${d.inMinutes}m${d.inSeconds % 60}s';
  }
}

/// 边绘制器：正常实线 / 回退虚线 + 箭头。
class _EdgePainter extends CustomPainter {
  final bool active;
  final bool isRollback;
  final Color color;

  _EdgePainter({
    required this.active,
    required this.isRollback,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2;
    final paint = Paint()
      ..color = color
      ..strokeWidth = isRollback ? 1.5 : 2
      ..style = PaintingStyle.stroke;

    if (isRollback) {
      // 虚线 + 回退箭头
      const dashWidth = 4.0;
      const dashSpace = 3.0;
      var x = 0.0;
      while (x < size.width - 8) {
        canvas.drawLine(Offset(x, midY), Offset(x + dashWidth, midY), paint);
        x += dashWidth + dashSpace;
      }
      // 箭头（指向下个节点）
      final arrow = Path()
        ..moveTo(size.width - 2, midY - 5)
        ..lineTo(size.width + 4, midY)
        ..lineTo(size.width - 2, midY + 5);
      canvas.drawPath(arrow, paint..style = PaintingStyle.fill);
    } else {
      canvas.drawLine(Offset(0, midY), Offset(size.width - 2, midY), paint);
      // 箭头
      final arrow = Path()
        ..moveTo(size.width - 4, midY - 4)
        ..lineTo(size.width, midY)
        ..lineTo(size.width - 4, midY + 4);
      canvas.drawPath(arrow, paint..style = PaintingStyle.fill);
    }
  }

  @override
  bool shouldRepaint(covariant _EdgePainter old) =>
      old.active != active ||
      old.isRollback != isRollback ||
      old.color != color;
}
