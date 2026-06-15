import 'dart:math';

import '../utils/safe_parse.dart';

/// FivePoint 绩点的来源。
enum FivePointSource {
  /// ZDBK 权威 `jd` 字段（精确，优先使用）。
  jd,

  /// 本地从 `cj` 字段估算（回退，可能丢失精度）。
  fallback,
}

/// Grade model — strict port of Celechron's `grade.dart`.
///
/// Maps ZDBK five-point grades (优/良/中/及格/不及格) and hundred-point scores
/// to four GPA scales: 5.0, 4.3 (standard), 4.0 (legacy), and hundred-point.
///
/// Unlike the old implementation which reconstructed `fivePoint` from the raw
/// score string using coarse thresholds (>=90→5, >=80→4, ...), this version
/// uses ZDBK's authoritative `jd` (绩点) field directly, matching Celechron.
/// This preserves precision: ZDBK returns values like 4.8, 4.5, 4.2 for A-level
/// grades, which the old int-based mapping collapsed to a flat 5.0.
class Grade {
  final String id;
  final String name;
  final double credit;
  final String original; // Raw score string: "95", "优", "良好", etc.

  /// Five-point GPA from ZDBK's `jd` field (e.g. 5.0, 4.8, 4.2, 3.5, 0.0).
  final double fivePoint;

  /// 绩点来源：ZDBK 权威 `jd` 字段 vs 本地估算回退。
  final FivePointSource fivePointSource;

  bool major = false;

  Grade({
    required this.id,
    required this.name,
    required this.credit,
    required this.original,
    required this.fivePoint,
    this.fivePointSource = FivePointSource.fallback,
    this.major = false,
  });

  factory Grade.fromJson(Map<String, dynamic> json) {
    // 绩点来源判断：jd 必须是数字（int/double/可解析的数字字符串）
    // 数组、对象、非数字字符串均视为无效 → 回退到本地估算
    final jdRaw = json['jd'];
    double fp;
    FivePointSource source;

    bool _isValidNumber(dynamic v) {
      if (v is num) return true;
      if (v is String && double.tryParse(v) != null) return true;
      return false;
    }

    if (_isValidNumber(jdRaw)) {
      fp = SafeParse.double_(jdRaw);
      source = FivePointSource.jd;
    } else {
      fp = _scoreToFivePoint(SafeParse.string(json['cj']));
      source = FivePointSource.fallback;
    }

    return Grade(
      id: SafeParse.string(json['xkkh']),
      name: SafeParse.string(json['kcmc'], defaultValue: '未命名课程'),
      credit: SafeParse.double_(json['xf']),
      original: SafeParse.string(json['cj']),
      fivePoint: fp,
      fivePointSource: source,
    );
  }

  factory Grade.fromScoresJson(Map<String, dynamic> json) {
    return Grade(
      id: SafeParse.string(json['courseId']),
      name: SafeParse.string(json['courseName'], defaultValue: '未命名课程'),
      credit: SafeParse.double_(json['credit']),
      original: SafeParse.string(json['hundredPoint']),
      fivePoint: SafeParse.double_(json['fivePoint']),
      fivePointSource: FivePointSource.fallback,
    );
  }

  /// Fallback: convert a raw score string to five-point GPA.
  /// Only used when ZDBK's `jd` field is unavailable.
  static double _scoreToFivePoint(String score) {
    if (score == '优' || score == '优秀') return 5.0;
    if (score == '良' || score == '良好') return 4.0;
    if (score == '中' || score == '中等') return 3.0;
    if (score == '及格' || score == '合格') return 2.0;
    if (score == '不及格' || score == '不合格') return 0.0;

    final numScore = double.tryParse(score);
    if (numScore != null) {
      if (numScore >= 90) return 5.0;
      if (numScore >= 80) return 4.0;
      if (numScore >= 70) return 3.0;
      if (numScore >= 60) return 2.0;
      return 0.0;
    }
    return 0.0;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'credit': credit,
        'original': original,
        'fivePoint': fivePoint,
      };

  /// Whether this grade should be excluded from GPA calculation.
  bool get isExcludedFromGpa {
    final s = original;
    return s == '弃修' ||
        s == '待录' ||
        s == '缓考' ||
        s == '无效' ||
        s == '合格' ||
        s == '不合格' ||
        id.contains('xtwkc') ||
        credit <= 0;
  }

  // ── Derived fields ────────────────────────────────────────────────

  /// Real course ID — strips the retake suffix so different attempts of
  /// the same course share a common key for first/highest-pick strategies.
  ///
  /// Celechron: `realId` normalises `(2023-2024-2)-CS101-001` → `(2023-2024-2)-CS101`.
  String get realId {
    final match = RegExp(r'(\(.*\)-.*?)-.*').firstMatch(id);
    var key = match?.group(1);
    key ??= id.length < 22 ? id : id.substring(0, 22);
    return key;
  }

  /// Earned credits — 0 for failed / excluded courses.
  /// Celechron: `earnedCredit = (creditIncluded && (fivePoint != 0 || id.contains('xtwkc'))) ? credit : 0.0`
  double get earnedCredit {
    final creditIncluded = original != '弃修' &&
        original != '待录' &&
        original != '缓考' &&
        original != '无效';
    return (creditIncluded && (fivePoint != 0 || id.contains('xtwkc')))
        ? credit
        : 0.0;
  }

  // ── 4.3-scale GPA (四分制) ────────────────────────────────────────────

  /// Convert five-point GPA to the 4.3 scale (Celechron mapping).
  ///
  /// Values > 4.0 on the five-point scale are mapped via `_toFourPoint`:
  ///   5.0 → 4.3, 4.8 → 4.2, 4.5 → 4.1, 4.2 → 4.0
  /// Values ≤ 4.0 pass through as-is (e.g. a five-point 3.5 → 4.3-scale 3.5).
  double get fourPointGpa {
    if (fivePoint > 4.0) {
      return _toFourPoint[fivePoint] ?? 4.0;
    }
    return fivePoint;
  }

  // ── Legacy 4.0-scale GPA ─────────────────────────────────────────────

  /// Convert five-point GPA to the legacy 4.0 scale (Celechron).
  ///
  /// Values > 4.0 on the five-point scale cap at 4.0.
  /// Values ≤ 4.0 pass through as-is.
  double get fourPointLegacyGpa => fivePoint > 4.0 ? 4.0 : fivePoint;

  // ── Hundred-point score ──────────────────────────────────────────────

  /// Extract hundred-point score from the original field.
  ///
  /// Celechron's approach: use `_toHundredPoint` mapping for Chinese grades,
  /// fall back to digit extraction for numeric scores.
  /// Returns 0 for unparseable values (rather than null, which would cause
  /// downstream GPA calculations to silently produce 0.0).
  int get hundredPoint {
    // 1. Check Chinese-grade mapping
    final mapping = _toHundredPoint[original];
    if (mapping != null) return mapping;

    // 2. Direct numeric parse
    final num = double.tryParse(original);
    if (num != null) return num.round();

    // 3. Regex extraction of first digit sequence
    final match = RegExp(r'(\d+)').firstMatch(original);
    if (match != null) {
      return int.tryParse(match.group(1)!) ?? 0;
    }

    return 0;
  }

  // ── Static lookup tables (from Celechron) ────────────────────────────

  /// Five-point GPA → 4.3-scale mapping (for values > 4.0).
  static final Map<double, double> _toFourPoint = {
    5.0: 4.3,
    4.8: 4.2,
    4.5: 4.1,
    4.2: 4.0,
  };

  /// Chinese/letter grades → hundred-point score.
  static final Map<String, int> _toHundredPoint = {
    "A+": 95,
    "A": 90,
    "A-": 87,
    "B+": 83,
    "B": 80,
    "B-": 77,
    "C+": 73,
    "C": 70,
    "C-": 67,
    "D": 60,
    "F": 0,
    "优秀": 90,
    "良好": 80,
    "中等": 70,
    "及格": 60,
    "不及格": 0,
    "合格": 75,
    "不合格": 0,
    "弃修": 0,
    "缺考": 0,
    "缓考": 0,
    "待录": 0,
    "无效": 0,
  };
}
