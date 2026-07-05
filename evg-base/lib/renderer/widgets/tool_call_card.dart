/// 工具调用卡片——根据 [ToolCallOptions] 渲染工具调用信息。
///
/// 公开类：[ToolCallCard]
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import '../shared/theme_provider.dart';
import 'models.dart';

/// 工具调用卡片。
///
/// 读取 [ToolCallOptions] 控制：
/// - visible: 是否显示（外部判断）
/// - showArgs: 是否显示调用参数
/// - showResult: 是否显示调用结果
/// - autoCollapse: 完成后是否自动折叠
class ToolCallCard extends StatefulWidget {
  final ToolCallData call;
  final ToolCallOptions options;

  const ToolCallCard({
    super.key,
    required this.call,
    required this.options,
  });

  @override
  State<ToolCallCard> createState() => _ToolCallCardState();
}

class _ToolCallCardState extends State<ToolCallCard> {
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant ToolCallCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 完成后自动折叠
    if (widget.options.autoCollapse &&
        widget.call.completed &&
        !oldWidget.call.completed) {
      setState(() => _expanded = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokenBg = context.componentColor('toolCall', 'bg');
    final tokenBorder = context.componentColor('toolCall', 'border');
    final surface = Theme.of(context).colorScheme.surfaceContainerHighest;

    final call = widget.call;
    final isComplete = call.completed;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: tokenBg ?? surface,
        border: Border.all(
          color: tokenBorder ??
              Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 工具名 + 状态
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 8, 4),
              child: Row(
                children: [
                  Icon(
                    isComplete ? Icons.check_circle : Icons.build,
                    size: 14,
                    color: isComplete
                        ? Colors.green
                        : Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    call.name,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                        ),
                  ),
                  const Spacer(),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          // 详细信息
          if (_expanded) ...[
            if (widget.options.showArgs && call.arguments.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    call.arguments,
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            if (widget.options.showResult && call.result != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
                child: Text(
                  call.result!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 11,
                        height: 1.4,
                      ),
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ],
      ),
    );
  }
}
