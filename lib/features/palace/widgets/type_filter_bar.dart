/// Palace 事件类型过滤栏。
library;

import 'package:flutter/material.dart';

import '../../../core/palace/models/consciousness_event.dart' show EventType;

/// 每种类型的显示配置。
const _typeConfig = <EventType, _TypeMeta>{
  EventType.thought: _TypeMeta('💡', '想法'),
  EventType.lesson: _TypeMeta('📖', '教训'),
  EventType.decision: _TypeMeta('🎯', '决策'),
  EventType.reflection: _TypeMeta('🪞', '反思'),
  EventType.connection: _TypeMeta('🔗', '连接'),
  EventType.milestone: _TypeMeta('🏔️', '节点'),
};

class _TypeMeta {
  final String icon;
  final String label;
  const _TypeMeta(this.icon, this.label);
}

/// 六种事件类型的过滤 Tab 栏。
class TypeFilterBar extends StatelessWidget {
  final EventType? selected;
  final ValueChanged<EventType?> onChanged;

  const TypeFilterBar({
    super.key,
    this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final entries = _typeConfig.entries.toList();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          // "全部"按钮
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: FilterChip(
              label: const Text('全部'),
              selected: selected == null,
              onSelected: (_) => onChanged(null),
            ),
          ),
          for (final entry in entries)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: FilterChip(
                label: Text('${entry.value.icon} ${entry.value.label}'),
                selected: selected == entry.key,
                onSelected: (_) => onChanged(entry.key),
              ),
            ),
        ],
      ),
    );
  }
}
