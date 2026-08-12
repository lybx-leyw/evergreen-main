/// 考试日程视图（zju / exams）。
///
/// B3-exams（2026-08-12）自参考工程
/// `cp_evergreen_push/lib/features/exams/screens/exams_screen.dart` 移植，改造点：
/// - 去 Scaffold/AppBar（evg-base 桌面规范：模块区无 per-module AppBar，页面自绘标题头）；
/// - 数据不再走 Riverpod `examsListProvider`（ZDBK + courses 双源合并），改经数据中枢
///   `orch.fastReadByName('zju_exams')`（fetcher 已合并双源 + 按时间排序随 JSON 缓存）；
/// - `Exam`→`ZjuExam`、`AppTheme`→`ZjuScoreColors`；
/// - 列表分组（⚠️7 天内 / 📅30 天内 / 📆后续 / ✅已结束）+ 日历视图原样保留。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:evergreen_base/providers.dart' show dataOrchestratorProvider;

import '../../shared/models/zju_exam.dart';
import '../widgets/exam_card.dart';

/// 考试日程主视图：列表分组 + 日历视图切换。
class ExamsView extends ConsumerStatefulWidget {
  const ExamsView({super.key});

  @override
  ConsumerState<ExamsView> createState() => _ExamsViewState();
}

class _ExamsViewState extends ConsumerState<ExamsView> {
  bool _showCalendar = false;
  DateTime _focusedMonth = DateTime.now();
  DateTime? _selectedDay;
  Future<Map<String, dynamic>?>? _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  /// 经数据中枢拉取（内存快读 → 磁盘/网络）。
  Future<Map<String, dynamic>?> _fetch() async {
    final orch = ref.read(dataOrchestratorProvider);
    if (orch.typeByName('zju_exams') == null) {
      throw StateError('数据源 zju_exams 未注册');
    }
    final mem = await orch.fastReadByName('zju_exams');
    if (mem != null) return mem as Map<String, dynamic>;
    final data = await orch.getByName('zju_exams');
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
              if (data == null) return _buildError(_statusError());
              final exams = ((data['exams'] as List<dynamic>?) ?? [])
                  .map((e) => ZjuExam.fromJson(e as Map<String, dynamic>))
                  .toList();
              if (exams.isEmpty) {
                return _buildEmpty();
              }
              if (_showCalendar) return _buildCalendar(exams);
              return _buildList(exams);
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
          Text('考试日程', style: Theme.of(context).textTheme.titleLarge),
          const Spacer(),
          IconButton(
            icon: Icon(_showCalendar ? Icons.list : Icons.calendar_month),
            tooltip: _showCalendar ? '列表视图' : '日历视图',
            onPressed: () => setState(() => _showCalendar = !_showCalendar),
          ),
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
            const Text('加载考试信息失败', style: TextStyle(fontSize: 15)),
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
    final s = orch.status('zju_exams');
    final err = s?.lastError;
    if (err == null || err.isEmpty) return '数据源未连接（zju_exams）';
    if (err.contains('未配置') || err.contains('设置')) {
      return '$err\n请先在「设置」中填写学号密码，再点重试。';
    }
    return err;
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.event_busy, size: 40, color: Colors.grey.shade400),
          const SizedBox(height: 8),
          const Text('暂无考试安排', style: TextStyle(fontSize: 15)),
          const SizedBox(height: 4),
          Text(
            '考试日程将在教务网公布后显示',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  /// 分组列表：⚠️7 天内 / 📅30 天内 / 📆后续 / ✅已结束（照抄参考）。
  Widget _buildList(List<ZjuExam> exams) {
    final past = exams.where((e) => e.urgency == ZjuExamUrgency.past).toList();
    final critical =
        exams.where((e) => e.urgency == ZjuExamUrgency.critical).toList();
    final soon =
        exams.where((e) => e.urgency == ZjuExamUrgency.soon).toList();
    final future =
        exams.where((e) => e.urgency == ZjuExamUrgency.future).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (critical.isNotEmpty) ...[
          Text('⚠️ 7天内 (${critical.length})',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          ...critical.map((e) => ExamCard(exam: e)),
          const SizedBox(height: 16),
        ],
        if (soon.isNotEmpty) ...[
          Text('📅 30天内 (${soon.length})',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          ...soon.map((e) => ExamCard(exam: e)),
          const SizedBox(height: 16),
        ],
        if (future.isNotEmpty) ...[
          Text('📆 后续 (${future.length})',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          ...future.map((e) => ExamCard(exam: e)),
        ],
        if (past.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('✅ 已结束 (${past.length})',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(color: Colors.grey)),
          ...past.map((e) => ExamCard(exam: e)),
        ],
      ],
    );
  }

  /// 日历视图（照抄参考：自适应 cell 宽 + 月份导航 + 选中日考试列表）。
  Widget _buildCalendar(List<ZjuExam> exams) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final firstDay = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final lastDay = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0);
    final firstWeekday = firstDay.weekday % 7;
    final daysInMonth = lastDay.day;
    final rows = ((firstWeekday + daysInMonth) / 7).ceil();

    final examsByDay = <int, List<ZjuExam>>{};
    for (final e in exams) {
      if (e.startTime == null) continue;
      if (e.startTime!.year != _focusedMonth.year ||
          e.startTime!.month != _focusedMonth.month) continue;
      examsByDay.putIfAbsent(e.startTime!.day, () => []).add(e);
    }

    final selectedExams = _selectedDay != null
        ? exams
            .where((e) =>
                e.startTime != null &&
                e.startTime!.year == _selectedDay!.year &&
                e.startTime!.month == _selectedDay!.month &&
                e.startTime!.day == _selectedDay!.day)
            .toList()
        : <ZjuExam>[];

    return Column(
      children: [
        // Month navigator
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, size: 20),
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() {
                  _focusedMonth =
                      DateTime(_focusedMonth.year, _focusedMonth.month - 1, 1);
                  _selectedDay = null;
                }),
              ),
              Text('${_focusedMonth.year}年${_focusedMonth.month}月',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
              IconButton(
                icon: const Icon(Icons.chevron_right, size: 20),
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() {
                  _focusedMonth =
                      DateTime(_focusedMonth.year, _focusedMonth.month + 1, 1);
                  _selectedDay = null;
                }),
              ),
            ],
          ),
        ),
        // Calendar — 自适应宽度，紧凑风格
        LayoutBuilder(
          builder: (context, constraints) {
            final cellW = ((constraints.maxWidth - 8) / 7).clamp(32.0, 64.0);
            final cellH = cellW * 0.85;
            final fontSize = (cellW * 0.38).clamp(10.0, 14.0);

            return Center(
              child: SizedBox(
                width: 7 * cellW,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Weekday headers
                    Row(
                      children: '日一二三四五六'
                          .split('')
                          .map((d) => SizedBox(
                                width: cellW,
                                height: 20,
                                child: Center(
                                    child: Text(d,
                                        style: TextStyle(
                                            fontSize: 10,
                                            color: theme.colorScheme
                                                .onSurfaceVariant))),
                              ))
                          .toList(),
                    ),
                    // Grid
                    SizedBox(
                      height: rows * cellH,
                      child: Stack(
                        children: [
                          // Grid lines
                          ...List.generate(
                            rows,
                            (r) => Positioned(
                              top: r * cellH,
                              left: 0,
                              child: Row(
                                children: List.generate(7, (c) {
                                  final idx = r * 7 + c;
                                  if (idx < firstWeekday ||
                                      idx - firstWeekday >= daysInMonth) {
                                    return SizedBox(
                                        width: cellW, height: cellH);
                                  }
                                  final day = idx - firstWeekday + 1;
                                  final date = DateTime(_focusedMonth.year,
                                      _focusedMonth.month, day);
                                  final isToday = date.year == now.year &&
                                      date.month == now.month &&
                                      date.day == now.day;
                                  final isSel = _selectedDay != null &&
                                      date.year == _selectedDay!.year &&
                                      date.month == _selectedDay!.month &&
                                      date.day == _selectedDay!.day;
                                  final hasExam =
                                      examsByDay.containsKey(day);

                                  return GestureDetector(
                                    onTap: () => setState(() => _selectedDay =
                                        _selectedDay?.day == day
                                            ? null
                                            : date),
                                    child: Container(
                                      width: cellW,
                                      height: cellH,
                                      decoration: BoxDecoration(
                                        color: isSel
                                            ? theme
                                                .colorScheme.primaryContainer
                                            : isToday
                                                ? theme.colorScheme
                                                    .surfaceContainerHighest
                                                : null,
                                        border: Border.all(
                                          color: theme
                                              .colorScheme.outlineVariant,
                                          width: 0.5,
                                        ),
                                      ),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text('$day',
                                              style: TextStyle(
                                                fontSize: fontSize,
                                                fontWeight: isToday
                                                    ? FontWeight.bold
                                                    : null,
                                                color: isSel
                                                    ? theme.colorScheme
                                                        .onPrimaryContainer
                                                    : null,
                                              )),
                                          if (hasExam)
                                            Container(
                                              margin:
                                                  const EdgeInsets.only(
                                                      top: 1),
                                              width: 5,
                                              height: 5,
                                              decoration: BoxDecoration(
                                                color: isSel
                                                    ? theme.colorScheme
                                                        .onPrimaryContainer
                                                    : theme.colorScheme.primary,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  );
                                }),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        // Selected day exams
        if (selectedExams.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                Icon(Icons.event, size: 14,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  '${_selectedDay!.month}/${_selectedDay!.day} 考试',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(color: theme.colorScheme.primary),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: selectedExams.length,
              itemBuilder: (_, i) => ExamCard(exam: selectedExams[i]),
            ),
          ),
        ],
      ],
    );
  }
}
