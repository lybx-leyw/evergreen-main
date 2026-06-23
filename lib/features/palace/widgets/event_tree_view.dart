/// Palace 事件树状视图 —— 类型 → 日期 → 卡片 三层结构。
library;

import 'package:flutter/material.dart';

import '../../../core/palace/models/consciousness_event.dart'
    show ConsciousnessEvent, EventType;
import 'event_card.dart';
import 'event_detail_panel.dart';

/// 按类型分组 → 按日期分组 的三层树状视图。
class EventTreeView extends StatefulWidget {
  final List<ConsciousnessEvent> events;
  final EventType? filterType;

  const EventTreeView({
    super.key,
    required this.events,
    this.filterType,
  });

  @override
  State<EventTreeView> createState() => _EventTreeViewState();
}

class _EventTreeViewState extends State<EventTreeView> {
  String? _expandedEventId;
  final Set<String> _expandedTypeNodes = {};
  final Set<String> _expandedDateNodes = {};

  @override
  void initState() {
    super.initState();
    // 默认展开所有类型节点
    for (final type in EventType.values) {
      _expandedTypeNodes.add(type.name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.filterType != null
        ? widget.events.where((e) => e.type == widget.filterType).toList()
        : widget.events;

    if (filtered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inbox_outlined, size: 48,
                  color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 12),
              const Text('宫殿空空如也', style: TextStyle(fontSize: 16)),
              const SizedBox(height: 4),
              const Text('通过 AI 对话或手动捕捉来存入第一条认知碎片',
                  style: TextStyle(fontSize: 13, color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    // 按类型分组
    final grouped = <EventType, List<ConsciousnessEvent>>{};
    for (final event in filtered) {
      grouped.putIfAbsent(event.type, () => []).add(event);
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final type in EventType.values)
          if (grouped.containsKey(type))
            _buildTypeNode(type, grouped[type]!),
      ],
    );
  }

  Widget _buildTypeNode(EventType type, List<ConsciousnessEvent> events) {
    final isExpanded = _expandedTypeNodes.contains(type.name);
    final (icon, label) = _typeMeta(type);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () {
            setState(() {
              if (isExpanded) {
                _expandedTypeNodes.remove(type.name);
              } else {
                _expandedTypeNodes.add(type.name);
              }
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Icon(isExpanded ? Icons.expand_more : Icons.chevron_right,
                    size: 20),
                const SizedBox(width: 4),
                Text('$icon ', style: const TextStyle(fontSize: 16)),
                Text(label,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                Text('(${events.length})',
                    style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.outline)),
              ],
            ),
          ),
        ),
        if (isExpanded)
          ..._buildDateGroups(events),
        const Divider(height: 1, indent: 40),
      ],
    );
  }

  List<Widget> _buildDateGroups(List<ConsciousnessEvent> events) {
    // 按日期分组
    final dateMap = <DateTime, List<ConsciousnessEvent>>{};
    for (final e in events) {
      final day = DateTime(e.capturedAt.year, e.capturedAt.month, e.capturedAt.day);
      dateMap.putIfAbsent(day, () => []).add(e);
    }

    final days = dateMap.keys.toList()..sort((a, b) => b.compareTo(a));

    return [
      for (final day in days)
        _buildDateNode(day, dateMap[day]!),
    ];
  }

  Widget _buildDateNode(DateTime day, List<ConsciousnessEvent> events) {
    final dayKey = '${day.toIso8601String()}_${events.first.type.name}';
    final isExpanded = _expandedDateNodes.contains(dayKey);
    final dateLabel = _formatDay(day);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () {
            setState(() {
              if (isExpanded) {
                _expandedDateNodes.remove(dayKey);
              } else {
                _expandedDateNodes.add(dayKey);
              }
            });
          },
          child: Padding(
            padding: const EdgeInsets.only(left: 56, right: 16, top: 2, bottom: 2),
            child: Row(
              children: [
                Icon(isExpanded ? Icons.expand_more : Icons.chevron_right,
                    size: 18),
                const SizedBox(width: 4),
                Text(dateLabel,
                    style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
                const SizedBox(width: 6),
                Text('(${events.length})',
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.outline)),
              ],
            ),
          ),
        ),
        if (isExpanded)
          ...events.map((event) {
            final isSelected = _expandedEventId == event.id;
            return Column(
              children: [
                EventCard(
                  event: event,
                  isSelected: isSelected,
                  onTap: () {
                    setState(() {
                      _expandedEventId = isSelected ? null : event.id;
                    });
                  },
                ),
                if (isSelected) EventDetailPanel(event: event),
              ],
            );
          }),
      ],
    );
  }

  (String, String) _typeMeta(EventType type) => switch (type) {
    EventType.thought => ('💡', '想法'),
    EventType.lesson => ('📖', '教训'),
    EventType.decision => ('🎯', '决策'),
    EventType.reflection => ('🪞', '反思'),
    EventType.connection => ('🔗', '连接'),
    EventType.milestone => ('🏔️', '节点'),
  };

  String _formatDay(DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;

    if (diff == 0) return '今天';
    if (diff == 1) return '昨天';
    if (diff < 7) return '$diff 天前';
    return '${day.year}年${day.month}月${day.day}日';
  }
}
