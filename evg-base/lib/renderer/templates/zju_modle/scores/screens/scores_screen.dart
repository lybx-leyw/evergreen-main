/// 成绩与 GPA 仪表盘（zju / scores）。
///
/// B3-scores（2026-08-12）自参考工程
/// `cp_evergreen_push/lib/features/scores/screens/scores_screen.dart` 移植，改造点：
/// - 去 Scaffold/AppBar（evg-base 桌面规范：模块区无 per-module AppBar，页面自绘标题头）；
/// - 数据不再走 Riverpod `zdbkEverythingProvider`，改经数据中枢
///   `orch.fastReadByName('zju_scores')`（fetcher 已算好 domestic/abroad GPA 随 JSON 缓存）；
/// - `Grade`→`ZjuGrade`、`GpaCalculator`→`ZjuGpaCalculator`、`AppTheme`→`ZjuScoreColors`；
/// - `Result`/`LoadingWidget`/`ErrorCard`/`EmptyState`/`FreshnessBadge` 按 evg-base
///   courses 同款模式内联（load/error/empty 三态）；
/// - GPA 趋势折线图 + 成绩分布柱状图（fl_chart）原样保留。
library;

import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:evergreen_base/providers.dart' show dataOrchestratorProvider;

import '../../shared/models/zju_grade.dart';
import '../../shared/utils/zju_gpa_calculator.dart';
import '../../shared/utils/zju_theme_colors.dart';

/// 成绩与 GPA 主视图。
class ScoresView extends ConsumerStatefulWidget {
  const ScoresView({super.key});

  @override
  ConsumerState<ScoresView> createState() => _ScoresViewState();
}

class _ScoresViewState extends ConsumerState<ScoresView> {
  String _strategy = 'first'; // 'first' 保研（首次）/ 'highest' 出国（最高）
  String? _selectedSemester;
  String _searchQuery = '';
  final _searchController = TextEditingController();
  Future<Map<String, dynamic>?>? _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 经数据中枢拉取（内存快读 → 磁盘/网络）。
  ///
  /// 注：`typeByName` 返回 `DataType<dynamic>`，无法直接传 `fastRead<Map>`，
  /// 故用字符串版 `fastReadByName` / `getByName`（返回 dynamic 再 cast）。
  Future<Map<String, dynamic>?> _fetch() async {
    final orch = ref.read(dataOrchestratorProvider);
    if (orch.typeByName('zju_scores') == null) {
      throw StateError('数据源 zju_scores 未注册');
    }
    final mem = await orch.fastReadByName('zju_scores');
    if (mem != null) return mem as Map<String, dynamic>;
    final data = await orch.getByName('zju_scores');
    return data as Map<String, dynamic>?;
  }

  void _reload() => setState(() => _future = _fetch());

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(),
        Expanded(
          child: FutureBuilder<Map<String, dynamic>?>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) return _buildError(snap.error.toString());
              final data = snap.data;
              if (data == null) {
                // fetcher 抛错 → 中枢返回 null 并记录 lastError；此处读状态补全提示。
                return _buildError(_statusError());
              }
              final grades = ((data['grades'] as List<dynamic>?) ?? [])
                  .map((e) => ZjuGrade.fromJson(e as Map<String, dynamic>))
                  .toList();
              final domesticGpa = ZjuGpaResult.fromJson(
                  (data['domestic_gpa'] as Map<String, dynamic>?) ?? {});
              final abroadGpa = ZjuGpaResult.fromJson(
                  (data['abroad_gpa'] as Map<String, dynamic>?) ?? {});
              return _buildDashboard(
                  grades: grades, domesticGpa: domesticGpa, abroadGpa: abroadGpa);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Row(
        children: [
          Text('成绩与 GPA', style: Theme.of(context).textTheme.titleLarge),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: _reload,
          ),
        ],
      ),
    );
  }

  Widget _buildError(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 40, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            const Text('加载成绩失败', style: TextStyle(fontSize: 15)),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: _reload,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  /// 从中枢状态读取 lastError 作为错误细节（fetcher 抛错被捕获后记录于此）。
  String _statusError() {
    final orch = ref.read(dataOrchestratorProvider);
    final s = orch.status('zju_scores');
    final err = s?.lastError;
    if (err == null || err.isEmpty) return '数据源未连接（zju_scores）';
    if (err.contains('未配置') || err.contains('设置')) {
      return '$err\n请先在「设置」中填写学号密码，再点重试。';
    }
    return err;
  }

  /// GPA 仪表盘（策略切换 + GPA 卡 + 图表 + 学期/搜索筛选 + 成绩列表）。
  Widget _buildDashboard({
    required List<ZjuGrade> grades,
    required ZjuGpaResult domesticGpa,
    required ZjuGpaResult abroadGpa,
  }) {
    final gpa = _strategy == 'first' ? domesticGpa : abroadGpa;
    final allGrades = _strategy == 'first'
        ? ZjuGpaCalculator.pickFirstAttempt(grades)
        : ZjuGpaCalculator.pickHighestAttempt(grades);

    // 提取学期列表（选课课号 xkkh，如 (2024-2025-1)-CS101-001）
    final semesters = allGrades
        .map((g) => _extractSemester(g.id))
        .toSet()
        .where((s) => s != null)
        .cast<String>()
        .toList()
      ..sort();

    // 筛选：学期 + 搜索
    var filtered = allGrades;
    if (_selectedSemester != null) {
      filtered = filtered
          .where((g) => _extractSemester(g.id) == _selectedSemester)
          .toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filtered = filtered
          .where((g) =>
              g.name.toLowerCase().contains(q) ||
              g.original.toLowerCase().contains(q))
          .toList();
    }

    // ── 可滚动头部：策略 + GPA 卡片 + 图表 ──
    final scrollableHeader = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'first', label: Text('保研（首次）')),
            ButtonSegment(value: 'highest', label: Text('出国（最高）')),
          ],
          selected: {_strategy},
          onSelectionChanged: (s) => setState(() => _strategy = s.first),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(children: [
          _GpaCard(
              label: '五分制',
              value: gpa.fivePoint.toStringAsFixed(2),
              max: 5.0),
          const SizedBox(width: 12),
          _GpaCard(
              label: '四分制(4.3)',
              value: gpa.fourPoint.toStringAsFixed(2),
              max: 4.3),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Row(children: [
          _GpaCard(
              label: '四分制(4.0)',
              value: gpa.fourPointLegacy.toStringAsFixed(2),
              max: 4.0),
          const SizedBox(width: 12),
          _GpaCard(
              label: '百分制',
              value: gpa.hundredPoint.toStringAsFixed(1),
              max: 100.0),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: Row(children: [
          Text('已获得学分: ${gpa.earnedCredits.toStringAsFixed(1)}',
              style: Theme.of(context).textTheme.bodySmall),
          if (_selectedSemester != null)
            TextButton(
                onPressed: () => setState(() => _selectedSemester = null),
                child: const Text('清除筛选')),
        ]),
      ),
      if (semesters.length >= 2)
        SizedBox(
          height: 180,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
            child: _GpaTrendChart(grades: allGrades),
          ),
        ),
      SizedBox(
        height: 140,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
          child: _GradeDistributionChart(grades: allGrades),
        ),
      ),
    ];

    // ── 固定筛选栏：Pin 在顶部的搜索 + 学期 ──
    final searchBar = Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(children: [
        if (semesters.isNotEmpty)
          Expanded(
            child: DropdownButtonFormField<String?>(
              value: _selectedSemester,
              decoration: const InputDecoration(
                  labelText: '学期',
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
              items: [
                const DropdownMenuItem(value: null, child: Text('全部')),
                ...semesters.map((s) => DropdownMenuItem(
                    value: s,
                    child: Text(_displaySemester(s),
                        style: const TextStyle(fontSize: 13)))),
              ],
              onChanged: (v) => setState(() => _selectedSemester = v),
            ),
          ),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: _searchController,
            decoration: const InputDecoration(
                hintText: '搜索课程',
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                prefixIcon: Icon(Icons.search, size: 18)),
            onChanged: (v) => setState(() => _searchQuery = v.trim()),
          ),
        ),
      ]),
    );

    // 使用 Column 将滚动区域 + 固定搜索栏分层
    return Column(
      children: [
        // 搜索栏固定在顶部
        searchBar,
        // 滚动区域
        Expanded(
          child: filtered.isEmpty
              ? ListView(children: [
                  ...scrollableHeader,
                  const SizedBox(height: 8),
                  _EmptyGrades(isEmpty: grades.isEmpty),
                ])
              : CustomScrollView(
                  slivers: [
                    SliverList(
                        delegate: SliverChildBuilderDelegate(
                            (_, i) => scrollableHeader[i],
                            childCount: scrollableHeader.length)),
                    SliverList(
                        delegate: SliverChildBuilderDelegate((_, i) {
                      final g = filtered[i];
                      return Card(
                        margin:
                            const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                        child: ListTile(
                          title: Text(g.name),
                          subtitle: Text('${g.credit.toStringAsFixed(1)} 学分'),
                          trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  g.original,
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: ZjuScoreColors.scoreColor(
                                          g.fivePoint.toDouble())),
                                ),
                                Text(
                                  '${g.fourPointGpa.toStringAsFixed(2)} / 4.3',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ]),
                        ),
                      );
                    }, childCount: filtered.length)),
                  ],
                ),
        ),
      ],
    );
  }

  /// 从选课课号 xkkh 中提取学期，如 `(2024-2025-1)-CS101-001` → `2024-2025-1`
  static String? _extractSemester(String courseId) {
    final match = RegExp(r'\(([^)]+)\)').firstMatch(courseId);
    return match?.group(1);
  }

  static String _displaySemester(String s) {
    final parts = s.split('-');
    if (parts.length >= 3) {
      return '${parts[0]}-${parts[1]} 第${parts[2]}学期';
    }
    return s;
  }
}

/// 空态：无成绩 / 无匹配。
class _EmptyGrades extends StatelessWidget {
  final bool isEmpty;
  const _EmptyGrades({required this.isEmpty});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.grade_outlined, size: 40, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text(isEmpty ? '暂无成绩' : '无匹配成绩',
                style: const TextStyle(fontSize: 15)),
            const SizedBox(height: 4),
            Text(
              isEmpty ? '请在教务网查询成绩后刷新（数据来自教务成绩单）' : '尝试调整学期或搜索词',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}

/// GPA 各学期趋势折线图（抄参考 `_GpaTrendChart`，fl_chart）。
class _GpaTrendChart extends StatelessWidget {
  final List<ZjuGrade> grades;
  const _GpaTrendChart({required this.grades});

  @override
  Widget build(BuildContext context) {
    // 按学期分组计算平均五分制 GPA
    final Map<String, List<ZjuGrade>> bySemester = {};
    for (final g in grades) {
      final sem = _extractSemester(g.id);
      if (sem != null) {
        bySemester.putIfAbsent(sem, () => []).add(g);
      }
    }

    final sortedSems = bySemester.keys.toList()..sort();
    if (sortedSems.length < 2) return const SizedBox.shrink();

    final spots = <FlSpot>[];
    for (var i = 0; i < sortedSems.length; i++) {
      final semGrades = bySemester[sortedSems[i]]!;
      final included = semGrades.where((g) => !g.isExcludedFromGpa).toList();
      if (included.isEmpty) continue;
      final sum = included.fold<double>(0.0, (a, b) => a + b.fivePoint);
      spots.add(FlSpot(i.toDouble(),
          double.parse((sum / included.length).toStringAsFixed(2))));
    }

    if (spots.length < 2) return const SizedBox.shrink();

    final maxY = spots.map((s) => s.y).reduce(max);
    final minY = spots.map((s) => s.y).reduce(min);
    final range = (maxY - minY) * 0.3 + 0.5;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('GPA 趋势', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Expanded(
          child: LineChart(
            LineChartData(
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: 0.5,
              ),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  axisNameWidget:
                      const Text('五分制', style: TextStyle(fontSize: 10)),
                  sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      getTitlesWidget: (v, _) => Text(v.toStringAsFixed(1),
                          style: const TextStyle(fontSize: 9))),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    interval: 1,
                    getTitlesWidget: (v, _) {
                      final idx = v.toInt();
                      if (idx < 0 || idx >= sortedSems.length) {
                        return const SizedBox();
                      }
                      final label = sortedSems[idx];
                      final parts = label.split('-');
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(parts.length >= 2 ? parts[1] : label,
                            style: const TextStyle(fontSize: 9)),
                      );
                    },
                  ),
                ),
                topTitles:
                    AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(show: false),
              minY: (minY - range * 0.2).clamp(0.0, 5.0),
              maxY: (maxY + range * 0.2).clamp(0.0, 5.0),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  color: Theme.of(context).colorScheme.primary,
                  barWidth: 2.5,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                      radius: 3,
                      color: Theme.of(context).colorScheme.primary,
                      strokeWidth: 1.5,
                      strokeColor: Colors.white,
                    ),
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.1),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static String? _extractSemester(String courseId) {
    final match = RegExp(r'\(([^)]+)\)').firstMatch(courseId);
    return match?.group(1);
  }
}

/// 成绩分布柱状图——五分制各分数段的课程数量（抄参考 `_GradeDistributionChart`）。
class _GradeDistributionChart extends StatelessWidget {
  final List<ZjuGrade> grades;
  const _GradeDistributionChart({required this.grades});

  @override
  Widget build(BuildContext context) {
    // 五分制区间: 0-1, 1-2, 2-3, 3-4, 4-5
    final bins = [0, 0, 0, 0, 0];
    for (final g in grades) {
      if (g.isExcludedFromGpa) continue;
      final idx = g.fivePoint.toInt().clamp(0, 4);
      bins[idx]++;
    }
    final maxCount = bins.reduce(max).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('成绩分布', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Expanded(
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: maxCount * 1.2,
              barTouchData: BarTouchData(enabled: false),
              titlesData: FlTitlesData(
                show: true,
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (v, _) {
                      const labels = ['0-1', '1-2', '2-3', '3-4', '4-5'];
                      final idx = v.toInt();
                      if (idx < 0 || idx >= labels.length) {
                        return const SizedBox();
                      }
                      return Text(labels[idx],
                          style: const TextStyle(fontSize: 9));
                    },
                  ),
                ),
                leftTitles:
                    AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles:
                    AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              gridData: FlGridData(show: false),
              borderData: FlBorderData(show: false),
              barGroups: List.generate(
                  5,
                  (i) => BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: bins[i].toDouble(),
                            color: _binColor(i, context),
                            width: 16,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(4),
                              topRight: Radius.circular(4),
                            ),
                          ),
                        ],
                      )),
            ),
          ),
        ),
      ],
    );
  }

  Color _binColor(int idx, BuildContext context) {
    final theme = Theme.of(context).colorScheme;
    switch (idx) {
      case 4:
        return Colors.green; // 4-5 优秀
      case 3:
        return Colors.lightGreen; // 3-4 良好
      case 2:
        return Colors.orange; // 2-3 中等
      case 1:
        return Colors.deepOrange; // 1-2 及格
      default:
        return Colors.red; // 0-1 不及格
    }
  }
}

/// GPA 卡片（抄参考 `_GpaCard`）。
class _GpaCard extends StatelessWidget {
  final String label;
  final String value;
  final double max;

  const _GpaCard({required this.label, required this.value, required this.max});

  @override
  Widget build(BuildContext context) {
    final v = double.tryParse(value) ?? 0;
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              Text(
                value,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: ZjuScoreColors.gpaColor(v),
                    ),
              ),
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: (v / max).clamp(0.0, 1.0),
                backgroundColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
