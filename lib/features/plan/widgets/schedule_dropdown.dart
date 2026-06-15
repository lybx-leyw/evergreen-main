/// 课表下拉组件 — 展示当日课程。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/timetable_session.dart';
import '../../../core/result.dart';
import '../../zdbk/providers/zdbk_provider.dart';

/// 当日课表可折叠面板。
class ScheduleDropdown extends ConsumerStatefulWidget {
  const ScheduleDropdown({super.key});

  @override
  ConsumerState<ScheduleDropdown> createState() => _ScheduleDropdownState();
}

class _ScheduleDropdownState extends ConsumerState<ScheduleDropdown> {
  bool _expanded = false;

  static const _weekdayNames = [
    '', '周一', '周二', '周三', '周四', '周五', '周六', '周日',
  ];

  @override
  Widget build(BuildContext context) {
    final timetableAsync = ref.watch(zdbkTimetableProvider);
    final today = DateTime.now().weekday; // 1=Mon, matches dayOfWeek

    return timetableAsync.when(
      loading: () => Card(
        child: ListTile(
          leading: const SizedBox(
            width: 24, height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          title: const Text('加载课表...', style: TextStyle(fontSize: 14)),
        ),
      ),
      error: (_, __) => Card(
        child: ListTile(
          leading: const Icon(Icons.error_outline, color: Colors.orange),
          title: const Text('课表加载失败', style: TextStyle(fontSize: 14)),
          trailing: TextButton(
            onPressed: () => ref.invalidate(zdbkTimetableProvider),
            child: const Text('重试'),
          ),
        ),
      ),
      data: (result) {
        final sessions = result.fold(
          (ok) => ok,
          (_) => <TimetableSession>[],
        );
        final todaySessions =
            sessions.where((s) => s.dayOfWeek == today && !s.isEnded).toList();
        final weekday = _weekdayNames[today];

        return Card(
          child: ExpansionTile(
            initiallyExpanded: _expanded,
            onExpansionChanged: (v) => setState(() => _expanded = v),
            leading: const Icon(Icons.today),
            title: Text(
              '今日课程 ($weekday) · ${todaySessions.length}门',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            children: todaySessions.isEmpty
                ? [const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('今日无课 🎉', style: TextStyle(color: Colors.grey)),
                  )]
                : todaySessions.map((s) {
                    final periods =
                        s.periods.isNotEmpty ? '${s.periods.first}-${s.periods.last}节' : '';
                    return ListTile(
                      dense: true,
                      title: Text(s.courseName, style: const TextStyle(fontSize: 13)),
                      subtitle: Text(
                        [periods, s.location, s.teacher]
                            .where((e) => e != null && e.isNotEmpty)
                            .join(' · '),
                        style: const TextStyle(fontSize: 12),
                      ),
                    );
                  }).toList(),
          ),
        );
      },
    );
  }
}
