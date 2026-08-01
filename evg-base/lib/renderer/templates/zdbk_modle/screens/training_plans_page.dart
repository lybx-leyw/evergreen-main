/// 培养方案页（modle_route: training_plans）。
///
/// UI 逻辑照搬 `.reference` 的 training_plan_screen；数据来源统一改为数据中枢
/// （orch://zdbk_training_plans）。开课情况已拆分到 [CourseOfferingsPage]
/// （modle_route: course_offerings）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:evergreen_base/core/module/module_descriptor.dart';

import '../models.dart';
import '../zdbk_view.dart';

class TrainingPlanPage extends ConsumerStatefulWidget {
  final WidgetRef ref;
  final Map<String, DataSourceDescriptor> sources;
  const TrainingPlanPage({super.key, required this.ref, required this.sources});

  @override
  ConsumerState<TrainingPlanPage> createState() => _TrainingPlanPageState();
}

class _TrainingPlanPageState extends ConsumerState<TrainingPlanPage> {
  Future<Map<String, dynamic>>? _future;
  Map<String, dynamic> _raw = {};

  // 培养方案：筛选
  String _planCollege = '';
  String _planMajor = '';
  String _planGrade = '';

  // 懒加载
  final ScrollController _scrollCtrl = ScrollController();
  int _displayCount = 20;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _future = zdbkResolve(widget.ref, widget.sources);
    _future!.then((m) {
      if (mounted) setState(() => _raw = m);
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    // 距底部 100px 时触发加载更多
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

        final plans = ZdbkData.plans(
            _raw['training_plans'], widget.sources['training_plans']?.bindings);

        if (plans.isEmpty) {
          return zdbkEmpty('暂无课程数据');
        }

        return CustomScrollView(
          controller: _scrollCtrl,
          slivers: [
            SliverToBoxAdapter(
                child: zdbkPageHeader(context, '课程 · 培养方案')),
            SliverToBoxAdapter(child: _plansBody(context, plans)),
          ],
        );
      },
    );
  }

  // ── 培养方案（筛选 + 卡片 + 详情 + 懒加载）──
  Widget _plansBody(BuildContext context, List<ZdbkTrainingPlan> all) {
    if (all.isEmpty) return const SizedBox.shrink();
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

    // 懒加载：仅渲染前 _displayCount 条，搜索/筛选作用于全量 list。
    final total = list.length;
    final visible = _displayCount.clamp(0, total);
    final displayList = list.take(visible).toList();

    final theme = Theme.of(context);
    final children = <Widget>[];
    children.add(zdbkSectionTitle(context, '培养方案', all.length));
    children.add(Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Wrap(spacing: 6, runSpacing: 6, children: [
        _chip(_planGrade.isNotEmpty ? '${_planGrade}级' : '全部年级',
            () => _showGradePicker(all), _planGrade.isNotEmpty),
        _chip(_planCollege.isNotEmpty ? _planCollege : '学院',
            () => _showOptionPicker('选择学院', colleges,
                (v) => setState(() { _planCollege = v; _displayCount = 20; })),
            _planCollege.isNotEmpty),
        _chip(_planMajor.isNotEmpty ? _planMajor : '专业',
            () => _showOptionPicker('选择专业', majors,
                (v) => setState(() { _planMajor = v; _displayCount = 20; })),
            _planMajor.isNotEmpty),
      ]),
    ));
    children.add(Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Text('${total} 个方案',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    ));
    if (displayList.isEmpty) {
      children.add(const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: Text('未找到符合条件的方案')),
      ));
    }
    for (final p in displayList) {
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
    // 底部：加载指示器
    if (visible < total) {
      children.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text('已显示 $visible / $total 条，下滑加载更多',
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
              setState(() { _planGrade = ''; _displayCount = 20; });
              Navigator.of(ctx).pop();
            },
          ),
          for (final g in grades)
            SimpleDialogOption(
              child: Text('${g}级'),
              onPressed: () {
                setState(() { _planGrade = g; _displayCount = 20; });
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
