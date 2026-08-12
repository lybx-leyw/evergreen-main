/// ZjuGpaCalculator — 教务成绩 GPA 计算器。
///
/// B3（2026-08-12）自参考工程 `cp_evergreen_push/lib/core/utils/gpa_calculator.dart`
/// 拷入并前缀 `Zju`（规划 §5.6）。支持 4 套刻度：5.0、4.3（标准）、4.0（legacy）、
/// 百分制；按课程 ID 分组支持「首次修读」/「最高分」两种策略。
library;

import '../models/zju_grade.dart';

/// 一套 GPA 计算结果（4 刻度 + 已获学分）。
class ZjuGpaResult {
  final double fivePoint;
  final double fourPoint;
  final double fourPointLegacy;
  final double hundredPoint;
  final double earnedCredits;

  const ZjuGpaResult({
    required this.fivePoint,
    required this.fourPoint,
    required this.fourPointLegacy,
    required this.hundredPoint,
    required this.earnedCredits,
  });

  /// 序列化（数据中枢缓存契约，fetcher 输出）。
  Map<String, dynamic> toJson() => {
        'five_point': fivePoint,
        'four_point': fourPoint,
        'four_point_legacy': fourPointLegacy,
        'hundred_point': hundredPoint,
        'earned_credits': earnedCredits,
      };

  /// 从缓存 JSON 还原。
  factory ZjuGpaResult.fromJson(Map<String, dynamic> json) {
    return ZjuGpaResult(
      fivePoint: (json['five_point'] as num?)?.toDouble() ?? 0.0,
      fourPoint: (json['four_point'] as num?)?.toDouble() ?? 0.0,
      fourPointLegacy:
          (json['four_point_legacy'] as num?)?.toDouble() ?? 0.0,
      hundredPoint: (json['hundred_point'] as num?)?.toDouble() ?? 0.0,
      earnedCredits: (json['earned_credits'] as num?)?.toDouble() ?? 0.0,
    );
  }

  @override
  String toString() =>
      'GPA: 5.0=${fivePoint.toStringAsFixed(2)} '
      '4.3=${fourPoint.toStringAsFixed(2)} '
      '4.0=${fourPointLegacy.toStringAsFixed(2)} '
      '100=${hundredPoint.toStringAsFixed(1)} '
      '(${earnedCredits.toStringAsFixed(1)}cr)';
}

/// GPA 计算器——纯静态方法，无状态。
class ZjuGpaCalculator {
  ZjuGpaCalculator._();

  /// 计算一组成绩的 GPA（4 刻度 + 已获学分）。
  static ZjuGpaResult calculateGpa(Iterable<ZjuGrade> grades) {
    final list = grades.toList();

    // 已获学分（全部课程，GPA 过滤前统计）
    final earnedCredits = list.fold<double>(0, (sum, g) => sum + g.earnedCredit);

    final filtered = list.where((g) => !g.isExcludedFromGpa).toList();
    if (filtered.isEmpty) {
      return ZjuGpaResult(
        fivePoint: 0.0,
        fourPoint: 0.0,
        fourPointLegacy: 0.0,
        hundredPoint: 0.0,
        earnedCredits: earnedCredits,
      );
    }

    double totalCredit = 0;
    double weightedFive = 0;
    double weightedFour = 0;
    double weightedLegacy = 0;
    double weightedHundred = 0;

    for (final grade in filtered) {
      final hp = grade.hundredPoint;
      totalCredit += grade.credit;
      weightedFive += grade.fivePoint * grade.credit;
      weightedFour += grade.fourPointGpa * grade.credit;
      weightedLegacy += grade.fourPointLegacyGpa * grade.credit;
      weightedHundred += hp * grade.credit;
    }

    return ZjuGpaResult(
      fivePoint: totalCredit > 0 ? weightedFive / totalCredit : 0.0,
      fourPoint: totalCredit > 0 ? weightedFour / totalCredit : 0.0,
      fourPointLegacy:
          totalCredit > 0 ? weightedLegacy / totalCredit : 0.0,
      hundredPoint: totalCredit > 0 ? weightedHundred / totalCredit : 0.0,
      earnedCredits: earnedCredits,
    );
  }

  /// 按课程权重计算 GPA。
  static ZjuGpaResult calculateWeightedGpa(
    Iterable<ZjuGrade> grades,
    Map<String, double> weightMap,
  ) {
    final list = grades.toList();
    final earnedCredits = list.fold<double>(0, (sum, g) => sum + g.earnedCredit);

    final filtered = list.where((g) => !g.isExcludedFromGpa).toList();
    if (filtered.isEmpty) {
      return ZjuGpaResult(
        fivePoint: 0.0,
        fourPoint: 0.0,
        fourPointLegacy: 0.0,
        hundredPoint: 0.0,
        earnedCredits: earnedCredits,
      );
    }

    double totalWeightedCredit = 0;
    double weightedFive = 0;
    double weightedFour = 0;
    double weightedLegacy = 0;
    double weightedHundred = 0;

    for (final grade in filtered) {
      final weight = weightMap[grade.id] ?? 1.0;
      final effectiveCredit = grade.credit * weight;
      final hp = grade.hundredPoint;
      totalWeightedCredit += effectiveCredit;
      weightedFive += grade.fivePoint * effectiveCredit;
      weightedFour += grade.fourPointGpa * effectiveCredit;
      weightedLegacy += grade.fourPointLegacyGpa * effectiveCredit;
      weightedHundred += hp * effectiveCredit;
    }

    return ZjuGpaResult(
      fivePoint:
          totalWeightedCredit > 0 ? weightedFive / totalWeightedCredit : 0.0,
      fourPoint:
          totalWeightedCredit > 0 ? weightedFour / totalWeightedCredit : 0.0,
      fourPointLegacy: totalWeightedCredit > 0
          ? weightedLegacy / totalWeightedCredit
          : 0.0,
      hundredPoint: totalWeightedCredit > 0
          ? weightedHundred / totalWeightedCredit
          : 0.0,
      earnedCredits: earnedCredits,
    );
  }

  /// 按真实课程 ID 分组（重修归一化）。
  static Map<String, List<ZjuGrade>> groupByCourseId(
      Iterable<ZjuGrade> grades) {
    final map = <String, List<ZjuGrade>>{};
    for (final grade in grades) {
      map.putIfAbsent(grade.realId, () => []).add(grade);
    }
    return map;
  }

  /// 取每门课首次修读成绩（保研口径）。
  static List<ZjuGrade> pickFirstAttempt(Iterable<ZjuGrade> grades) {
    final groups = groupByCourseId(grades);
    return groups.values.map((group) => group.first).toList();
  }

  /// 取每门课百分制最高的一次成绩（出国口径）。
  static List<ZjuGrade> pickHighestAttempt(Iterable<ZjuGrade> grades) {
    final groups = groupByCourseId(grades);
    return groups.values.map((group) {
      return group.reduce((a, b) =>
          a.hundredPoint >= b.hundredPoint ? a : b);
    }).toList();
  }
}
