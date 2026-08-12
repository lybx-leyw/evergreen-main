/// ZjuExam — 考试安排模型。
///
/// B3-exams（2026-08-12）自参考工程 `cp_evergreen_push/lib/core/models/exam.dart`
/// 拷入并前缀 `Zju`（规划 §5.6），保留 fromZdbk / fromCourses 双来源解析；
/// 另增 fromJson/toJson 双向桥接——fetcher 产出 JSON（数据中枢 jsonEncode 缓存），
/// renderer 侧 fromJson 还原。SafeParse 复用 evg-base core 已有实现。
library;

import 'package:evergreen_base/core/utils/safe_parse.dart';

/// 考试紧急度分级（倒计时窗口）。
enum ZjuExamUrgency {
  /// 已结束。
  past,

  /// 7 天内。
  critical,

  /// 30 天内。
  soon,

  /// 更远。
  future,
}

/// 一场考试——来自 ZDBK（教务网）或 courses.zju.edu.cn（学在浙大）。
class ZjuExam {
  final String id; // 选课课号 xkkh（ZDBK） / 课程 id（courses）
  final String name; // 课程名称
  final String? location; // 考场 cdmc
  final DateTime? startTime;
  final DateTime? endTime;
  final String? seatNumber; // 座位号 zwh
  final String source; // 'zdbk' 或 'courses'

  const ZjuExam({
    required this.id,
    required this.name,
    this.location,
    this.startTime,
    this.endTime,
    this.seatNumber,
    required this.source,
  });

  factory ZjuExam.fromZdbk(Map<String, dynamic> json) {
    final kssj = SafeParse.string(json['kssj']);
    final jssj = SafeParse.string(json['jssj']);

    return ZjuExam(
      id: SafeParse.string(json['xkkh']),
      name: SafeParse.string(json['kcmc'], defaultValue: '未命名考试'),
      location: SafeParse.string(json['cdmc']),
      startTime: _parseKssj(kssj),
      endTime: _parseJssj(kssj, jssj),
      seatNumber: SafeParse.string(json['zwh']),
      source: 'zdbk',
    );
  }

  factory ZjuExam.fromCourses(Map<String, dynamic> json) {
    return ZjuExam(
      id: SafeParse.string(json['id']),
      name: SafeParse.string(
          json['title'], defaultValue: SafeParse.string(json['name'])),
      location: SafeParse.string(json['location']),
      startTime: SafeParse.dateTime(json['start_at'] ?? json['start']),
      endTime: SafeParse.dateTime(json['end_at'] ?? json['end']),
      seatNumber: null,
      source: 'courses',
    );
  }

  /// 从数据中枢缓存的 JSON 还原（fetcher `toJson()` 产出）。
  factory ZjuExam.fromJson(Map<String, dynamic> json) {
    return ZjuExam(
      id: SafeParse.string(json['id']),
      name: SafeParse.string(json['name'], defaultValue: '未命名考试'),
      location: SafeParse.string(json['location']).isEmpty
          ? null
          : SafeParse.string(json['location']),
      startTime: SafeParse.dateTime(json['startTime']),
      endTime: SafeParse.dateTime(json['endTime']),
      seatNumber: SafeParse.string(json['seatNumber']).isEmpty
          ? null
          : SafeParse.string(json['seatNumber']),
      source: SafeParse.string(json['source'], defaultValue: 'zdbk'),
    );
  }

  /// 序列化（数据中枢缓存契约，DateTime → ISO 8601 字符串）。
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'location': location,
        'startTime': startTime?.toIso8601String(),
        'endTime': endTime?.toIso8601String(),
        'seatNumber': seatNumber,
        'source': source,
      };

  // ── ZDBK 时间解析 ───────────────────────────────────────────────────

  /// 解析 ZDBK 开考时间 `kssj`。
  ///
  /// ZDBK 格式："2025年08月23日(14:00-16:40)"，提取日期与开始时间（横杠前）。
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

  /// 解析 ZDBK 结束时间 `jssj`，回退到 `kssj` 内嵌区间。
  ///
  /// ZDBK 常把 `jssj` 返回为字面字符串 "null"（而非 null），此时结束时间
  /// 内嵌在 `kssj` 的 "(14:00-16:40)" 中。Courses API 为标准 ISO 格式。
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

  /// 构造 DateTime，自动 clamp 非法值到合法范围（照抄参考，防坏数据炸 UI）。
  static DateTime _safeDateTime(
      int year, int month, int day, int hour, int minute) {
    return DateTime(
      year.clamp(2000, 2100),
      month.clamp(1, 12),
      day.clamp(1, 31),
      hour.clamp(0, 23),
      minute.clamp(0, 59),
    );
  }

  // ── 派生字段 ─────────────────────────────────────────────────────────

  /// 距开考天数（已过为负；无时间信息返回 999）。
  int get daysUntil {
    if (startTime == null) return 999;
    return startTime!.difference(DateTime.now()).inDays;
  }

  /// 紧急度分级（照抄参考：7 天内 critical / 30 天内 soon / 更远 future）。
  ZjuExamUrgency get urgency {
    if (daysUntil < 0) return ZjuExamUrgency.past;
    if (daysUntil <= 7) return ZjuExamUrgency.critical;
    if (daysUntil <= 30) return ZjuExamUrgency.soon;
    return ZjuExamUrgency.future;
  }
}
