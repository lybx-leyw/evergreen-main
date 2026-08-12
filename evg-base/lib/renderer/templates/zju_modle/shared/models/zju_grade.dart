/// ZjuGrade — 教务（ZDBK）成绩记录模型。
///
/// B3（2026-08-12）自参考工程 `cp_evergreen_push/lib/core/models/grade.dart`
/// 拷入并前缀 `Zju`（规划 §5.6：避免与 evg-base 现有符号冲突）。
/// 保留 fromJson/toJson 双向桥接——fetcher 产出 JSON（数据中枢 jsonEncode 缓存），
/// renderer 侧 fromJson 还原。SafeParse 直接复用 evg-base core 已有实现。
library;

import 'package:evergreen_base/core/utils/safe_parse.dart';

/// 五分制绩点的来源。
enum ZjuFivePointSource {
  /// ZDBK 权威 `jd` 字段（精确，优先使用）。
  jd,

  /// 本地从 `cj` 字段估算（回退，可能丢失精度）。
  fallback,
}

/// 一门成绩记录。映射 ZDBK 五分制成绩（优/良/中/及格/不及格）与百分制成绩
/// 到 4 套 GPA 刻度：5.0、4.3（标准）、4.0（legacy）、百分制。
///
/// 与参考实现一致：优先使用 ZDBK 权威 `jd`（绩点）字段，而非从原始成绩
/// 字符串用粗阈值重建——ZDBK 返回 4.8/4.5/4.2 等精确值。
class ZjuGrade {
  final String id; // 选课课号 xkkh，如 (2024-2025-1)-CS101-001
  final String name; // 课程名称 kcmc
  final double credit; // 学分 xf
  final String original; // 原始成绩串 cj："95"、"优"、"良好" 等
  final double fivePoint; // ZDBK `jd` 权威绩点（如 5.0、4.8、4.2、3.5、0.0）
  final ZjuFivePointSource fivePointSource; // 绩点来源

  /// 是否主修课程（主修成绩页拉取时标记）。
  bool major = false;

  ZjuGrade({
    required this.id,
    required this.name,
    required this.credit,
    required this.original,
    required this.fivePoint,
    this.fivePointSource = ZjuFivePointSource.fallback,
    this.major = false,
  });

  factory ZjuGrade.fromJson(Map<String, dynamic> json) {
    // 绩点来源判断：jd 必须是数字（int/double/可解析的数字字符串）；
    // 数组、对象、非数字字符串均视为无效 → 回退到本地估算。
    final jdRaw = json['jd'];
    double fp;
    ZjuFivePointSource source;

    bool isValidNumber(dynamic v) {
      if (v is num) return true;
      if (v is String && double.tryParse(v) != null) return true;
      return false;
    }

    if (isValidNumber(jdRaw)) {
      fp = SafeParse.double_(jdRaw);
      source = ZjuFivePointSource.jd;
    } else {
      fp = _scoreToFivePoint(SafeParse.string(json['cj']));
      source = ZjuFivePointSource.fallback;
    }

    return ZjuGrade(
      id: SafeParse.string(json['xkkh']),
      name: SafeParse.string(json['kcmc'], defaultValue: '未命名课程'),
      credit: SafeParse.double_(json['xf']),
      original: SafeParse.string(json['cj']),
      fivePoint: fp,
      fivePointSource: source,
      major: SafeParse.bool_(json['major']),
    );
  }

  factory ZjuGrade.fromScoresJson(Map<String, dynamic> json) {
    return ZjuGrade(
      id: SafeParse.string(json['courseId']),
      name: SafeParse.string(json['courseName'], defaultValue: '未命名课程'),
      credit: SafeParse.double_(json['credit']),
      original: SafeParse.string(json['hundredPoint']),
      fivePoint: SafeParse.double_(json['fivePoint']),
      fivePointSource: ZjuFivePointSource.fallback,
    );
  }

  /// 回退：把原始成绩串转五分制绩点（仅当 ZDBK `jd` 字段不可用时）。
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

  /// 序列化（数据中枢缓存契约）。`jd` 带出权威绩点，fromJson 可完整还原。
  Map<String, dynamic> toJson() => {
        'xkkh': id,
        'kcmc': name,
        'xf': credit,
        'cj': original,
        'jd': fivePoint,
        'major': major,
      };

  /// 是否应从 GPA 计算中排除。
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

  // ── 派生字段 ─────────────────────────────────────────────────────────

  /// 真实课程 ID——去掉重修后缀，使同一门课的不同修读记录共享分组键。
  /// `(2023-2024-2)-CS101-001` → `(2023-2024-2)-CS101`。
  String get realId {
    final match = RegExp(r'(\(.*\)-.*?)-.*').firstMatch(id);
    var key = match?.group(1);
    key ??= id.length < 22 ? id : id.substring(0, 22);
    return key;
  }

  /// 已获得学分——不及格 / 被排除课程计 0。
  double get earnedCredit {
    final creditIncluded = original != '弃修' &&
        original != '待录' &&
        original != '缓考' &&
        original != '无效';
    return (creditIncluded && (fivePoint != 0 || id.contains('xtwkc')))
        ? credit
        : 0.0;
  }

  /// 四分制（4.3 刻度）。>4.0 的五分制经映射表换算，其余原样通过。
  double get fourPointGpa {
    if (fivePoint > 4.0) {
      return _toFourPoint[fivePoint] ?? 4.0;
    }
    return fivePoint;
  }

  /// Legacy 四分制（4.0 刻度）。>4.0 封顶为 4.0，其余原样通过。
  double get fourPointLegacyGpa => fivePoint > 4.0 ? 4.0 : fivePoint;

  /// 百分制分数。中文成绩走映射表，数字成绩直接解析，无法解析返回 0。
  int get hundredPoint {
    // 1. 中文成绩映射
    final mapping = _toHundredPoint[original];
    if (mapping != null) return mapping;

    // 2. 直接数字解析
    final num = double.tryParse(original);
    if (num != null) return num.round();

    // 3. 正则提取首个数字串
    final match = RegExp(r'(\d+)').firstMatch(original);
    if (match != null) {
      return int.tryParse(match.group(1)!) ?? 0;
    }

    return 0;
  }

  // ── 静态映射表（自参考实现）──────────────────────────────────────────

  /// 五分制 → 4.3 刻度（仅 >4.0 需要换算）。
  static final Map<double, double> _toFourPoint = {
    5.0: 4.3,
    4.8: 4.2,
    4.5: 4.1,
    4.2: 4.0,
  };

  /// 中文/字母成绩 → 百分制。
  static final Map<String, int> _toHundredPoint = {
    'A+': 95,
    'A': 90,
    'A-': 87,
    'B+': 83,
    'B': 80,
    'B-': 77,
    'C+': 73,
    'C': 70,
    'C-': 67,
    'D': 60,
    'F': 0,
    '优秀': 90,
    '良好': 80,
    '中等': 70,
    '及格': 60,
    '不及格': 0,
    '合格': 75,
    '不合格': 0,
    '弃修': 0,
    '缺考': 0,
    '缓考': 0,
    '待录': 0,
    '无效': 0,
  };
}
