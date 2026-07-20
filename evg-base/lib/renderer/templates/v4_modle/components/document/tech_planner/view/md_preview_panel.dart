/// Markdown 实时预览面板。
///
/// 使用 MarkdownRenderer 将编辑器内容实时渲染为富文本。
library;

import 'package:flutter/material.dart';
import 'package:evergreen_base/renderer/components/shared/widgets/markdown_renderer.dart';

/// Markdown 实时预览面板。
///
/// 接收 [content] 字符串，实时渲染为 Markdown。
/// [title] 作为面板标题显示在顶部。
class MdPreviewPanel extends StatelessWidget {
  final String content;
  final String title;

  const MdPreviewPanel({
    super.key,
    required this.content,
    this.title = '预览',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(left: BorderSide(color: colorScheme.outlineVariant, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 标题栏 ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
            ),
            child: Row(
              children: [
                Icon(Icons.visibility_outlined, size: 18,
                    color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Text(title,
                    style: theme.textTheme.labelLarge?.copyWith(
                        color: colorScheme.onSurfaceVariant)),
              ],
            ),
          ),

          // ── 内容 ──
          Expanded(
            child: content.isEmpty
                ? Center(
                    child: Text('暂无内容',
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant)))
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: MarkdownRenderer(
                      text: content,
                      useCard: false,
                      padding: EdgeInsets.zero,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
