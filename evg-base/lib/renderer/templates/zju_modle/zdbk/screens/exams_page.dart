/// 考试 · 考试安排页（modle_route: exams）。
///
/// 照搬 `.reference` 中 exams 相关页面的卡片 UI 逻辑；数据来源改为数据中枢
/// （orch://zdbk_exams）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:evergreen_base/core/module/module_descriptor.dart';

import '../models.dart';
import '../zdbk_view.dart';

class ExamsPage extends ConsumerStatefulWidget {
  final WidgetRef ref;
  final Map<String, DataSourceDescriptor> sources;
  const ExamsPage({super.key, required this.ref, required this.sources});

  @override
  ConsumerState<ExamsPage> createState() => _ExamsPageState();
}

class _ExamsPageState extends ConsumerState<ExamsPage> {
  Future<Map<String, dynamic>>? _future;
  List<ZdbkExamItem> _items = [];

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
        setState(() =>
            _items = ZdbkData.exams(m['exams'], widget.sources['exams']?.bindings));
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
        final raw = snap.data?['exams'];
        if (snap.hasError || (_items.isEmpty && raw == null)) {
          return zdbkError('加载考试安排失败', _load);
        }
        if (_items.isEmpty) {
          return zdbkEmpty('暂无考试安排');
        }

        final byTerm = <String, List<ZdbkExamItem>>{};
        for (final e in _items) {
          byTerm.putIfAbsent(e.term.isEmpty ? '未排学期' : e.term, () => []).add(e);
        }

        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: zdbkPageHeader(context, '考试安排')),
            for (final entry in byTerm.entries) ...[
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
                    child: _examCard(e),
                  ),
                ),
            ],
          ],
        );
      },
    );
  }

  Widget _examCard(ZdbkExamItem e) {
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
            if (e.time.isNotEmpty) _row(Icons.schedule, e.time),
            if (e.location.isNotEmpty) _row(Icons.room, e.location),
            if (e.teacher.isNotEmpty) _row(Icons.person, e.teacher),
            if (e.seatNo.isNotEmpty) _row(Icons.event_seat, '座位号 $e.seatNo'),
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
