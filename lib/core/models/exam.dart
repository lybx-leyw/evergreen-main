import '../utils/safe_parse.dart';

/// Exam model — represents an upcoming exam from ZDBK or courses.zju.edu.cn.
class Exam {
  final String id;
  final String name; // Course name
  final String? location; // Exam room
  final DateTime? startTime;
  final DateTime? endTime;
  final String? seatNumber;
  final String source; // 'zdbk' or 'courses'

  const Exam({
    required this.id,
    required this.name,
    this.location,
    this.startTime,
    this.endTime,
    this.seatNumber,
    required this.source,
  });

  factory Exam.fromZdbk(Map<String, dynamic> json) {
    final kssj = SafeParse.string(json['kssj']);
    final jssj = SafeParse.string(json['jssj']);

    return Exam(
      id: SafeParse.string(json['xkkh']),
      name: SafeParse.string(json['kcmc'], defaultValue: '未命名考试'),
      location: SafeParse.string(json['cdmc']),
      startTime: _parseKssj(kssj),
      endTime: _parseJssj(kssj, jssj),
      seatNumber: SafeParse.string(json['zwh']),
      source: 'zdbk',
    );
  }

  factory Exam.fromCourses(Map<String, dynamic> json) {
    return Exam(
      id: SafeParse.string(json['id']),
      name: SafeParse.string(json['title'],
          defaultValue: SafeParse.string(json['name'])),
      location: SafeParse.string(json['location']),
      startTime: SafeParse.dateTime(
          json['start_at'] ?? json['start']),
      endTime: SafeParse.dateTime(
          json['end_at'] ?? json['end']),
      seatNumber: null,
      source: 'courses',
    );
  }

  // ── ZDBK time parsing ───────────────────────────────────────────────

  /// Parse ZDBK start time from `kssj` field.
  ///
  /// ZDBK format: "2025年08月23日(14:00-16:40)"
  /// Extracts date and start time (before the dash).
  static DateTime? _parseKssj(String? raw) {
    if (raw == null || raw.isEmpty || raw == 'null') return null;

    // Chinese date format: "2025年08月23日(14:00-16:40)"
    final m = RegExp(
      r'(\d{4})年(\d{1,2})月(\d{1,2})日\((\d{1,2}):(\d{2})',
    ).firstMatch(raw);
    if (m != null) {
      return _safeDateTime(
        SafeParse.int_(m.group(1)),
        SafeParse.int_(m.group(2)),
        SafeParse.int_(m.group(3)),
        SafeParse.int_(m.group(4)),
        SafeParse.int_(m.group(5)),
      );
    }

    // Fallback: standard ISO format
    return SafeParse.dateTime(raw);
  }

  /// Parse ZDBK end time from `jssj` field, falling back to `kssj` range.
  ///
  /// ZDBK returns `jssj` as the literal string "null" (not a null value).
  /// In that case, the end time is embedded in `kssj`: "(14:00-16:40)".
  ///
  /// For Courses API, standard ISO format is expected.
  static DateTime? _parseJssj(String? kssj, String? jssj) {
    // If jssj is a real value, try it
    if (jssj != null && jssj != 'null' && jssj.isNotEmpty) {
      final parsed = SafeParse.dateTime(jssj);
      if (parsed != null) return parsed;
    }

    // Extract end time from kssj's time range: "2025年08月23日(14:00-16:40)"
    if (kssj != null && kssj != 'null') {
      final m = RegExp(
        r'(\d{4})年(\d{1,2})月(\d{1,2})日\(\d{1,2}:\d{2}-(\d{1,2}):(\d{2})\)',
      ).firstMatch(kssj);
      if (m != null) {
        return _safeDateTime(
          SafeParse.int_(m.group(1)),
          SafeParse.int_(m.group(2)),
          SafeParse.int_(m.group(3)),
          SafeParse.int_(m.group(4)),
          SafeParse.int_(m.group(5)),
        );
      }
    }

    return null;
  }

  /// 构造 DateTime，自动 clamp 非法值到合法范围。
  static DateTime _safeDateTime(int year, int month, int day, int hour, int minute) {
    return DateTime(
      year.clamp(2000, 2100),
      month.clamp(1, 12),
      day.clamp(1, 31),
      hour.clamp(0, 23),
      minute.clamp(0, 59),
    );
  }

  // ── Convenience ─────────────────────────────────────────────────────

  /// Days until exam (negative if past).
  int get daysUntil {
    if (startTime == null) return 999;
    return startTime!.difference(DateTime.now()).inDays;
  }

  /// Urgency classification.
  ExamUrgency get urgency {
    if (daysUntil < 0) return ExamUrgency.past;
    if (daysUntil <= 7) return ExamUrgency.critical;
    if (daysUntil <= 30) return ExamUrgency.soon;
    return ExamUrgency.future;
  }
}

enum ExamUrgency { past, critical, soon, future }
