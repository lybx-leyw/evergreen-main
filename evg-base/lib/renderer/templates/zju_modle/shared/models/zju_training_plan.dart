/// ZjuTrainingPlan — 教务（ZDBK）培养方案模型。
///
/// B3-zdbk（2026-08-12）自参考工程 `cp_evergreen_push/lib/core/models/
/// training_plan.dart` 拷入并前缀 `Zju`（规划 §5.6 防符号冲突）。
/// 保留 fromJson/toJson 双向桥接——fetcher 产出 JSON（数据中枢 jsonEncode
/// 缓存），renderer 侧 fromJson 还原。`rawJson` 仅供调试/全文搜索，
/// 不参与 toJson（缓存契约只序列化规范化字段）。
library;

import 'package:evergreen_base/core/utils/safe_parse.dart';

/// 一条培养方案信息。
class ZjuTrainingPlan {
  /// 教学计划号（jxjhh，用于 PDF 打印端点的主键）。
  final String? planNo;

  /// 培养方案 ID（pyfaxx_id）。
  final String? pyfaxxId;

  /// 方案名称（pyfamc）。
  final String planName;

  /// 专业名称（zymc）。
  final String? major;

  /// 年级代码（synj/nj，如 "2025"）。
  final String? grade;

  /// 学院名称（xy/xymc）。
  final String? college;

  /// 培养层次（pycc，本科/硕士/博士）。
  final String? level;

  /// 学制（xz，年）。
  final String? duration;

  /// 最低毕业学分（minxf）。
  final double minCredits;

  /// 已修学分（yxxf）。
  final double earnedCredits;

  /// 状态编码（zt）。
  final String? status;

  /// 培养方案备注（bz，含完整课程描述）。
  final String? remarks;

  /// 原始 JSON（供调试和全文搜索，不参与序列化）。
  final Map<String, dynamic> rawJson;

  const ZjuTrainingPlan({
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

  factory ZjuTrainingPlan.fromJson(Map<String, dynamic> json) {
    // 尝试多个字段名（不同 API 版本字段名可能不同，照抄参考实现）。
    String? _firstOf(List<String> keys) {
      for (final k in keys) {
        final v = SafeParse.string(json[k]);
        if (v.isNotEmpty) return v;
      }
      return null;
    }

    return ZjuTrainingPlan(
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

  /// 序列化（数据中枢缓存契约）——toJson→fromJson 可还原全部核心字段。
  Map<String, dynamic> toJson() => {
        'jxjhh': planNo,
        'pyfaxx_id': pyfaxxId,
        'pyfamc': planName,
        'zymc': major,
        'synj': grade,
        'xymc': college,
        'pycc': level,
        'xz': duration,
        'minxf': minCredits,
        'yxxf': earnedCredits,
        'zt': status,
        'bz': remarks,
      };

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
