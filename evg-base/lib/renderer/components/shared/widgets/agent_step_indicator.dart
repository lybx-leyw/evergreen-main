/// AgentStepIndicator — 事件驱动的 AI 进度指示器（Phase 2 · B2，共享组件）。
///
/// 由 Agent 事件驱动（toolDispatch / turnStarted / turnDone），真实反映 AI 步骤：
/// - 空闲 → "就绪"
/// - turnStarted + 无工具 → "思考中…"
/// - toolDispatch → "调用工具 `{name}` · 第 {step}/{maxSteps} 步"
/// - toolResult 失败 → "工具 `{name}` 失败，正在处理…"
/// - turnDone → 归零/隐藏
///
/// 视觉：4px 圆角进度条 + 标签（复用 EvergreenProgress 主题约定，颜色从 colorScheme 派生）。
/// 用法：
/// ```dart
/// AgentStepIndicator(
///   running: _isRunning,
///   currentTool: _currentTool,
///   step: _step,
///   maxSteps: 50,
///   phaseLabel: '生成中',
/// )
/// ```
library agent_step_indicator;

import 'package:flutter/material.dart';

/// AI 步骤指示器（纯展示，状态由父级从 Agent 事件推导）。
class AgentStepIndicator extends StatelessWidget {
  /// 是否正在运行（turnStarted→turnDone）。
  final bool running;

  /// 当前工具名（toolDispatch 时设置，toolResult 时清空）。
  final String currentTool;

  /// 当前步骤数（Agent._step）。
  final int step;

  /// 总步骤上限（AgentOptions.maxSteps）。
  final int maxSteps;

  /// 阶段标签（如"生成中"/"分析中"），可选。
  final String? phaseLabel;

  /// 是否发生错误（当前工具失败）。
  final bool hasError;

  const AgentStepIndicator({
    super.key,
    required this.running,
    this.currentTool = '',
    this.step = 0,
    this.maxSteps = 50,
    this.phaseLabel,
    this.hasError = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // ── 状态推导 ──
    String label;
    double? value; // null = 不确定模式
    Color color;

    if (!running) {
      label = phaseLabel ?? '就绪';
      value = null;
      color = scheme.outline;
    } else if (currentTool.isNotEmpty) {
      if (hasError) {
        label = '工具 `$currentTool` 失败，正在处理…';
        color = scheme.error;
      } else {
        label = '调用工具 `$currentTool`'
            '${maxSteps > 0 ? ' · 第 $step/$maxSteps 步' : ''}';
        color = scheme.primary;
      }
      // 工具执行阶段用不确定进度（无法预估时长）
      value = null;
    } else {
      label = '思考中…';
      value = null;
      color = scheme.secondary;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 指示点
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
          ),
        ),
        const SizedBox(width: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        // 进度条（运行中显示）
        if (running) ...[
          const SizedBox(width: 8),
          SizedBox(
            width: 60,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: value,
                minHeight: 3,
                backgroundColor: scheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
