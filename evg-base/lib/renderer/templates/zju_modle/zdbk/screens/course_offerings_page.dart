/// 开课情况页（modle_route: course_offerings）。
///
/// UI 逻辑照搬 `.reference` 的 course_offerings_screen；数据来源统一改为数据中枢
/// （orch://zdbk_course_offerings）。培养方案已拆分到 [TrainingPlanPage]
/// （modle_route: training_plans）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:evergreen_base/core/module/module_descriptor.dart';

import '../models.dart';
import '../zdbk_view.dart';

class CourseOfferingsPage extends ConsumerStatefulWidget {
  final WidgetRef ref;
  final Map<String, DataSourceDescriptor> sources;
  const CourseOfferingsPage({super.key, required this.ref, required this.sources});

  @override
  ConsumerState<CourseOfferingsPage> createState() => _CourseOfferingsPageState();
}

class _CourseOfferingsPageState extends ConsumerState<CourseOfferingsPage> {
  Future<Map<String, dynamic>>? _future;
  Map<String, dynamic> _raw = {};

  // 开课情况：搜索 + 按类型分组
  final _offerCtrl = TextEditingController();
  String _offerQuery = '';

  // 懒加载
  final ScrollController _scrollCtrl = ScrollController();
  int _displayCount = 20;

  @override
  void initState() {
    super.initState();
    _offerCtrl.addListener(() {
      final newQ = _offerCtrl.text.trim();
      if (newQ != _offerQuery) {
        setState(() { _offerQuery = newQ; _displayCount = 20; });
      }
    });
    _scrollCtrl.addListener(_onScroll);
    _future = zdbkResolve(widget.ref, widget.sources);
    _future!.then((m) {
      if (mounted) setState(() => _raw = m);
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _offerCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    if (pos.pixels >= pos.maxScrollExtent - 100) {
      setState(() => _displayCount += 20);
    }
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
          return zdbkError('加载课程失败', () {
            setState(() => _future = zdbkResolve(widget.ref, widget.sources));
            _future!.then((m) => mounted ? setState(() => _raw = m) : null);
          });
        }

        final offerings = ZdbkData.offerings(
            _raw['course_offerings'], widget.sources['course_offerings']?.bindings);

        if (offerings.isEmpty) {
          return zdbkEmpty('暂无课程数据');
        }

        return CustomScrollView(
          controller: _scrollCtrl,
          slivers: [
            SliverToBoxAdapter(
                child: zdbkPageHeader(context, '课程 · 开课情况')),
            SliverToBoxAdapter(child: _offeringsBody(context, offerings)),
          ],
        );
      },
    );
  }

  // ── 开课情况（搜索 + 按类型分组 + 卡片 + 懒加载）──
  Widget _offeringsBody(
      BuildContext context, List<ZdbkCourseOffering> all) {
    if (all.isEmpty) return const SizedBox.shrink();
    final q = _offerQuery.toLowerCase();
    // 搜索作用于全量数据
    final filtered = q.isEmpty
        ? all
        : all.where((o) =>
            o.courseName.toLowerCase().contains(q) ||
            o.teacher.toLowerCase().contains(q) ||
            o.location.toLowerCase().contains(q) ||
            o.college.toLowerCase().contains(q) ||
            o.major.toLowerCase().contains(q)).toList();

    final byType = <String, List<ZdbkCourseOffering>>{};
    for (final o in filtered) {
      byType.putIfAbsent(o.type.isEmpty ? '其他' : o.type, () => []).add(o);
    }

    final theme = Theme.of(context);
    final children = <Widget>[];
    children.add(zdbkSectionTitle(context, '开课情况', all.length));
    children.add(Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: TextField(
        controller: _offerCtrl,
        decoration: InputDecoration(
          hintText: '搜索课程名称、教师、地点...',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _offerQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () => _offerCtrl.clear())
              : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          filled: true,
          fillColor: theme.colorScheme.surfaceContainerHighest,
        ),
      ),
    ));
    if (filtered.isEmpty) {
      children.add(const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: Text('未找到匹配的课程')),
      ));
    }
    // 懒加载：全量 search/filter，展示分页
    int shown = 0;
    outer:
    for (final entry in byType.entries) {
      children.add(Padding(
        padding: const EdgeInsets.only(left: 16, bottom: 4, top: 6),
        child: Text('${entry.key} (${entry.value.length})',
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
      ));
      for (final o in entry.value) {
        if (shown >= _displayCount) break outer;
        shown++;
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(o.courseName,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  if (o.teacher.isNotEmpty) _row(Icons.person, o.teacher),
                  if (o.schedule.isNotEmpty) _row(Icons.schedule, o.schedule),
                  if (o.location.isNotEmpty) _row(Icons.room, o.location),
                  if (o.credit.isNotEmpty) _row(Icons.star, '${o.credit} 学分'),
                ],
              ),
            ),
          ),
        ));
      }
    }
    // 底部：加载指示器
    final total = filtered.length;
    if (shown < total) {
      children.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text('已显示 $shown / $total 条，下滑加载更多',
              style: theme.textTheme.bodySmall),
        ),
      ));
    } else if (total > 20) {
      children.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text('已显示全部 $total 条',
              style: theme.textTheme.bodySmall),
        ),
      ));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  // ── 共用小组件 ──
  Widget _row(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Row(children: [
          Icon(icon, size: 15,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
              child: Text(text,
                  style: Theme.of(context).textTheme.bodySmall)),
        ]),
      );
}
