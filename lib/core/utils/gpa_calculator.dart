import '../models/grade.dart';

/// GPA Calculator — strict port of Celechron's `gpa_helper.dart`.
///
/// Computes GPA across 4 scales: 5.0, 4.3 (standard), 4.0 (legacy), and hundred-point.
/// Supports grouping by course ID with first-attempt or highest-attempt strategies.
class GpaCalculator {
  /// Calculate GPA for a list of grades.
  ///
  /// Returns [fivePoint, fourPoint, fourPointLegacy, hundredPoint] + earned credits.
  ///
  /// Celechron reference: uses `grade.gpaIncluded` to filter, `grade.earnedCredit`
  /// for the credit tally, and `grade.fourPoint` / `grade.fourPointLegacy` / 
  /// `grade.hundredPoint` as precomputed fields.
  static GpaResult calculateGpa(Iterable<Grade> grades) {
    final list = grades.toList();

    // Total earned credits (all courses, before GPA-filtering)
    final earnedCredits = list.fold<double>(0, (sum, g) => sum + g.earnedCredit);

    final filtered = list.where((g) => !g.isExcludedFromGpa).toList();
    if (filtered.isEmpty) {
      return GpaResult(
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

    return GpaResult(
      fivePoint: totalCredit > 0 ? weightedFive / totalCredit : 0.0,
      fourPoint: totalCredit > 0 ? weightedFour / totalCredit : 0.0,
      fourPointLegacy: totalCredit > 0 ? weightedLegacy / totalCredit : 0.0,
      hundredPoint: totalCredit > 0 ? weightedHundred / totalCredit : 0.0,
      earnedCredits: earnedCredits,
    );
  }

  /// Calculate GPA with per-course weights.
  static GpaResult calculateWeightedGpa(
    Iterable<Grade> grades,
    Map<String, double> weightMap,
  ) {
    final list = grades.toList();

    // Total earned credits (all courses, before GPA-filtering)
    final earnedCredits = list.fold<double>(0, (sum, g) => sum + g.earnedCredit);

    final filtered = list.where((g) => !g.isExcludedFromGpa).toList();
    if (filtered.isEmpty) {
      return GpaResult(
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

    return GpaResult(
      fivePoint: totalWeightedCredit > 0 ? weightedFive / totalWeightedCredit : 0.0,
      fourPoint: totalWeightedCredit > 0 ? weightedFour / totalWeightedCredit : 0.0,
      fourPointLegacy:
          totalWeightedCredit > 0 ? weightedLegacy / totalWeightedCredit : 0.0,
      hundredPoint:
          totalWeightedCredit > 0 ? weightedHundred / totalWeightedCredit : 0.0,
      earnedCredits: earnedCredits,
    );
  }

  /// Group grades by real course ID (retake-normalised).
  ///
  /// Uses [Grade.realId] so that different attempts of the same course
  /// (e.g. first take and retake) land in the same group.
  static Map<String, List<Grade>> groupByCourseId(Iterable<Grade> grades) {
    final map = <String, List<Grade>>{};
    for (final grade in grades) {
      map.putIfAbsent(grade.realId, () => []).add(grade);
    }
    return map;
  }

  /// Pick the first attempt of each course (domestic GPA / 保研).
  static List<Grade> pickFirstAttempt(Iterable<Grade> grades) {
    final groups = groupByCourseId(grades);
    return groups.values.map((group) => group.first).toList();
  }

  /// Pick the highest hundred-point attempt of each course (abroad GPA / 出国).
  static List<Grade> pickHighestAttempt(Iterable<Grade> grades) {
    final groups = groupByCourseId(grades);
    return groups.values.map((group) {
      return group.reduce((a, b) =>
          a.hundredPoint >= b.hundredPoint ? a : b);
    }).toList();
  }
}

/// Result of a GPA calculation across 4 scales.
class GpaResult {
  final double fivePoint;
  final double fourPoint;
  final double fourPointLegacy;
  final double hundredPoint;
  final double earnedCredits;

  const GpaResult({
    required this.fivePoint,
    required this.fourPoint,
    required this.fourPointLegacy,
    required this.hundredPoint,
    required this.earnedCredits,
  });

  @override
  String toString() =>
      'GPA: 5.0=${fivePoint.toStringAsFixed(2)} 4.3=${fourPoint.toStringAsFixed(2)} 4.0=${fourPointLegacy.toStringAsFixed(2)} 100=${hundredPoint.toStringAsFixed(1)} (${earnedCredits.toStringAsFixed(1)}cr)';
}
