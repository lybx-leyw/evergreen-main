/// Timeline 槽位——从 [ComponentDescriptor.config] 读取时间线数据渲染。
/// 支持 M2 dataSource 注入：拉取到的数据合并进 config['items']。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/slot/data_source_slot.dart';

/// Timeline 时间线组件。
class TimelineSlot extends DataSourceSlot {
  const TimelineSlot({super.key, required super.config});

  // Phase 2: 声明式数据绑定
  @override
  DataMapping get dataMapping => const DataMapping(targetKey: 'items');

  @override
  DataSourceSlotState<TimelineSlot> createState() => _TimelineSlotState();
}

class _TimelineSlotState extends DataSourceSlotState<TimelineSlot> {

  @override
  Widget buildStatic(Map<String, dynamic> cfg) {
    final title = cfg['title'] as String? ?? '时间线';
    final items = (cfg['items'] as List<dynamic>?) ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ),
        Expanded(
          child: items.isEmpty
              ? _emptyState(context)
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index] as Map<String, dynamic>;
                    return _TimelineEntry(
                      date: item['time'] as String? ??
                          item['date'] as String? ??
                          '',
                      title: item['label'] as String? ??
                          item['title'] as String? ??
                          '',
                      subtitle: item['description'] as String? ??
                          item['subtitle'] as String?,
                      isLast: index == items.length - 1,
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _emptyState(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timeline,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(height: 8),
          Text('暂无时间线数据',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _TimelineEntry extends StatelessWidget {
  final String date;
  final String title;
  final String? subtitle;
  final bool isLast;

  const _TimelineEntry({
    required this.date,
    required this.title,
    this.subtitle,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              date,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          SizedBox(
            width: 32,
            child: Column(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: theme.colorScheme.outline.withValues(alpha: 0.3),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleSmall),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(subtitle!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            )),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


