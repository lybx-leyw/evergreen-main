import 'package:flutter/material.dart';

/// 品牌化加载指示器——ZJU 蓝脉冲动画 + 可选消息。
///
/// ```dart
/// // 标准
/// const LoadingIndicator(message: '加载课程列表...');
///
/// // 紧凑（卡片内嵌）
/// const LoadingIndicator.compact(hint: '查询中...');
/// ```
class LoadingIndicator extends StatelessWidget {
  final String? message;
  final String? semanticLabel;
  final bool compact;

  const LoadingIndicator({
    super.key,
    this.message,
    this.semanticLabel,
    this.compact = false,
  });

  /// 紧凑工厂——水平布局，适合嵌入卡片内。
  const LoadingIndicator.compact({
    super.key,
    String? hint,
    this.semanticLabel,
  })  : message = hint,
        compact = true;

  @override
  Widget build(BuildContext context) {
    final primary =
        Theme.of(context).colorScheme.primary;
    final onSurfaceVariant =
        Theme.of(context).colorScheme.onSurfaceVariant;

    final indicator = SizedBox(
      width: compact ? 16 : 36,
      height: compact ? 16 : 36,
      child: CircularProgressIndicator(
        strokeWidth: compact ? 2 : 3,
        color: primary,
      ),
    );

    final label = semanticLabel ?? message ?? '加载中';

    if (message == null && compact) {
      return Semantics(label: label, child: Center(child: indicator));
    }

    if (compact) {
      return Semantics(
        label: label,
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              indicator,
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  message!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: onSurfaceVariant,
                      ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Semantics(
      label: label,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            indicator,
            if (message != null) ...[
              const SizedBox(height: 16),
              Text(
                message!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: onSurfaceVariant,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 向后兼容别名。
@Deprecated('Use LoadingIndicator instead')
typedef LoadingWidget = LoadingIndicator;
