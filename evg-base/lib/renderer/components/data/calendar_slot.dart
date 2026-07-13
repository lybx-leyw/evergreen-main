/// 日历 slot——委托 [CalendarWidget] 渲染月历。
///
/// M2 P2 迁移：由 P4 桩升级为真实实现，读取 `config.events` 渲染事件标记，
/// 并支持 dataSource 注入 `{events:[{date,title,color}]}`（替换静态 events）。
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/renderer/data/data_source_slot.dart';
import '../shared/widgets/calendar_widget.dart';

class CalendarSlot extends DataSourceSlot {
  const CalendarSlot({super.key, required super.config});

  @override
  DataSourceSlotState<CalendarSlot> createState() => _CalendarSlotState();
}

class _CalendarSlotState extends DataSourceSlotState<CalendarSlot> {
  @override
  Map<String, dynamic> mergeData(Map<String, dynamic> base, dynamic resolved) {
    final merged = <String, dynamic>{...base};
    if (resolved is List) {
      merged['events'] = resolved;
    } else if (resolved is Map<String, dynamic>) {
      if (resolved['events'] is List) {
        merged['events'] = resolved['events'];
      } else {
        merged.addAll(resolved);
      }
    }
    return merged;
  }

  @override
  Widget buildStatic(Map<String, dynamic> cfg) {
    final events = _parseEvents(cfg['events']);
    return CalendarWidget(events: events);
  }

  List<CalendarEvent> _parseEvents(dynamic raw) {
    final result = <CalendarEvent>[];
    if (raw is! List) return result;
    for (final e in raw) {
      if (e is! Map) continue;
      final date = DateTime.tryParse(e['date']?.toString() ?? '');
      if (date == null) continue;
      result.add(CalendarEvent(
        date: date,
        title: e['title']?.toString() ?? '',
        color: _parseColor(e['color']?.toString()),
      ));
    }
    return result;
  }

  /// 解析 `#RRGGBB` / `#AARRGGBB` 十六进制颜色；无效时返回 null（用默认色）。
  Color? _parseColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    var h = hex.replaceFirst('#', '').trim();
    if (h.length == 6) h = 'FF$h';
    if (h.length != 8) return null;
    final value = int.tryParse(h, radix: 16);
    return value == null ? null : Color(value);
  }
}
