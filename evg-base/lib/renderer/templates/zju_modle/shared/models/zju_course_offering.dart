/// ZjuCourseOffering — 教务（ZDBK）开课情况模型。
///
/// B3-zdbk（2026-08-12）自参考工程 `cp_evergreen_push/lib/core/models/
/// course_offering.dart` 拷入并前缀 `Zju`（规划 §5.6 防符号冲突）。
/// 保留 fromJson/toJson 双向桥接——fetcher 产出 JSON（数据中枢 jsonEncode
/// 缓存），renderer 侧 fromJson 还原。SafeParse 直接复用 evg-base core。
library;

import 'package:evergreen_base/core/utils/safe_parse.dart';

/// 一门开课信息。
class ZjuCourseOffering {
  /// 课程代码（kcdm）。
  final String? courseCode;

  /// 课程名称（kcmc）。
  final String courseName;

  /// 教师姓名（jsxm）。
  final String? teacher;

  /// 上课地点（skdd）。
  final String? location;

  /// 上课时间（sksj）。
  final String? schedule;

  /// 学分（xf）。
  final double credits;

  /// 总学时（zxss）。
  final int totalHours;

  /// 开课学院（kkxy）。
  final String? college;

  /// 课程性质（kcxz，必修/选修）。
  final String? courseType;

  /// 课程类别（kclb）。
  final String? courseCategory;

  /// 课程归属（kcgs）。
  final String? courseBelong;

  /// 学年（xn）。
  final String? academicYear;

  /// 学期（xxq）。
  final String? semester;

  /// 考试时间（kssj）。
  final String? examTime;

  /// 专业名称（zymc）。
  final String? major;

  /// 教学计划号（jxjhh）。
  final String? planNo;

  /// 选课课号（xkkh）。
  final String? courseSelectNo;

  const ZjuCourseOffering({
    this.courseCode,
    required this.courseName,
    this.teacher,
    this.location,
    this.schedule,
    this.credits = 0,
    this.totalHours = 0,
    this.college,
    this.courseType,
    this.courseCategory,
    this.courseBelong,
    this.academicYear,
    this.semester,
    this.examTime,
    this.major,
    this.planNo,
    this.courseSelectNo,
  });

  factory ZjuCourseOffering.fromJson(Map<String, dynamic> json) {
    return ZjuCourseOffering(
      courseCode: SafeParse.string(json['kcdm']),
      courseName: SafeParse.string(json['kcmc'], defaultValue: '未命名课程'),
      teacher: SafeParse.string(json['jsxm']),
      location: SafeParse.string(json['skdd']),
      schedule: SafeParse.string(json['sksj']),
      credits: SafeParse.double_(json['xf']),
      totalHours: SafeParse.int_(json['zxss']),
      college: SafeParse.string(json['kkxy']),
      courseType: SafeParse.string(json['kcxz']),
      courseCategory: SafeParse.string(json['kclb']),
      courseBelong: SafeParse.string(json['kcgs']),
      academicYear: SafeParse.string(json['xn']),
      semester: SafeParse.string(json['xxq']),
      examTime: SafeParse.string(json['kssj']),
      major: SafeParse.string(json['zymc']),
      planNo: SafeParse.string(json['jxjhh']),
      courseSelectNo: SafeParse.string(json['xkkh']),
    );
  }

  /// 序列化（数据中枢缓存契约）——字段名与 ZDBK 原始 key 一致，fromJson 可还原。
  Map<String, dynamic> toJson() => {
        'kcdm': courseCode,
        'kcmc': courseName,
        'jsxm': teacher,
        'skdd': location,
        'sksj': schedule,
        'xf': credits,
        'zxss': totalHours,
        'kkxy': college,
        'kcxz': courseType,
        'kclb': courseCategory,
        'kcgs': courseBelong,
        'xn': academicYear,
        'xxq': semester,
        'kssj': examTime,
        'zymc': major,
        'jxjhh': planNo,
        'xkkh': courseSelectNo,
      };

  /// 简短的文字描述（供 Agent 工具使用）。
  String toShortDescription() {
    final parts = <String>[
      courseName,
      if (teacher != null) teacher!,
      if (schedule != null && schedule!.isNotEmpty) schedule!,
      if (location != null && location!.isNotEmpty) location!,
      if (credits > 0) '${credits}学分',
    ];
    return parts.join(' · ');
  }
}
