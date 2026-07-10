/// 日历组件——自绘月历视图。
///
/// 公开类：[CalendarWidget]
///
/// 支持：
/// - 月视图切换（上月/下月）
/// - 今日标记
/// - 日期选择
/// - 事件标记点
/// - 今日快速跳转
library;

import 'package:flutter/material.dart';

/// 日历事件数据。
class CalendarEvent {
  final DateTime date;
  final String title;
  final Color? color;

  const CalendarEvent({
    required this.date,
    required this.title,
    this.color,
  });
}

/// 自绘月历组件。
///
/// 使用方式：
/// ```dart
/// CalendarWidget(
///   events: [
///     CalendarEvent(date: DateTime(2026, 7, 15), title: '会议'),
///   ],
///   onDateSelected: (date) => print('选中: $date'),
/// )
/// ```
class CalendarWidget extends StatefulWidget {
  /// 初始展示月份（默认当月）。
  final DateTime? initialMonth;

  /// 事件列表。
  final List<CalendarEvent> events;

  /// 日期选中回调。
  final void Function(DateTime date)? onDateSelected;

  /// 选中的日期。
  final DateTime? selectedDate;

  const CalendarWidget({
    super.key,
    this.initialMonth,
    this.events = const [],
    this.onDateSelected,
    this.selectedDate,
  });

  @override
  State<CalendarWidget> createState() => _CalendarWidgetState();
}

class _CalendarWidgetState extends State<CalendarWidget> {
  late DateTime _currentMonth;
  DateTime? _selectedDate;

  static const _weekdayHeaders = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  void initState() {
    super.initState();
    _currentMonth = widget.initialMonth ?? DateTime.now();
    _currentMonth = DateTime(_currentMonth.year, _currentMonth.month, 1);
    _selectedDate = widget.selectedDate;
  }

  @override
  void didUpdateWidget(CalendarWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedDate != oldWidget.selectedDate) {
      _selectedDate = widget.selectedDate;
    }
  }

  void _previousMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1, 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 1);
    });
  }

  void _goToToday() {
    setState(() {
      _currentMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
      _selectedDate = DateTime.now();
    });
    widget.onDateSelected?.call(DateTime.now());
  }

  void _onDateTap(DateTime date) {
    setState(() => _selectedDate = date);
    widget.onDateSelected?.call(date);
  }

  /// 获取某月的所有日期格子（含前后月填充）。
  List<DateTime?> _getMonthDays() {
    final firstDay = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final lastDay = DateTime(_currentMonth.year, _currentMonth.month + 1, 0);

    final days = <DateTime?>[];

    // 周一为每周第一天，填充上月空白
    final startWeekday = firstDay.weekday; // 1=Mon, 7=Sun
    for (var i = 1; i < startWeekday; i++) {
      days.add(null);
    }

    // 本月所有日期
    for (var d = 1; d <= lastDay.day; d++) {
      days.add(DateTime(_currentMonth.year, _currentMonth.month, d));
    }

    // 填充下月空白（使总数为 7 的倍数）
    while (days.length % 7 != 0) {
      days.add(null);
    }

    return days;
  }

  /// 获取某日的事件列表。
  List<CalendarEvent> _eventsForDay(DateTime date) {
    return widget.events.where((e) =>
        e.date.year == date.year &&
        e.date.month == date.month &&
        e.date.day == date.day).toList();
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  bool _isSelected(DateTime date) {
    if (_selectedDate == null) return false;
    return date.year == _selectedDate!.year &&
        date.month == _selectedDate!.month &&
        date.day == _selectedDate!.day;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = _getMonthDays();
    final monthName = '${_currentMonth.year}年${_currentMonth.month}月';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 月份切换栏
        _buildMonthHeader(theme, monthName),

        const SizedBox(height: 8),

        // 星期标题行
        _buildWeekdayHeaders(theme),

        const SizedBox(height: 4),

        // 日期网格
        _buildDayGrid(theme, days),
      ],
    );
  }

  Widget _buildMonthHeader(ThemeData theme, String monthName) {
    return Row(
      children: [
        IconButton(
          onPressed: _previousMonth,
          icon: const Icon(Icons.chevron_left),
          tooltip: '上月',
          style: IconButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(36, 36),
          ),
        ),
        Expanded(
          child: GestureDetector(
            onTap: _goToToday,
            child: Text(
              monthName,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        IconButton(
          onPressed: _nextMonth,
          icon: const Icon(Icons.chevron_right),
          tooltip: '下月',
          style: IconButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(36, 36),
          ),
        ),
      ],
    );
  }

  Widget _buildWeekdayHeaders(ThemeData theme) {
    return Row(
      children: _weekdayHeaders.map((day) {
        final isWeekend = day == '六' || day == '日';
        return Expanded(
          child: Center(
            child: Text(
              day,
              style: theme.textTheme.labelSmall?.copyWith(
                color: isWeekend
                    ? theme.colorScheme.error.withValues(alpha: 0.7)
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDayGrid(ThemeData theme, List<DateTime?> days) {
    // 计算行数
    final rowCount = (days.length / 7).ceil();
    final cellHeight = 36.0;

    return SizedBox(
      height: cellHeight * rowCount + 8,
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 7,
          mainAxisSpacing: 2,
          crossAxisSpacing: 2,
          childAspectRatio: 1,
        ),
        itemCount: days.length,
        itemBuilder: (context, index) {
          final date = days[index];
          if (date == null) return const SizedBox.shrink();

          return _buildDayCell(theme, date);
        },
      ),
    );
  }

  Widget _buildDayCell(ThemeData theme, DateTime date) {
    final isToday = _isToday(date);
    final isSelected = _isSelected(date);
    final events = _eventsForDay(date);
    final hasEvents = events.isNotEmpty;
    final isWeekend = date.weekday == 6 || date.weekday == 7;

    // 背景色
    Color? bgColor;
    if (isSelected) {
      bgColor = theme.colorScheme.primary;
    } else if (isToday) {
      bgColor = theme.colorScheme.primaryContainer;
    }

    // 文字色
    Color textColor;
    if (isSelected) {
      textColor = theme.colorScheme.onPrimary;
    } else if (isToday) {
      textColor = theme.colorScheme.onPrimaryContainer;
    } else if (isWeekend) {
      textColor = theme.colorScheme.error.withValues(alpha: 0.7);
    } else {
      textColor = theme.colorScheme.onSurface;
    }

    return GestureDetector(
      onTap: () => _onDateTap(date),
      child: Container(
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(isSelected ? 8 : 6),
          border: isToday && !isSelected
              ? Border.all(
                  color: theme.colorScheme.primary,
                  width: 1.5,
                )
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${date.day}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: textColor,
                fontWeight:
                    isToday || isSelected ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
            if (hasEvents)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: events.take(3).map((e) {
                  return Container(
                    width: 4,
                    height: 4,
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? theme.colorScheme.onPrimary
                          : (e.color ?? theme.colorScheme.primary),
                      shape: BoxShape.circle,
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }
}
