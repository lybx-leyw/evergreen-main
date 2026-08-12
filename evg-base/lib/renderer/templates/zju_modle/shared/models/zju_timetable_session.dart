/// ZjuTimetableSession — 课表单条记录。
///
/// B3-ui（2026-08-13）自参考工程
/// `cp_evergreen_push/lib/core/models/timetable_session.dart` 拷入并前缀 `Zju`
/// （规划 §5.6 防符号冲突），改造点：
/// - 解析工具改用 evg-base `core/utils/safe_parse.dart`（API 兼容参考）；
/// - `toJson` 额外携带 `semester` / `course_year`——数据中枢缓存契约要求
///   toJson→fromJson 可还原全部字段，UI 学期位掩码过滤依赖这两个字段
///   （参考实现缓存的是原始 zdbk 条目、每次重新 fromZdbkJson，不适用中枢）。
///
/// 数据源：ZDBK `jwglxt/kbcx/xskbcx_cxXsKb.html`。
/// 原始 JSON 字段：
/// - `kcb`: 课程信息 HTML（含课程名、周次、教师、地点，以 `<br>` 分隔）
/// - `xqj`: 星期几 (1-7)
/// - `djj`: 第几节（起始节次）
/// - `skcd`: 上课节次长度
/// - `dsz`: 教学周范围
/// - `xkkh`: 选课课号
library;

import 'package:evergreen_base/core/utils/safe_parse.dart';

/// 课表单条记录。
class ZjuTimetableSession {
  final String? courseId;
  final String courseName;
  final String? teacher;
  final String? location;
  final int dayOfWeek;
  final List<int> periods;
  final String? weekRange;
  final int? semester; // 按位: 春=1, 夏=2, 短①=4, 秋=8, 冬=16, 短②=32, 暑=64
  final int? courseYear; // 从 xkkh 提取的学年起始年
  final bool isEnded;
  final double credit;

  const ZjuTimetableSession({
    this.courseId,
    required this.courseName,
    this.teacher,
    this.location,
    required this.dayOfWeek,
    required this.periods,
    this.weekRange,
    this.semester,
    this.courseYear,
    this.isEnded = false,
    this.credit = 0.0,
  });

  /// 从 ZDBK 课表 JSON 条目解析。
  ///
  /// 新格式字段：`kcb`, `xqj`, `djj`(起始节次), `skcd`(节次长度), `dsz`(周范围)。
  /// `kcb` 格式：`课程名称<br>周次{...}<br>教师名<br>地点[zwf...]`
  factory ZjuTimetableSession.fromZdbkJson(Map<String, dynamic> json) {
    // ── 解析 kcb HTML 字符串 ──────────────────────────────────
    final rawKcb = SafeParse.string(json['kcb'], defaultValue: '');
    final kcbParts = rawKcb.split('<br>');

    var courseName = kcbParts.isNotEmpty ? kcbParts[0].trim() : '未命名课程';
    var teacher = '';
    var location = '';
    // 学期标记：按位存储 春=1, 夏=2, 短①(夏后)=4, 秋=8, 冬=16, 短②(冬后)=32, 暑=64
    var semester = 0;

    if (kcbParts.length >= 2) {
      final weekInfo = kcbParts[1];
      if (weekInfo.contains('春')) semester |= 1;
      if (weekInfo.contains('夏')) semester |= 2;
      if (weekInfo.contains('秋')) semester |= 8;
      if (weekInfo.contains('冬')) semester |= 16;
      // 短学期：kcb 不分夏后/冬后，两个短标记都设
      if (weekInfo.contains('短') || weekInfo == '短学期') {
        semester |= 4;
        semester |= 32;
      }
      if (weekInfo.contains('暑')) semester |= 64;
    }
    if (kcbParts.length >= 3) {
      teacher = kcbParts[2].trim(); // 第3段是教师名
    }
    if (kcbParts.length >= 4) {
      // 第4段是地点，可能包含 "zwf" 分隔的额外信息
      var rawLoc = kcbParts[3].trim();
      final zwfIdx = rawLoc.indexOf('zwf');
      if (zwfIdx > 0) {
        rawLoc = rawLoc.substring(0, zwfIdx);
      }
      location = rawLoc;
    }

    // ── 从 djj + skcd 计算节次列表 ────────────────────────────
    final startPeriod = SafeParse.int_(json['djj']);
    final periodLength = SafeParse.int_(json['skcd']);
    final periods = <int>[];
    if (startPeriod != null && startPeriod > 0) {
      final count = (periodLength != null && periodLength > 0) ? periodLength : 1;
      for (var i = 0; i < count; i++) {
        periods.add(startPeriod + i);
      }
    }

    // ── 周次范围 ──────────────────────────────────────────────
    final rawWeek = SafeParse.string(json['dsz']);
    final weekRange = (rawWeek == null || rawWeek.isEmpty) ? null : rawWeek;

    // ── 从 xkkh 提取学年起始年 ──────────────────────────────────
    // 格式: (2025-2026-2)-CS101-001 → 2025
    final courseId = SafeParse.string(json['xkkh']);
    int? courseYear;
    if (courseId != null) {
      final match = RegExp(r'\((\d{4})').firstMatch(courseId);
      if (match != null) courseYear = int.tryParse(match.group(1)!);
    }

    return ZjuTimetableSession(
      courseId: courseId,
      courseName: courseName,
      teacher: teacher,
      location: location,
      dayOfWeek: SafeParse.int_(json['xqj'], defaultValue: 1).clamp(1, 7),
      periods: periods,
      weekRange: weekRange,
      semester: semester,
      courseYear: courseYear,
      isEnded: SafeParse.bool_(json['sfyjskc'], defaultValue: false),
      credit: SafeParse.double_(json['xf']),
    );
  }

  /// 从中枢缓存 JSON（[toJson] 产物）还原。
  factory ZjuTimetableSession.fromJson(Map<String, dynamic> json) {
    return ZjuTimetableSession(
      courseId: json['course_id']?.toString(),
      courseName:
          SafeParse.string(json['course_name'], defaultValue: '未命名课程'),
      teacher: json['teacher']?.toString(),
      location: json['location']?.toString(),
      dayOfWeek: SafeParse.int_(json['day_of_week'], defaultValue: 1).clamp(1, 7),
      periods: ((json['periods'] as List?) ?? const [])
          .map((e) => SafeParse.int_(e))
          .where((e) => e > 0)
          .toList(),
      weekRange: json['week_range']?.toString(),
      semester: SafeParse.int_(json['semester'], defaultValue: 0) == 0
          ? null
          : SafeParse.int_(json['semester'], defaultValue: 0),
      courseYear: json['course_year'] == null
          ? null
          : SafeParse.int_(json['course_year']),
      isEnded: SafeParse.bool_(json['is_ended'], defaultValue: false),
      credit: SafeParse.double_(json['credit']),
    );
  }

  Map<String, dynamic> toJson() => {
        'course_id': courseId,
        'course_name': courseName,
        'teacher': teacher,
        'location': location,
        'day_of_week': dayOfWeek,
        'periods': periods,
        'week_range': weekRange,
        'semester': semester,
        'course_year': courseYear,
        'is_ended': isEnded,
        'credit': credit,
      };
}
