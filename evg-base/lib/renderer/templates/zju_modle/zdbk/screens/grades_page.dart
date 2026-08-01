/// 成绩 · 成绩单 / 主修成绩 / 二三四课堂页（modle_route: score）。
///
/// 渲染优化（参考 `.reference/.../features/scores/screens/scores_screen.dart`
/// 的 GPA Dashboard 设计，并在本仓库约束下「超越」）：
///  - 复刻：保研/出国策略切换、四制 GPA 汇总卡 + 进度条、GPA 趋势图、
///    成绩分布图、搜索 + 学期筛选、可滚动成绩列表。
///  - 超越：`.reference` 依赖 `fl_chart`；本仓库未引入该依赖，故两张图均用
///    `CustomPaint` / `Container` 手绘，**零新增依赖**，更轻、可控、主题自适应。
///  - 数据取数仍走数据中枢（orch://zdbk_transcript / _major_grade / _practice_scores）。
library;

import 'dart:math' show max, min;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:evergreen_base/core/module/module_descriptor.dart';

import '../models.dart';
import '../zdbk_view.dart';

/// 五分制 → 显示色（越高越绿，越低越红）。
Color scoreColor(double fivePoint) {
  if (fivePoint >= 4.5) return Colors.green.shade600;
  if (fivePoint >= 3.5) return Colors.lightGreen.shade700;
  if (fivePoint >= 2.5) return Colors.orange.shade700;
  if (fivePoint >= 1.5) return Colors.deepOrange;
  if (fivePoint > 0) return Colors.red.shade600;
  return Colors.grey;
}

/// 成绩分布柱状图色（索引即五分制区间 0-1,1-2,2-3,3-4,4-5）。
Color _binColor(int idx) {
  switch (idx) {
    case 4:
      return Colors.green;
    case 3:
      return Colors.lightGreen;
    case 2:
      return Colors.orange;
    case 1:
      return Colors.deepOrange;
    default:
      return Colors.red;
  }
}

const List<String> _binLabels = ['0-1', '1-2', '2-3', '3-4', '4-5'];

/// 单门课程的中间态（从 [ZdbkGradeItem] 适配，便于复用 reference 的 GPA 算法）。
class _GpaEntry {
  final String courseName;
  final String courseNo;
  final String original; // 原始成绩字符串（cj）：'95' / '优' / '良好' ...
  final double fivePoint; // 五分制（jd）
  final double credit; // 学分（xf）
  final double hundredPoint; // 百分制（由 cj 映射）
  final bool isMajor;

  const _GpaEntry({
    required this.courseName,
    this.courseNo = '',
    this.original = '',
    required this.fivePoint,
    required this.credit,
    required this.hundredPoint,
    this.isMajor = false,
  });

  /// 是否排除出 GPA 计算（照搬 reference 的 isExcludedFromGpa）。
  bool get excludedFromGpa =>
      original == '弃修' ||
      original == '待录' ||
      original == '缓考' ||
      original == '无效' ||
      original == '合格' ||
      original == '不合格' ||
      courseNo.contains('xtwkc') ||
      credit <= 0;

  /// 已获学分（排除弃修/待录/缓考/无效）。
  double get earnedCredit {
    final included = original != '弃修' &&
        original != '待录' &&
        original != '缓考' &&
        original != '无效';
    return (included && (fivePoint != 0 || courseNo.contains('xtwkc')))
        ? credit
        : 0.0;
  }

  /// 四分制（4.3 标准）：>4.0 部分按映射表转换，其余直透。
  double get fourPoint {
    if (fivePoint > 4.0) {
      final m = {5.0: 4.3, 4.8: 4.2, 4.5: 4.1, 4.2: 4.0};
      return m[fivePoint] ?? 4.0;
    }
    return fivePoint;
  }

  /// 四分制（4.0 传统）：>4.0 封顶 4.0。
  double get fourPointLegacy => fivePoint > 4.0 ? 4.0 : fivePoint;

  /// 真实课程主键（去除重修后缀，使同一课程不同尝试归并）。
  String get realId {
    final match = RegExp(r'(\(.*\)-.*?)-.*').firstMatch(courseNo);
    var key = match?.group(1);
    key ??= courseNo.isNotEmpty ? courseNo : courseName;
    return key;
  }
}

/// 把 [ZdbkGradeItem]（字段均为字符串）适配为 [_GpaEntry]（数值 + 派生字段）。
_GpaEntry _toEntry(ZdbkGradeItem g, bool isMajor) => _GpaEntry(
      courseName: g.courseName,
      courseNo: g.courseNo,
      original: g.score,
      fivePoint: double.tryParse(g.gpa) ?? 0,
      credit: double.tryParse(g.credit) ?? 0,
      hundredPoint: _toHundredPoint(g.score),
      isMajor: isMajor,
    );

/// 原始成绩字符串 → 百分制（照搬 reference 的 _toHundredPoint 映射）。
double _toHundredPoint(String s) {
  if (s.isEmpty) return 0;
  const map = <String, int>{
    '优秀': 90,
    '良好': 80,
    '中等': 70,
    '及格': 60,
    '合格': 75,
    '不合格': 0,
    '不及格': 0,
    '弃修': 0,
    '缺考': 0,
    '缓考': 0,
    '待录': 0,
    '无效': 0,
    'A+': 95,
    'A': 90,
    'A-': 87,
    'B+': 83,
    'B': 80,
    'B-': 77,
    'C+': 73,
    'C': 70,
    'C-': 67,
    'D': 60,
    'F': 0,
  };
  if (map.containsKey(s)) return map[s]!.toDouble();
  final num = double.tryParse(s);
  if (num != null) return num.round().toDouble();
  final m = RegExp(r'(\d+)').firstMatch(s);
  return m != null ? (int.tryParse(m.group(1)!) ?? 0).toDouble() : 0.0;
}

/// 四制 GPA 汇总（照搬 reference 的 GpaCalculator.calculateGpa）。
({double five, double four, double fourLegacy, double hundred, double credits})
    _computeGpa(List<_GpaEntry> grades) {
  final earned = grades.fold(0.0, (s, g) => s + g.earnedCredit);
  final filtered = grades.where((g) => !g.excludedFromGpa).toList();
  if (filtered.isEmpty) {
    return (five: 0, four: 0, fourLegacy: 0, hundred: 0, credits: earned);
  }
  double totalCredit = 0, w5 = 0, w4 = 0, wL = 0, wH = 0;
  for (final g in filtered) {
    totalCredit += g.credit;
    w5 += g.fivePoint * g.credit;
    w4 += g.fourPoint * g.credit;
    wL += g.fourPointLegacy * g.credit;
    wH += g.hundredPoint * g.credit;
  }
  return (
    five: totalCredit > 0 ? w5 / totalCredit : 0,
    four: totalCredit > 0 ? w4 / totalCredit : 0,
    fourLegacy: totalCredit > 0 ? wL / totalCredit : 0,
    hundred: totalCredit > 0 ? wH / totalCredit : 0,
    credits: earned,
  );
}

/// 按真实课程主键归并，'first' 取首修（保研）/ 'highest' 取最高分（出国）。
List<_GpaEntry> _pickStrategy(List<_GpaEntry> grades, String strategy) {
  final groups = <String, List<_GpaEntry>>{};
  for (final g in grades) {
    groups.putIfAbsent(g.realId, () => []).add(g);
  }
  if (strategy == 'highest') {
    return groups.values
        .map((grp) => grp.reduce((a, b) => a.hundredPoint >= b.hundredPoint ? a : b))
        .toList();
  }
  return groups.values.map((grp) => grp.first).toList();
}

/// 从选课课号（xkkh 形如 `(2024-2025-1)-CS101-001`）提取学期。
String? _extractSemester(String courseNo) {
  final m = RegExp(r'\(([^)]+)\)').firstMatch(courseNo);
  return m?.group(1);
}

String _displaySemester(String s) {
  final parts = s.split('-');
  if (parts.length >= 3) return '${parts[0]}-${parts[1]} 第${parts[2]}学期';
  return s;
}

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

  String _strategy = 'first'; // 'first' 保研 / 'highest' 出国
  String? _selectedSemester;
  String _searchQuery = '';
  bool _sortAsc = false; // false=绩点降序(高→低) / true=绩点升序(低→高)
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _future = zdbkResolve(widget.ref, widget.sources);
    _future!.then((m) {
      if (mounted) setState(() => _raw = m);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Map<String, String>? _bindings(String name) =>
      widget.sources[name]?.bindings;

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

        final transcript =
            ZdbkData.grades(_raw['transcript'], _bindings('transcript'));
        final major =
            ZdbkData.grades(_raw['major_grade'], _bindings('major_grade'));
        final practice = ZdbkData.practice(
            _raw['practice_scores'], _bindings('practice_scores'));

        final all = <_GpaEntry>[
          for (final g in transcript) _toEntry(g, false),
          for (final g in major) _toEntry(g, true),
        ];

        if (all.isEmpty &&
            practice.pt2 == 0 &&
            practice.pt3 == 0 &&
            practice.pt4 == 0) {
          return zdbkEmpty('暂无成绩数据');
        }

        // ── GPA 计算 + 学期列表 + 筛选 ──
        final picked = _pickStrategy(all, _strategy);
        final gpa = _computeGpa(picked);

        final semesters = picked
            .map((g) => _extractSemester(g.courseNo))
            .where((s) => s != null)
            .cast<String>()
            .toSet()
            .toList()
          ..sort();

        var displayed = picked;
        if (_selectedSemester != null) {
          displayed = displayed
              .where((g) => _extractSemester(g.courseNo) == _selectedSemester)
              .toList();
        }
        if (_searchQuery.isNotEmpty) {
          final q = _searchQuery.toLowerCase();
          displayed = displayed
              .where((g) =>
                  g.courseName.toLowerCase().contains(q) ||
                  g.original.toLowerCase().contains(q))
              .toList();
        }
        // 按绩点（五分制）升降序。
        displayed.sort((a, b) => _sortAsc
            ? a.fivePoint.compareTo(b.fivePoint)
            : b.fivePoint.compareTo(a.fivePoint));

        final theme = Theme.of(context);

        // ── 固定筛选栏（Pin 在顶部）──
        final filterBar = Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'first', label: Text('保研(首修)')),
                  ButtonSegment(value: 'highest', label: Text('出国(最高)')),
                ],
                selected: {_strategy},
                onSelectionChanged: (s) =>
                    setState(() => _strategy = s.first),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    hintText: '搜索课程',
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    prefixIcon: Icon(Icons.search, size: 18),
                  ),
                  onChanged: (v) =>
                      setState(() => _searchQuery = v.trim()),
                ),
              ),
              IconButton(
                icon: Icon(_sortAsc ? Icons.arrow_upward : Icons.arrow_downward),
                tooltip: _sortAsc ? '绩点升序' : '绩点降序',
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => _sortAsc = !_sortAsc),
              ),
              if (semesters.isNotEmpty) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    isExpanded: true,
                    value: _selectedSemester,
                    decoration: const InputDecoration(
                      labelText: '学期',
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: [
                      const DropdownMenuItem(
                          value: null, child: Text('全部')),
                      ...semesters.map((s) => DropdownMenuItem(
                          value: s,
                          child: Text(_displaySemester(s),
                              style: const TextStyle(fontSize: 13)))),
                    ],
                    onChanged: (v) =>
                        setState(() => _selectedSemester = v),
                  ),
                ),
              ],
              if (_selectedSemester != null)
                TextButton(
                  onPressed: () => setState(() => _selectedSemester = null),
                  child: const Text('清除筛选'),
                ),
            ],
          ),
        );

        // ── GPA 汇总卡 ──
        final gpaCards = Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          child: Column(
            children: [
              Row(children: [
                _gpaCard('五分制', gpa.five, 5.0),
                const SizedBox(width: 10),
                _gpaCard('四分制(4.3)', gpa.four, 4.3),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                _gpaCard('四分制(4.0)', gpa.fourLegacy, 4.0),
                const SizedBox(width: 10),
                _gpaCard('百分制', gpa.hundred, 100.0),
              ]),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    Text('已获得学分: ${gpa.credits.toStringAsFixed(1)}',
                        style: theme.textTheme.bodySmall),
                    const Spacer(),
                    Text('共 ${picked.length} 门',
                        style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        );

        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: zdbkPageHeader(context, '成绩')),
            SliverPersistentHeader(
              pinned: true,
              delegate: _PinnedHeaderDelegate(child: filterBar, height: 60),
            ),
            SliverToBoxAdapter(child: gpaCards),
            if (semesters.length >= 2)
              SliverToBoxAdapter(
                  child: _GpaTrendChart(grades: picked)),
            SliverToBoxAdapter(child: _GradeDistChart(grades: picked)),
            _practiceSliver(context, practice),
            displayed.isEmpty
                ? const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.grade_outlined,
                                size: 48, color: Colors.grey),
                            SizedBox(height: 8),
                            Text('无匹配成绩',
                                style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      ),
                    ),
                  )
                : SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final g in displayed) _gradeTile(g),
                      ],
                    ),
                  ),
          ],
        );
      },
    );
  }

  Widget _gpaCard(String label, double value, double max) {
    final theme = Theme.of(context);
    final ratio = (value / max).clamp(0.0, 1.0);
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Text(label, style: theme.textTheme.bodySmall),
              const SizedBox(height: 6),
              Text(value.toStringAsFixed(2),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: scoreColor(ratio * 5),
                  )),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: ratio,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _gradeTile(_GpaEntry g) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      child: ListTile(
        title: Text(g.courseName),
        subtitle: Text(
            '${g.credit.toStringAsFixed(1)} 学分${g.isMajor ? ' · 主修' : ''}'),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(g.original.isEmpty ? '—' : g.original,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: scoreColor(g.fivePoint))),
            Text('${g.fivePoint.toStringAsFixed(2)} / 5.0',
                style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _practiceSliver(BuildContext context, ZdbkPracticeScore p) {
    if (p.pt2 == 0 && p.pt3 == 0 && p.pt4 == 0) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    final theme = Theme.of(context);
    // SliverList 的孩子必须是 sliver；整段 box 内容用 SliverToBoxAdapter(Column) 包裹。
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
        ],
      ),
    );
  }

  Widget _scoreStat(String label, double v) => Column(
        children: [
          Text(v.toStringAsFixed(1),
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      );
}

/// Pin 在顶部的筛选栏代理（与 CustomScrollView 一体滚动，比 reference 的
/// 外层 Column 更紧凑）。
class _PinnedHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double height;
  const _PinnedHeaderDelegate({required this.child, this.height = 60});

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    final bg = Theme.of(context).scaffoldBackgroundColor;
    return Container(
      color: bg,
      alignment: Alignment.centerLeft,
      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant _PinnedHeaderDelegate old) =>
      old.child != child || old.height != height;
}

/// GPA 趋势折线图（手绘，零依赖；reference 用 fl_chart）。
class _GpaTrendChart extends StatelessWidget {
  final List<_GpaEntry> grades;
  const _GpaTrendChart({required this.grades});

  @override
  Widget build(BuildContext context) {
    final bySem = <String, List<_GpaEntry>>{};
    for (final g in grades) {
      final s = _extractSemester(g.courseNo);
      if (s != null) bySem.putIfAbsent(s, () => []).add(g);
    }
    final sems = bySem.keys.toList()..sort();
    if (sems.length < 2) return const SizedBox.shrink();

    final values = <double>[];
    final labels = <String>[];
    for (final s in sems) {
      final list = bySem[s]!.where((g) => !g.excludedFromGpa).toList();
      if (list.isEmpty) continue;
      // 学期均绩：按学分加权平均五分制绩点（均绩 = Σ(绩点×学分) / Σ学分）。
      double totalCredit = 0, weighted = 0;
      for (final g in list) {
        totalCredit += g.credit;
        weighted += g.fivePoint * g.credit;
      }
      final avg = totalCredit > 0 ? weighted / totalCredit : 0.0;
      values.add(double.parse(avg.toStringAsFixed(2)));
      labels.add(s.split('-').length >= 2 ? s.split('-')[1] : s);
    }
    if (values.length < 2) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Text('学期均绩变化',
              style: theme.textTheme.titleSmall),
        ),
        SizedBox(
          height: 160,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
            child: CustomPaint(
              size: Size.infinite,
              painter: _TrendPainter(
                values: values,
                labels: labels,
                lineColor: theme.colorScheme.primary,
                dotColor: theme.colorScheme.primary,
                gridColor:
                    theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
                labelColor: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TrendPainter extends CustomPainter {
  final List<double> values; // 五分制 0..5，按学期升序
  final List<String> labels;
  final Color lineColor;
  final Color dotColor;
  final Color gridColor;
  final Color labelColor;

  const _TrendPainter({
    required this.values,
    required this.labels,
    required this.lineColor,
    required this.dotColor,
    required this.gridColor,
    required this.labelColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    const padL = 28.0, padR = 12.0, padT = 10.0, padB = 22.0;
    final w = size.width - padL - padR;
    final h = size.height - padT - padB;
    if (w <= 0 || h <= 0) return;

    final maxV = values.reduce(max);
    final minV = values.reduce(min);
    final lo = (minV - 0.5).clamp(0.0, 5.0);
    final hi = (maxV + 0.5).clamp(0.0, 5.0);
    final span = (hi - lo) > 0 ? (hi - lo) : 1.0;

    double yOf(double v) => padT + h * (1 - (v - lo) / span);
    double xOf(int i) =>
        padL + w * (values.length == 1 ? 0.5 : i / (values.length - 1));

    // 横向网格线（0/2.5/5 五分制参考线）
    final grid = Paint()..color = gridColor..strokeWidth = 1;
    for (final ref in [0.0, 2.5, 5.0]) {
      if (ref < lo || ref > hi) continue;
      final y = yOf(ref);
      canvas.drawLine(Offset(padL, y), Offset(padL + w, y), grid);
    }

    // 折线
    final line = Paint()
      ..color = lineColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = xOf(i), y = yOf(values[i]);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, line);

    // 数据点 + 标签
    final dot = Paint()..color = dotColor;
    final ring = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (var i = 0; i < values.length; i++) {
      final x = xOf(i), y = yOf(values[i]);
      canvas.drawCircle(Offset(x, y), 3.5, dot);
      canvas.drawCircle(Offset(x, y), 3.5, ring);
      tp.text = TextSpan(
        text: labels[i],
        style: TextStyle(fontSize: 9, color: labelColor),
      );
      tp.layout();
      tp.paint(canvas, Offset(x - tp.width / 2, padT + h + 4));
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) =>
      old.values != values ||
      old.labels != labels ||
      old.lineColor != lineColor ||
      old.labelColor != labelColor;
}

/// 成绩分布柱状图（手绘，零依赖；reference 用 fl_chart）。
class _GradeDistChart extends StatelessWidget {
  final List<_GpaEntry> grades;
  const _GradeDistChart({required this.grades});

  @override
  Widget build(BuildContext context) {
    final bins = [0, 0, 0, 0, 0];
    for (final g in grades) {
      if (g.excludedFromGpa) continue;
      final idx = g.fivePoint.toInt().clamp(0, 4);
      bins[idx]++;
    }
    final maxC = bins.reduce(max).toDouble();
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child:
              Text('成绩分布', style: theme.textTheme.titleSmall),
        ),
        SizedBox(
          height: 150,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < 5; i++)
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text('${bins[i]}',
                            style: theme.textTheme.bodySmall),
                        const SizedBox(height: 4),
                        Expanded(
                          child: FractionallySizedBox(
                            heightFactor: maxC > 0 ? bins[i] / maxC : 0,
                            alignment: Alignment.bottomCenter,
                            child: Container(
                              width: 18,
                              decoration: BoxDecoration(
                                color: _binColor(i),
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(4),
                                  topRight: Radius.circular(4),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(_binLabels[i],
                            style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
