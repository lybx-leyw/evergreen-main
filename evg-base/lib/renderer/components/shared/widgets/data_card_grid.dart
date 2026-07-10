/// 数据卡片网格——根据 [DataBindingDescriptor(display=card)] 渲染卡片网格。
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'empty_state.dart';

/// 数据卡片网格视图。
class DataCardGrid extends StatelessWidget {
  final DataBindingDescriptor binding;
  final ActionDescriptor? actions;
  final List<Map<String, dynamic>> items;
  final void Function(int index, Map<String, dynamic> item)? onTap;
  final int crossAxisCount;

  const DataCardGrid({
    super.key,
    required this.binding,
    this.actions,
    this.items = const [],
    this.onTap,
    this.crossAxisCount = 2,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const EmptyState(
        icon: Icons.dashboard_outlined,
        title: '暂无数据',
      );
    }

    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.2,
      ),
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _DataCard(
          item: item,
          onTap: () => onTap?.call(index, item),
        );
      },
    );
  }
}

/// 单张数据卡片。
class _DataCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback? onTap;

  const _DataCard({required this.item, this.onTap});

  @override
  Widget build(BuildContext context) {
    final title = item['title']?.toString() ??
        item['name']?.toString() ??
        item['label']?.toString() ??
        '';
    final subtitle = item['subtitle']?.toString() ??
        item['description']?.toString();
    final value = item['value']?.toString();
    final trend = item['trend']?.toString();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (value != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      value,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                    ),
                    if (trend != null) ...[
                      const SizedBox(width: 8),
                      Icon(
                        trend == 'up'
                            ? Icons.trending_up
                            : Icons.trending_down,
                        size: 18,
                        color: trend == 'up'
                            ? Colors.green
                            : Theme.of(context).colorScheme.error,
                      ),
                    ],
                  ],
                ),
              ],
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
