/// 课程 · 开课情况 / 培养方案页（modle_route: courses）。
///
/// 开课情况、培养方案的 UI 逻辑照搬 `.reference` 的
/// course_offerings_screen / training_plan_screen；课表已拆分到
/// [TimetablePage]（modle_route: timetable）。数据来源统一改为数据中枢
/// （orch://zdbk_course_offerings / _training_plans）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:evergreen_base/core/module/module_descriptor.dart';

import '../models.dart';
import '../zdbk_view.dart';

class CoursesPage extends ConsumerStatefulWidget {
  final WidgetRef ref;
  final Map<String, DataSourceDescriptor> sources;
  const CoursesPage({super.key, required this.ref, required this.sources});

  @override
  ConsumerState<CoursesPage> createState() => _CoursesPageState();
}

class _CoursesPageState extends ConsumerState<CoursesPage> {
  Future<Map<String, dynamic>>? _future;
  Map<String, dynamic> _raw = {};

  // 开课情况：搜索 + 按类型分组
  final _offerCtrl = TextEditingController();
  String _offerQuery = '';
  // 培养方案：筛选
  String _planCollege = '';
  String _planMajor = '';
  String _planGrade = '';

  @override
  void initState() {
    super.initState();
    _offerCtrl.addListener(() => setState(() => _offerQuery = _offerCtrl.text.trim()));
    _future = zdbkResolve(widget.ref, widget.sources);
    _future!.then((m) {
      if (mounted) setState(() => _raw = m);
    });
  }

  @override
  void dispose() {
    _offerCtrl.dispose();
    super.dispose();
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
        final plans = ZdbkData.plans(
            _raw['training_plans'], widget.sources['training_plans']?.bindings);

        if (offerings.isEmpty && plans.isEmpty) {
          return zdbkEmpty('暂无课程数据');
        }

        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
                child: zdbkPageHeader(context, '课程 · 开课情况与培养方案')),
            _offeringsSliver(context, offerings),
            _plansSliver(context, plans),
          ],
        );
      },
    );
  }

  // ── 开课情况（照搬 reference：搜索 + 按类型分组 + 卡片）──
  Widget _offeringsSliver(
      BuildContext context, List<ZdbkCourseOffering> all) {
    if (all.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
    final q = _offerQuery.toLowerCase();
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
      children.add(const SliverToBoxAdapter(child: SizedBox.shrink()) as Widget);
      children.add(const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: Text('未找到匹配的课程')),
      ));
    }
    const _cap = 300;
    int shown = 0;
    for (final entry in byType.entries) {
      children.add(Padding(
        padding: const EdgeInsets.only(left: 16, bottom: 4, top: 6),
        child: Text('${entry.key} (${entry.value.length})',
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
      ));
      for (final o in entry.value) {
        if (shown >= _cap) break;
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
    if (filtered.length > _cap) {
      children.add(Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
            child: Text('仅显示前 $_cap 条，请输入关键词精确搜索',
                style: theme.textTheme.bodySmall)),
      ));
    }
    return SliverList.list(children: children);
  }

  // ── 培养方案（照搬 reference：筛选 + 卡片 + 详情）──
  Widget _plansSliver(BuildContext context, List<ZdbkTrainingPlan> all) {
    if (all.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
    var list = all;
    if (_planGrade.isNotEmpty) {
      list = list.where((p) => p.grade == _planGrade).toList();
    }
    if (_planCollege.isNotEmpty) {
      list = list.where((p) => p.college == _planCollege).toList();
    }
    if (_planMajor.isNotEmpty) {
      list = list.where((p) => p.major == _planMajor).toList();
    }

    final colleges = all
        .map((p) => p.college)
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final majors = (all.where((p) => p.college == _planCollege || _planCollege.isEmpty)
            .map((p) => p.major)
            .where((m) => m.isNotEmpty)
            .toSet()
            .toList())
      ..sort();

    final theme = Theme.of(context);
    final children = <Widget>[];
    children.add(zdbkSectionTitle(context, '培养方案', all.length));
    // 修复：筛选 chips 内边距统一为 16px（原先 12px，与其余区块不对齐）。
    children.add(Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Wrap(spacing: 6, runSpacing: 6, children: [
        _chip(_planGrade.isNotEmpty ? '${_planGrade}级' : '全部年级',
            () => _showGradePicker(all), _planGrade.isNotEmpty),
        _chip(_planCollege.isNotEmpty ? _planCollege : '学院',
            () => _showOptionPicker('选择学院', colleges,
                (v) => setState(() => _planCollege = v)),
            _planCollege.isNotEmpty),
        _chip(_planMajor.isNotEmpty ? _planMajor : '专业',
            () => _showOptionPicker('选择专业', majors,
                (v) => setState(() => _planMajor = v)),
            _planMajor.isNotEmpty),
      ]),
    ));
    children.add(Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Text('${list.length} 个方案',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    ));
    if (list.isEmpty) {
      children.add(const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: Text('未找到符合条件的方案')),
      ));
    }
    for (final p in list) {
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Card(
          margin: EdgeInsets.zero,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _openPlanDetail(context, p),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.planName,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  if (p.major.isNotEmpty) _row(Icons.school, p.major),
                  if (p.college.isNotEmpty) _row(Icons.domain, p.college),
                  if (p.grade.isNotEmpty) _row(Icons.people, '${p.grade}级'),
                  if (p.lengthYears.isNotEmpty)
                    _row(Icons.cast_for_education, '学制 ${p.lengthYears} 年'),
                  if (p.minCredits.isNotEmpty)
                    _row(Icons.star, '最低 ${p.minCredits} 学分'),
                ],
              ),
            ),
          ),
        ),
      ));
    }
    return SliverList.list(children: children);
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

  Widget _chip(String label, VoidCallback onTap, bool active) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: active
                ? Theme.of(context).colorScheme.primaryContainer
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: Theme.of(context)
                    .colorScheme
                    .outlineVariant
                    .withValues(alpha: 0.3)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(
                child: Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                        color: active
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurface))),
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down,
                size: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ]),
        ),
      );

  void _showGradePicker(List<ZdbkTrainingPlan> all) {
    final grades = all
        .map((p) => p.grade)
        .where((g) => g.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择年级'),
        children: [
          SimpleDialogOption(
            child: const Text('全部年级'),
            onPressed: () {
              setState(() => _planGrade = '');
              Navigator.of(ctx).pop();
            },
          ),
          for (final g in grades)
            SimpleDialogOption(
              child: Text('${g}级'),
              onPressed: () {
                setState(() => _planGrade = g);
                Navigator.of(ctx).pop();
              },
            ),
        ],
      ),
    );
  }

  void _showOptionPicker(String title, List<String> options,
      void Function(String) onSelected) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        final q = ctrl.text.trim().toLowerCase();
        final f = q.isEmpty
            ? options
            : options.where((o) => o.toLowerCase().contains(q)).toList();
        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: Column(children: [
              TextField(
                controller: ctrl,
                decoration: const InputDecoration(
                  hintText: '搜索...',
                  prefixIcon: Icon(Icons.search, size: 20),
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  isDense: true,
                ),
                onChanged: (_) => setD(() {}),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(children: [
                  ListTile(
                    title: const Text('全部',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    dense: true,
                    onTap: () {
                      onSelected('');
                      Navigator.of(ctx).pop();
                    },
                  ),
                  for (final opt in f)
                    ListTile(
                      title: Text(opt),
                      dense: true,
                      onTap: () {
                        onSelected(opt);
                        Navigator.of(ctx).pop();
                      },
                    ),
                  if (f.isEmpty && q.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('未找到'),
                    ),
                ]),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('取消')),
          ],
        );
      }),
    );
  }

  void _openPlanDetail(BuildContext context, ZdbkTrainingPlan p) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(p.planName),
        content: SizedBox(
          width: double.maxFinite,
          height: 420,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (p.college.isNotEmpty) _row(Icons.domain, p.college),
                if (p.grade.isNotEmpty) _row(Icons.people, '${p.grade}级'),
                if (p.lengthYears.isNotEmpty)
                  _row(Icons.cast_for_education, '学制 ${p.lengthYears} 年'),
                if (p.minCredits.isNotEmpty)
                  _row(Icons.star, '最低 ${p.minCredits} 学分'),
                if (p.totalCredits.isNotEmpty)
                  _row(Icons.credit_card, '总学分要求 ${p.totalCredits}'),
                if (p.category.isNotEmpty)
                  _row(Icons.category, p.category),
                if (p.campus.isNotEmpty) _row(Icons.location_on, p.campus),
                const SizedBox(height: 10),
                const Divider(),
                if (p.remarks.isNotEmpty)
                  Text(p.remarks,
                      style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('关闭')),
        ],
      ),
    );
  }
}
