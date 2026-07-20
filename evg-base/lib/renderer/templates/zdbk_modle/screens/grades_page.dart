/// 成绩 · 成绩单 / 主修成绩 / 二三四课堂页（modle_route: score）。
///
/// 照搬 `.reference` 中 scores 相关页面的列表卡片 UI 逻辑；考试安排已拆分到
/// [ExamsPage]（modle_route: exams）。数据来源改为数据中枢
/// （orch://zdbk_transcript / _major_grade / _practice_scores）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:evergreen_base/core/module/module_descriptor.dart';

import '../models.dart';
import '../zdbk_view.dart';

class GradesPage extends ConsumerStatefulWidget {
  final WidgetRef ref;
  final Map<String, DataSourceDescriptor> sources;
  const GradesPage({super.key, required this.ref, required this.sources});

  @override
  ConsumerState<GradesPage> createState() => _GradesPageState();
}

class _GradesPageState extends ConsumerState<GradesPage> {
  Future<Map<String, dynamic>>? _future;
  Map<String, dynamic> _raw = {};

  @override
  void initState() {
    super.initState();
    _future = zdbkResolve(widget.ref, widget.sources);
    _future!.then((m) {
      if (mounted) setState(() => _raw = m);
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
        if (snap.hasError) {
          return zdbkError('加载成绩失败', () {
            setState(() => _future = zdbkResolve(widget.ref, widget.sources));
            _future!.then((m) => mounted ? setState(() => _raw = m) : null);
          });
        }

        final transcript = ZdbkData.grades(
            _raw['transcript'], widget.sources['transcript']?.bindings);
        final major = ZdbkData.grades(
            _raw['major_grade'], widget.sources['major_grade']?.bindings);
        final practice = ZdbkData.practice(
            _raw['practice_scores'], widget.sources['practice_scores']?.bindings);

        if (transcript.isEmpty &&
            major.isEmpty &&
            practice.pt2 == 0 &&
            practice.pt3 == 0 &&
            practice.pt4 == 0) {
          return zdbkEmpty('暂无成绩数据');
        }

        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: zdbkPageHeader(context, '成绩')),
            _section(context, '成绩单', transcript.length, (i) {
              final g = transcript[i];
              return _gradeCard(g.courseName, '成绩 ${g.score}', '绩点 ${g.gpa}',
                  '学分 ${g.credit}', Icons.school);
            }, transcript.length),
            _section(context, '主修成绩', major.length, (i) {
              final g = major[i];
              return _gradeCard(g.courseName, '成绩 ${g.score}', '绩点 ${g.gpa}',
                  '学分 ${g.credit}', Icons.workspace_premium);
            }, major.length),
            _practiceSliver(context, practice),
          ],
        );
      },
    );
  }

  Widget _section(
    BuildContext context,
    String title,
    int count,
    Widget Function(int) itemBuilder,
    int length,
  ) {
    if (length == 0) return const SliverToBoxAdapter(child: SizedBox.shrink());
    return SliverList.list(children: [
      zdbkSectionTitle(context, title, count),
      for (int i = 0; i < length; i++) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: itemBuilder(i),
        ),
      ],
    ]);
  }

  Widget _practiceSliver(BuildContext context, ZdbkPracticeScore p) {
    if (p.pt2 == 0 && p.pt3 == 0 && p.pt4 == 0) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    final theme = Theme.of(context);
    return SliverList.list(children: [
      zdbkSectionTitle(context, '二 / 三 / 四课堂成绩', 3),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _scoreStat('第二课堂', p.pt2),
                _scoreStat('第三课堂', p.pt3),
                _scoreStat('第四课堂', p.pt4),
              ],
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _scoreStat(String label, double v) => Column(
        children: [
          Text(v.toStringAsFixed(1),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      );

  Widget _gradeCard(String title, String line1, String line2, String line3,
      IconData icon) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600))),
            ]),
            const SizedBox(height: 6),
            if (line1.isNotEmpty) _infoRow(Icons.grade, line1),
            if (line2.isNotEmpty) _infoRow(Icons.star, line2),
            if (line3.isNotEmpty) _infoRow(Icons.person, line3),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(children: [
          Icon(icon, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
              child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
        ]),
      );
}
