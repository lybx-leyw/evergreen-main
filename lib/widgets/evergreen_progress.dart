import 'package:flutter/material.dart';

/// 主题化进度条——统一替换 [LinearProgressIndicator]。
///
/// 使用主题色 (primary)，4px 高度，圆角端点。
/// 支持确定/不确定模式，可选标签文本。
///
/// ```dart
/// // 不确定进度
/// EvergreenProgress(label: '正在加载成绩...')
///
/// // 确定进度
/// EvergreenProgress(value: 0.7, label: '第 7/10 页')
/// ```
class EvergreenProgress extends StatelessWidget {
  /// 进度值 (0.0 ~ 1.0)。null 表示不确定模式。
  final double? value;

  /// 可选标签文本，显示在进度条下方。
  final String? label;

  /// 语义标签（无障碍）。
  final String? semanticLabel;

  const EvergreenProgress({
    super.key,
    this.value,
    this.label,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final indicator = ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: LinearProgressIndicator(
        value: value,
        minHeight: 4,
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
        semanticsLabel: semanticLabel,
      ),
    );

    if (label == null) return indicator;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        indicator,
        const SizedBox(height: 6),
        Text(
          label!,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
