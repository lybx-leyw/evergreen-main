/// Kanban 槽位——从 [ComponentDescriptor.config] 读取列和卡片数据渲染看板。
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';

/// Kanban 看板组件。
class KanbanSlot extends StatelessWidget {
  final ComponentDescriptor config;

  const KanbanSlot({super.key, required this.config});

  @override
  Widget build(BuildContext context) {
    final cfg = config.config;
    final columns = (cfg['columns'] as List<dynamic>?) ?? [];

    if (columns.isEmpty) {
      return _emptyState(context);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final colCount = columns.length;
        final colWidth = (constraints.maxWidth - (colCount - 1) * 8) / colCount;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: columns.map((col) {
              final colMap = col as Map<String, dynamic>;
              return SizedBox(
                width: colWidth.clamp(120, 240),
                child: _KanbanColumn(
                  title: colMap['title'] as String? ?? '',
                  color: _colorFromTitle(colMap['title'] as String? ?? ''),
                  items: (colMap['items'] as List<dynamic>?) ?? [],
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _emptyState(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.view_kanban, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(height: 8),
          Text('暂无看板数据', style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  static Color _colorFromTitle(String title) {
    final t = title.toLowerCase();
    if (t.contains('完成') || t.contains('done')) return Colors.green;
    if (t.contains('进行中') || t.contains('doing')) return Colors.orange;
    if (t.contains('规划') || t.contains('todo')) return Colors.blue;
    return Colors.grey;
  }
}

class _KanbanColumn extends StatelessWidget {
  final String title;
  final Color color;
  final List<dynamic> items;

  const _KanbanColumn({required this.title, required this.color, required this.items});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(title, style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('${items.length}', style: theme.textTheme.labelSmall),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...items.map((item) {
            final itemMap = item as Map<String, dynamic>;
            return Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  itemMap['title'] as String? ?? itemMap['label'] as String? ?? '',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
