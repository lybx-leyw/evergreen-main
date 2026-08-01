/// 思考栏——根据 [ThinkingOptions] 渲染 AI 思考过程。
///
/// 公开类：[ThinkingBlock]
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';

/// AI 思考过程展示组件。
///
/// 读取 [ThinkingOptions] 控制：
/// - visible: 是否显示（外部判断）
/// - transparent: 背景是否透明
/// - mode: expand（展开）| scroll（滑动窗口）
/// - showDuration: 是否显示思考耗时
class ThinkingBlock extends StatefulWidget {
  final String content;
  final ThinkingOptions options;

  const ThinkingBlock({
    super.key,
    required this.content,
    required this.options,
  });

  @override
  State<ThinkingBlock> createState() => _ThinkingBlockState();
}

class _ThinkingBlockState extends State<ThinkingBlock> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final surface =
        Theme.of(context).colorScheme.surfaceContainerHighest;

    final bgColor = widget.options.transparent
        ? Colors.transparent
        : surface;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: widget.options.transparent
            ? Border.all(
                color: Theme.of(context)
                    .colorScheme
                    .outline
                    .withValues(alpha: 0.2))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 思考栏头部
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
              child: Row(
                children: [
                  Icon(
                    Icons.psychology,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '思考过程',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  if (widget.options.showDuration) ...[
                    const SizedBox(width: 8),
                    Text(
                      '耗时 2.3s',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                  const Spacer(),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          // 思考内容
          if (_expanded)
            switch (widget.options.mode) {
              'scroll' => SizedBox(
                  height: 200,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: Text(
                      widget.content,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                            height: 1.5,
                          ),
                    ),
                  ),
                ),
              _ => Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Text( // 'expand' + 未知
                    widget.content,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                          height: 1.5,
                        ),
                  ),
                ),
            },
        ],
      ),
    );
  }
}
