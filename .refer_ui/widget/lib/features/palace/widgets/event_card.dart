/// Palace 事件卡片 —— 树状视图中的叶子节点。
library;

import 'package:flutter/material.dart';

import '../../../core/palace/models/consciousness_event.dart' show ConsciousnessEvent;

/// 单条事件卡片——显示标题（rawContent 前 60 字）、情绪 emoji、标签。
class EventCard extends StatelessWidget {
  final ConsciousnessEvent event;
  final bool isSelected;
  final VoidCallback? onTap;

  const EventCard({
    super.key,
    required this.event,
    this.isSelected = false,
    this.onTap,
  });

  static String _emojiForValence(double? valence) {
    if (valence == null) return '';
    if (valence >= 0.7) return '😄';
    if (valence >= 0.2) return '🙂';
    if (valence >= -0.2) return '😐';
    if (valence >= -0.7) return '😟';
    return '😡';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final emoji = _emojiForValence(event.emotionalValence);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      color: isSelected ? theme.colorScheme.primaryContainer : null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  event.title,
                  style: theme.textTheme.bodyMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (emoji.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(emoji, style: const TextStyle(fontSize: 16)),
              ],
              if (event.aiSummary != null && event.aiSummary!.isNotEmpty) ...[
                const SizedBox(width: 8),
                Icon(Icons.auto_awesome,
                    size: 14, color: theme.colorScheme.tertiary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
