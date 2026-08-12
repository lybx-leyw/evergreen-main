/// ZjuScoreColors — 成绩/GPA 配色工具。
///
/// B3-scores（2026-08-12）自参考工程 `cp_evergreen_push/lib/core/config/theme.dart`
/// 的 `AppTheme.scoreColor` / `AppTheme.gpaColor` 及品牌色常量移植，前缀 `Zju`
/// 防冲突（规划 §5.6）。仅提取成绩页面所需部分，不引入完整主题。
library;

import 'dart:ui' show Color;

/// 成绩/GPA 相关配色（与参考实现一致）。
abstract final class ZjuScoreColors {
  // ── 品牌色 ─────────────────────────────────────────────
  static const Color zjuBlue = Color(0xFF1677FF);
  static const Color successGreen = Color(0xFF52C41A);
  static const Color warningOrange = Color(0xFFFA8C16);
  static const Color dangerRed = Color(0xFFFF4D4F);

  /// 分数颜色（与参考原始 CSS 阈值一致）。
  ///
  /// 传五分制绩点（0-5）：≥9 绿 → ≥7 蓝 → ≥5 橙 → 红。
  static Color scoreColor(double? score) {
    if (score == null) return const Color(0xFF9E9E9E); // grey
    if (score >= 9.0) return successGreen;
    if (score >= 7.0) return zjuBlue;
    if (score >= 5.0) return warningOrange;
    return dangerRed;
  }

  /// GPA 颜色。
  static Color gpaColor(double gpa) {
    if (gpa >= 4.5) return successGreen;
    if (gpa >= 3.5) return zjuBlue;
    if (gpa >= 2.5) return warningOrange;
    return dangerRed;
  }
}
