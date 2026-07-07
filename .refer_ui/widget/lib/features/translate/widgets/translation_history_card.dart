import 'package:flutter/material.dart';
import '../models/translation_history.dart';

/// 翻译历史记录卡片。
class TranslationHistoryCard extends StatelessWidget {
  final TranslationHistory history;
  final VoidCallback? onOpen;
  final VoidCallback? onDelete;

  const TranslationHistoryCard({
    super.key,
    required this.history,
    this.onOpen,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
        title: Text(history.fileName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${history.languagePair} · ${history.durationText}'
          '${history.totalTokens > 0 ? ' · ${history.totalTokens} tokens' : ''}',
          style: theme.textTheme.bodySmall,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (history.dualPdfPath != null)
              IconButton(
                icon: const Icon(Icons.visibility, size: 20),
                tooltip: '打开 PDF',
                onPressed: onOpen,
              ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              tooltip: '删除记录',
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}
