/// Markdown 内容渲染——使用 MarkdownRenderer 解析并格式化展示。
import 'package:flutter/material.dart';
import 'package:evergreen_base/renderer/components/shared/slot_scale.dart';
import 'package:evergreen_base/renderer/components/shared/widgets/markdown_renderer.dart';

class MarkdownSlot extends StatelessWidget {
  final String markdown;
  final bool showHeader;

  const MarkdownSlot({required this.markdown, this.showHeader = true});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = SlotScale.of(context).scale;
    return Padding(
      padding: EdgeInsets.all(showHeader ? 16 * s : 8 * s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showHeader) ...[
            Row(
            children: [
              Icon(Icons.article, size: 18 * s,
                  color: theme.colorScheme.primary),
              SizedBox(width: 8 * s),
              Text(
                'Markdown',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: (theme.textTheme.titleSmall?.fontSize ?? 14) * s,
                ),
              ),
            ],
          ),
          SizedBox(height: 12 * s),
          ],
          Flexible(
            fit: FlexFit.tight,
            child: SingleChildScrollView(
              child: MarkdownRenderer(
                text: markdown,
                useCard: false,
                fontScale: s,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
