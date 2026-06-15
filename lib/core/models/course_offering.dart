/// 开课情况数据模型 — ZDBK 教务系统课程安排。
///
/// 字段名映射自 jqGrid colModel 和实际 API 返回。
library;

import '../utils/safe_parse.dart';

/// 一门开课信息。
class CourseOffering {
  /// 课程代码。
  final String? courseCode;

  /// 课程名称。
  final String courseName;

  /// 教师姓名。
  final String? teacher;

  /// 上课地点。
  final String? location;

  /// 上课时间。
  final String? schedule;

  /// 学分。
  final double credits;

  /// 总学时。
  final int totalHours;

  /// 开课学院。
  final String? college;

  /// 课程性质（必修/选修）。
  final String? courseType;

  /// 课程类别。
  final String? courseCategory;

  /// 课程归属。
  final String? courseBelong;

  /// 学年。
  final String? academicYear;

  /// 学期。
  final String? semester;

  /// 考试时间。
  final String? examTime;

  /// 专业名称。
  final String? major;

  /// 教学计划号。
  final String? planNo;

  /// 选课课号。
  final String? courseSelectNo;

  const CourseOffering({
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

  factory CourseOffering.fromJson(Map<String, dynamic> json) {
    return CourseOffering(
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
