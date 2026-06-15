import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/exam.dart';
import '../../../core/utils/auto_refresh.dart';
import '../providers/exams_provider.dart';
import '../widgets/exam_card.dart';
import '../../../widgets/loading_indicator.dart';
import '../../../widgets/error_card.dart';
import '../../../widgets/empty_state.dart';

/// Exams screen — upcoming exam countdowns + calendar view.
class ExamsScreen extends ConsumerStatefulWidget {
  const ExamsScreen({super.key});

  @override
  ConsumerState<ExamsScreen> createState() => _ExamsScreenState();
}

class _ExamsScreenState extends ConsumerState<ExamsScreen> {
  bool _showCalendar = false;
  DateTime _focusedMonth = DateTime.now();
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (shouldRefresh(ref)) ref.invalidate(examsListProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final examsAsync = ref.watch(examsListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('考试日程'),
        actions: [
          IconButton(
            icon: Icon(_showCalendar ? Icons.list : Icons.calendar_month),
            tooltip: _showCalendar ? '列表视图' : '日历视图',
            onPressed: () => setState(() => _showCalendar = !_showCalendar),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(examsListProvider),
          ),
        ],
      ),
      body: examsAsync.when(
        loading: () => const LoadingWidget(message: '加载考试日程...'),
        error: (err, _) => ErrorCard(
          message: '加载考试信息失败',
          detail: err.toString(),
          onRetry: () => ref.invalidate(examsListProvider),
        ),
        data: (exams) {
          if (exams.isEmpty) {
            return const EmptyState(
              icon: Icons.event_busy,
              title: '暂无考试安排',
              subtitle: '考试日程将在教务网公布后显示',
            );
          }
          if (_showCalendar) return _buildCalendar(exams);
          return _buildList(exams);
        },
      ),
    );
  }

  Widget _buildList(List<Exam> exams) {
    final past = exams.where((e) => e.urgency == ExamUrgency.past).toList();
    final critical = exams.where((e) => e.urgency == ExamUrgency.critical).toList();
    final soon = exams.where((e) => e.urgency == ExamUrgency.soon).toList();
    final future = exams.where((e) => e.urgency == ExamUrgency.future).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (critical.isNotEmpty) ...[
          Text('⚠️ 7天内 (${critical.length})', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          ...critical.map((e) => ExamCard(exam: e)),
          const SizedBox(height: 16),
        ],
        if (soon.isNotEmpty) ...[
          Text('📅 30天内 (${soon.length})', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          ...soon.map((e) => ExamCard(exam: e)),
          const SizedBox(height: 16),
        ],
        if (future.isNotEmpty) ...[
          Text('📆 后续 (${future.length})', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          ...future.map((e) => ExamCard(exam: e)),
        ],
        if (past.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('✅ 已结束 (${past.length})', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.grey)),
          ...past.map((e) => ExamCard(exam: e)),
        ],
      ],
    );
  }

  Widget _buildCalendar(List<Exam> exams) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final firstDay = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final lastDay = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0);
    final firstWeekday = firstDay.weekday % 7;
    final daysInMonth = lastDay.day;
    final rows = ((firstWeekday + daysInMonth) / 7).ceil();

    final examsByDay = <int, List<Exam>>{};
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
        : <Exam>[];

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
            final cellW =
                ((constraints.maxWidth - 8) / 7).clamp(32.0, 64.0);
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
                                    return SizedBox(width: cellW, height: cellH);
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
                                            ? theme.colorScheme.primaryContainer
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
                                                    ? theme
                                                        .colorScheme
                                                        .onPrimaryContainer
                                                    : null,
                                              )),
                                          if (hasExam)
                                            Container(
                                              margin: const EdgeInsets.only(
                                                  top: 1),
                                              width: 5,
                                              height: 5,
                                              decoration: BoxDecoration(
                                                color: isSel
                                                    ? theme
                                                        .colorScheme
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
