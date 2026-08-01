/// 课表 · 按星期分组的课表页（modle_route: timetable）。
///
/// 课表按周几分组展示（原始 `kcb` blob 已解析为 课程名/教师/地点/考试时间）。
/// 数据来源改为数据中枢（orch://zdbk_timetable）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:evergreen_base/core/module/module_descriptor.dart';

import '../models.dart';
import '../zdbk_view.dart';

class TimetablePage extends ConsumerStatefulWidget {
  final WidgetRef ref;
  final Map<String, DataSourceDescriptor> sources;
  const TimetablePage({super.key, required this.ref, required this.sources});

  @override
  ConsumerState<TimetablePage> createState() => _TimetablePageState();
}

class _TimetablePageState extends ConsumerState<TimetablePage> {
  Future<Map<String, dynamic>>? _future;
  List<ZdbkTimetableEntry> _list = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _future = zdbkResolve(widget.ref, widget.sources);
    });
    _future!.then((m) {
      if (mounted) {
        setState(() => _list =
            ZdbkData.timetable(m['timetable'], widget.sources['timetable']?.bindings));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final raw = snap.data?['timetable'];
        if (snap.hasError || (_list.isEmpty && raw == null)) {
          return zdbkError('加载课表失败', _load);
        }
        if (_list.isEmpty) {
          return zdbkEmpty('暂无课表数据');
        }

        final byDay = <String, List<ZdbkTimetableEntry>>{};
        for (final e in _list) {
          byDay.putIfAbsent(e.weekdayLabel, () => []).add(e);
        }

        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: zdbkPageHeader(context, '课表')),
            for (final entry in byDay.entries) ...[
              SliverToBoxAdapter(
                  child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(entry.key,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
              )),
              for (final e in entry.value)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                    child: _courseCard(e),
                  ),
                ),
            ],
          ],
        );
      },
    );
  }

  Widget _courseCard(ZdbkTimetableEntry e) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(e.courseName,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            if (e.teacher.isNotEmpty) _row(Icons.person, e.teacher),
            if (e.location.isNotEmpty) _row(Icons.room, e.location),
            if (e.term.isNotEmpty) _row(Icons.schedule, e.term),
            if (e.examTime.isNotEmpty) _row(Icons.event, e.examTime),
          ],
        ),
      ),
    );
  }

  Widget _row(IconData icon, String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(children: [
        Icon(icon, size: 15, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
      ]),
    );
  }
}
