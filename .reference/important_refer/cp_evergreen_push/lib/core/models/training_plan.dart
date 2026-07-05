/// 培养方案数据模型 — ZDBK 教务系统培养方案查询。
library;

import '../utils/safe_parse.dart';

/// 一条培养方案信息。
class TrainingPlan {
  /// 教学计划号（用于 PDF 打印端点的主键）。
  final String? planNo;

  /// 培养方案 ID（pyfaxx_id）。
  final String? pyfaxxId;

  /// 方案名称。
  final String planName;

  /// 专业名称。
  final String? major;

  /// 年级代码（如 "2025"）。
  final String? grade;

  /// 学院名称。
  final String? college;

  /// 培养层次（本科/硕士/博士）。
  final String? level;

  /// 学制（年）。
  final String? duration;

  /// 最低毕业学分。
  final double minCredits;

  /// 已修学分。
  final double earnedCredits;

  /// 状态编码。
  final String? status;

  /// 培养方案备注（含完整课程描述）。
  final String? remarks;

  /// 原始 JSON（供调试和全文搜索）。
  final Map<String, dynamic> rawJson;

  const TrainingPlan({
    this.planNo,
    this.pyfaxxId,
    required this.planName,
    this.major,
    this.grade,
    this.college,
    this.level,
    this.duration,
    this.minCredits = 0,
    this.earnedCredits = 0,
    this.status,
    this.remarks,
    this.rawJson = const {},
  });

  factory TrainingPlan.fromJson(Map<String, dynamic> json) {
    // 尝试多个字段名（不同 API 版本字段名可能不同）
    String? _firstOf(List<String> keys) {
      for (final k in keys) {
        final v = SafeParse.string(json[k]);
        if (v.isNotEmpty) return v;
      }
      return null;
    }

    return TrainingPlan(
      planNo: _firstOf(['jxjhh', 'pyfaxx_id', 'pyfabh', 'planNo']),
      pyfaxxId: SafeParse.string(json['pyfaxx_id']),
      planName: SafeParse.string(json['pyfamc'], defaultValue: '未命名方案'),
      major: _firstOf(['zymc', 'zymc_mc', 'major', 'zy_mc']),
      grade: _firstOf(['synj', 'nj', 'grade']),
      college: _firstOf(['xy', 'xymc', 'kkxy', 'xy_mc', 'college', 'dept']),
      level: SafeParse.string(json['pycc']),
      duration: SafeParse.string(json['xz']),
      minCredits: SafeParse.double_(json['minxf']),
      earnedCredits: SafeParse.double_(json['yxxf']),
      status: SafeParse.string(json['zt']),
      remarks: SafeParse.string(json['bz']),
      rawJson: json,
    );
  }

  String toShortDescription() {
    final parts = <String>[
      planName,
      if (major != null) major!,
      if (grade != null) grade!,
      if (minCredits > 0) '${minCredits}学分',
      if (college != null) college!,
    ];
    return parts.join(' · ');
  }
}
