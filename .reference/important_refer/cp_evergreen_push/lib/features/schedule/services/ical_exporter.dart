import '../../../core/utils/date_utils.dart';

/// 课程日程模型 —— 供 iCal 导出使用。
class CourseSchedule {
  final String id;
  final String name;
  final String instructor;
  final String className;
  final String location;
  final String? rawSchedule;

  const CourseSchedule({
    required this.id,
    required this.name,
    this.instructor = '',
    this.className = '',
    this.location = '',
    this.rawSchedule,
  });

  /// 解析原始课表字符串（如 "周一第1-2节{1-17周}"）为结构化字段。
  _ParsedSchedule? parseSchedule() {
    if (rawSchedule == null || rawSchedule!.isEmpty) return null;
    final match = RegExp(
      r'(周[一二三四五六日天])第(\d+)-(\d+)节[{(](\d+)-?(\d+)?周?[})]',
    ).firstMatch(rawSchedule!);
    if (match == null) return null;
    final weekdayCN = match.group(1)!;
    final weekdayCode = _weekdayMap[weekdayCN.substring(1)];
    if (weekdayCode == null) return null;
    final dayOffset = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'].indexOf(weekdayCode);
    final startPeriod = int.tryParse(match.group(2)!) ?? 1;
    final endPeriod = int.tryParse(match.group(3)!) ?? startPeriod;
    final weekStart = int.tryParse(match.group(4)!) ?? 1;
    final weekEnd = match.group(5) != null
        ? (int.tryParse(match.group(5)!) ?? weekStart)
        : weekStart;
    return _ParsedSchedule(
      dayOffset: dayOffset,
      startPeriod: startPeriod,
      endPeriod: endPeriod,
      weekStart: weekStart,
      weekEnd: weekEnd,
    );
  }

  static const Map<String, String> _weekdayMap = {
    '一': 'MO', '二': 'TU', '三': 'WE', '四': 'TH',
    '五': 'FR', '六': 'SA', '日': 'SU', '天': 'SU',
  };
}

/// iCal (ICS) format exporter — generates calendar files for course schedules.
///
/// Ports the schedule export logic from electron/main.js.
class ICalExporter {
  /// ZJU class period start times (0-indexed: period 1 = 08:00).
  static const List<String> _periodStartTimes = [
    '08:00', '08:50', '09:50', '10:40', '11:30',
    '13:15', '14:05', '15:05', '15:55', '16:45',
    '18:30', '19:20', '20:10', '21:00',
  ];

  /// Generate iCal content from a list of course schedules.
  ///
  /// [courses] — list of course objects with schedule info.
  /// [semesterStart] — first Monday of the semester.
  String generate(List<CourseSchedule> courses, DateTime semesterStart) {
    final buf = StringBuffer();
    buf.writeln('BEGIN:VCALENDAR');
    buf.writeln('VERSION:2.0');
    buf.writeln('PRODID:-//ZJU live better and better//CN');
    buf.writeln('CALSCALE:GREGORIAN');
    buf.writeln('METHOD:PUBLISH');

    for (final c in courses) {
      final schedule = c.parseSchedule();
      if (schedule == null) {
        // Default: Monday 08:00, 18 weeks
        _writeEvent(buf, c, semesterStart, 0, 1, 2, 1, 18);
        continue;
      }

      _writeEvent(
        buf,
        c,
        semesterStart,
        schedule.dayOffset,
        schedule.startPeriod,
        schedule.endPeriod,
        schedule.weekStart,
        schedule.weekEnd,
      );
    }

    buf.writeln('END:VCALENDAR');
    return buf.toString();
  }

  void _writeEvent(
    StringBuffer buf,
    CourseSchedule course,
    DateTime semesterStart,
    int dayOffset,
    int startPeriod,
    int endPeriod,
    int weekStart,
    int weekEnd,
  ) {
    final weekdayCode = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'][dayOffset];

    final periodIdx = (startPeriod - 1).clamp(0, _periodStartTimes.length - 1);
    final timeParts = _periodStartTimes[periodIdx].split(':');
    final hourStart = int.parse(timeParts[0]);
    final minuteStart = int.parse(timeParts[1]);
    final durationMinutes = (endPeriod - startPeriod + 1) * 45;

    final eventStart = DateTime(
      semesterStart.year, semesterStart.month, semesterStart.day + dayOffset,
      hourStart, minuteStart,
    );
    final eventEnd = eventStart.add(Duration(minutes: durationMinutes));

    final untilDate = DateTime(
      semesterStart.year, semesterStart.month,
      semesterStart.day + (weekEnd - 1) * 7 + dayOffset,
    );
    // Push UNTIL to end of day
    final until = DateTime(untilDate.year, untilDate.month, untilDate.day, 23, 59, 59);

    final uid = course.id.isNotEmpty ? course.id : course.name.hashCode.toString();

    buf.writeln('BEGIN:VEVENT');
    buf.writeln('UID:$uid@zju-live-better');
    buf.writeln('SUMMARY:${_escapeText(course.name)}');
    buf.writeln('DESCRIPTION:${_escapeText('教师: ${course.instructor}\n教学班: ${course.className}')}');
    if (course.location.isNotEmpty) {
      buf.writeln('LOCATION:${_escapeText(course.location)}');
    }
    buf.writeln('DTSTART:${_formatICSDate(eventStart)}');
    buf.writeln('DTEND:${_formatICSDate(eventEnd)}');
    buf.writeln('RRULE:FREQ=WEEKLY;BYDAY=$weekdayCode;INTERVAL=1;UNTIL=${_formatICSDate(until)}');
    buf.writeln('END:VEVENT');
  }

  /// Format a DateTime as iCal UTC string: YYYYMMDDTHHMMSSZ
  String _formatICSDate(DateTime dt) {
    final y = dt.year.toString();
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$y$m${d}T${h}${min}00Z';
  }

  /// Escape special characters for iCal text fields.
  String _escapeText(String text) {
    return text
        .replaceAll('\\', '\\\\')
        .replaceAll(';', '\\;')
        .replaceAll(',', '\\,')
        .replaceAll('\n', '\\n');
  }
}

class _ParsedSchedule {
  final int dayOffset;
  final int startPeriod;
  final int endPeriod;
  final int weekStart;
  final int weekEnd;

  const _ParsedSchedule({
    required this.dayOffset,
    required this.startPeriod,
    required this.endPeriod,
    required this.weekStart,
    required this.weekEnd,
  });
}
