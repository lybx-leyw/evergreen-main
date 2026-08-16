/// ScraperWorkflowStepper — 工作流横向步骤条（Phase 2 · B1）。
///
/// 展示 8 阶段（idle→capturing→analyzing→questioning→generating→running→
/// debugging→done/failed），当前阶段高亮 + 呼吸动画，已完成打勾，失败红叉，
/// 悬停/点击显示阶段耗时与关键计数（日志数/调试轮数/refining 轮次）。
///
/// 数据源：[ScraperWorkflow.phase] + [ScraperWorkflow.timeline]（Phase 1 产出）。
/// 颜色全部从全局 colorScheme 派生（主题规约：不硬编码）。
library scraper_workflow_stepper;

import 'package:flutter/material.dart';

import 'scraper_workflow.dart';

/// 步骤条显示的阶段顺序（按流程）。
const List<ScraperPhase> _stepOrder = [
  ScraperPhase.capturing,
  ScraperPhase.analyzing,
  ScraperPhase.questioning,
  ScraperPhase.generating,
  ScraperPhase.running,
  ScraperPhase.debugging,
  ScraperPhase.done,
];

/// 工作流步骤条。
class ScraperWorkflowStepper extends StatelessWidget {
  final ScraperWorkflow workflow;
  final bool compact; // 紧凑模式（非 workflow 视图时顶部常驻，B1）

  const ScraperWorkflowStepper({
    super.key,
    required this.workflow,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final phase = workflow.phase;
    final done = phase == ScraperPhase.done;
    final failed = phase == ScraperPhase.failed;

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
          // 当前阶段标签
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
          // 步骤节点
          Expanded(
            child: Row(
              children: [
                for (var i = 0; i < _stepOrder.length; i++) ...[
                  if (i > 0)
                    Expanded(child: _buildConnector(scheme, i)),
                  _buildStep(context, scheme, _stepOrder[i], done, failed),
                ],
              ],
            ),
          ),
          // 计数信息（紧凑模式显示）
          if (compact && workflow.debugCount > 0) ...[
            const SizedBox(width: 12),
            _CompactBadge(
              text: workflow.warningSent3
                  ? '⚠ ${workflow.consecutiveFailures}'
                  : '🔧 ${workflow.consecutiveFailures}',
              color: workflow.warningSent3 ? scheme.error : scheme.secondary,
            ),
          ],
          if (compact && workflow.refineCount > 0) ...[
            const SizedBox(width: 6),
            _CompactBadge(
              text: '🔄 ${workflow.refineCount}',
              color: scheme.primary,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildConnector(ColorScheme scheme, int idx) {
    // 连接线：已完成阶段之间用 primary，其余 outlineVariant
    final prev = _stepOrder[idx - 1];
    final completed = _isBeforeOrAt(prev, workflow.phase) &&
        workflow.phase != ScraperPhase.failed;
    return Container(
      height: 2,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: completed ? scheme.primary : scheme.outlineVariant,
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }

  Widget _buildStep(BuildContext context, ColorScheme scheme, ScraperPhase step,
      bool done, bool failed) {
    final current = workflow.phase == step;
    final completed = _isBeforeOrAt(step, workflow.phase) && !failed;
    final isFailed = failed && step == _lastReached(workflow.phase);

    final color = completed
        ? scheme.primary
        : current
            ? scheme.primary
            : scheme.outlineVariant;

    return Tooltip(
      message: _stepTooltip(step, scheme),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 节点圆
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
              child: _buildNodeContent(scheme, step, current, completed, isFailed),
            ),
          ),
          const SizedBox(height: 3),
          // 阶段名
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

  Widget _buildNodeContent(
      ColorScheme scheme, ScraperPhase step, bool current, bool completed, bool isFailed) {
    if (isFailed) {
      return Icon(Icons.close_rounded, size: compact ? 10 : 12, color: scheme.error);
    }
    if (completed && !current) {
      return Icon(Icons.check_rounded, size: compact ? 10 : 12, color: scheme.primary);
    }
    // 当前节点：呼吸动画点
    if (current) {
      return TweenAnimationBuilder<double>(
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
      );
    }
    // 未到达
    return Container(
      width: compact ? 5 : 6,
      height: compact ? 5 : 6,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: scheme.outlineVariant,
      ),
    );
  }

  bool _isBeforeOrAt(ScraperPhase step, ScraperPhase current) {
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
    final si = order.indexOf(step);
    final ci = order.indexOf(current);
    if (si < 0 || ci < 0) return false;
    // debugging 循环：当前 debugging 时，debugging 节点视为进行中
    if (step == ScraperPhase.debugging) {
      return current == ScraperPhase.debugging ||
          current == ScraperPhase.done ||
          current == ScraperPhase.failed;
    }
    return si <= ci;
  }

  ScraperPhase _lastReached(ScraperPhase current) {
    final order = <ScraperPhase>[
      ScraperPhase.capturing,
      ScraperPhase.analyzing,
      ScraperPhase.generating,
      ScraperPhase.running,
      ScraperPhase.debugging,
    ];
    for (final p in order.reversed) {
      if (_isBeforeOrAt(p, current)) return p;
    }
    return ScraperPhase.capturing;
  }

  String _stepTooltip(ScraperPhase step, ColorScheme scheme) {
    // 从 timeline 找该阶段耗时
    final entries = workflow.timeline.where((t) => t.phase == step);
    final elapsed = entries.isEmpty
        ? null
        : entries.last.elapsed;
    final buf = StringBuffer(_stepFullName(step));
    if (elapsed != null && elapsed.inMilliseconds > 0) {
      buf.write('\n耗时 ${_fmtDuration(elapsed)}');
    }
    if (step == ScraperPhase.capturing) {
      buf.write('\n日志 ${workflow.logs.length} 条'
          '${workflow.snapshotFrozen ? '（已冻结）' : ''}');
    }
    if (step == ScraperPhase.debugging) {
      buf.write('\n连续失败 ${workflow.consecutiveFailures} 轮'
          '${workflow.warningSent3 ? ' ⚠️' : ''}');
    }
    return buf.toString();
  }

  static String _fmtDuration(Duration d) {
    if (d.inSeconds < 1) return '${d.inMilliseconds}ms';
    if (d.inMinutes < 1) return '${d.inSeconds}s';
    return '${d.inMinutes}m${d.inSeconds % 60}s';
  }

  static String _phaseLabel(ScraperPhase p) => switch (p) {
        ScraperPhase.idle => '待机',
        ScraperPhase.capturing => '抓包中',
        ScraperPhase.analyzing => '分析中',
        ScraperPhase.questioning => '追问中',
        ScraperPhase.generating => '生成中',
        ScraperPhase.running => '运行中',
        ScraperPhase.debugging => '调试中',
        ScraperPhase.done => '✅ 完成',
        ScraperPhase.failed => '❌ 失败',
      };

  static String _stepShortName(ScraperPhase p) => switch (p) {
        ScraperPhase.capturing => '抓包',
        ScraperPhase.analyzing => '分析',
        ScraperPhase.questioning => '追问',
        ScraperPhase.generating => '生成',
        ScraperPhase.running => '运行',
        ScraperPhase.debugging => '调试',
        ScraperPhase.done => '完成',
        _ => '',
      };

  static String _stepFullName(ScraperPhase p) => switch (p) {
        ScraperPhase.capturing => '抓包（用户操作）',
        ScraperPhase.analyzing => 'AI 分析日志',
        ScraperPhase.questioning => 'AI 追问',
        ScraperPhase.generating => 'AI 生成代码',
        ScraperPhase.running => '执行验证',
        ScraperPhase.debugging => '调试',
        ScraperPhase.done => '完成',
        _ => '',
      };

  static IconData _phaseIcon(ScraperPhase p) => switch (p) {
        ScraperPhase.idle => Icons.pause_circle_outline,
        ScraperPhase.capturing => Icons.wifi_find_rounded,
        ScraperPhase.analyzing => Icons.analytics_rounded,
        ScraperPhase.questioning => Icons.help_outline_rounded,
        ScraperPhase.generating => Icons.code_rounded,
        ScraperPhase.running => Icons.play_circle_outline,
        ScraperPhase.debugging => Icons.bug_report_rounded,
        ScraperPhase.done => Icons.check_circle_rounded,
        ScraperPhase.failed => Icons.error_rounded,
      };

  /// 阶段色——从 colorScheme 派生（主题规约）。
  static Color _phaseColor(ScraperPhase p, ColorScheme scheme) => switch (p) {
        ScraperPhase.capturing => scheme.tertiary,
        ScraperPhase.running ||
        ScraperPhase.analyzing ||
        ScraperPhase.generating ||
        ScraperPhase.debugging =>
          scheme.secondary,
        ScraperPhase.done => scheme.primary,
        ScraperPhase.failed => scheme.error,
        _ => scheme.outline,
      };
}

/// 紧凑计数徽标。
class _CompactBadge extends StatelessWidget {
  final String text;
  final Color color;

  const _CompactBadge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
