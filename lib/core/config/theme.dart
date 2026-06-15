import 'package:flutter/material.dart';

/// 主题变体：系统跟随 / 默认亮色 / 默认暗色 / 绿意不息 / 黎语未央。
enum ThemeVariant { system, light, dark, evergreen, liyu, highContrast }

/// Evergreen 双风格主题系统。
///
/// 亮色：温暖白底、柔和阴影、清晰层次。
/// 暗色：GitHub 风格暗底、低对比边框、蓝紫调点缀。
/// 统一使用 ZJU 蓝 (#1677FF) 作为 seed color。
class AppTheme {
  // ─── 品牌色 ─────────────────────────────────────────────
  static const Color zjuBlue = Color(0xFF1677FF);
  static const Color zjuBlueLight = Color(0xFF4096FF);
  static const Color zjuBlueDark = Color(0xFF0958D9);

  // 绿意不息 — 团队专属绿
  static const Color evergreenGreen = Color(0xFF2DA44E);
  static const Color evergreenGreenLight = Color(0xFF3FB950);
  static const Color evergreenGreenDark = Color(0xFF1A7F37);

  // 黎语未央 — 个人专属红
  static const Color liyuRed = Color(0xFFCF222E);
  static const Color liyuRedLight = Color(0xFFFF6B6B);
  static const Color liyuRedDark = Color(0xFFA0111F);

  static const Color successGreen = Color(0xFF52C41A);
  static const Color successGreenDark = Color(0xFF3CB815);
  static const Color warningOrange = Color(0xFFFA8C16);
  static const Color warningOrangeDark = Color(0xFFDD7A0F);
  static const Color dangerRed = Color(0xFFFF4D4F);
  static const Color dangerRedDark = Color(0xFFE03E3E);
  static const Color accentPurple = Color(0xFF722ED1);

  // ─── 亮色主题 ───────────────────────────────────────────

  static ThemeData get lightTheme {
    const surface = Color(0xFFFFFFFF);
    const surfaceVariant = Color(0xFFF2F3F5);
    const background = Color(0xFFF5F6F8);
    const onSurface = Color(0xFF1A1D21);
    const onSurfaceVariant = Color(0xFF656D78);
    const outline = Color(0xFFD0D5DD);
    const dividerColor = Color(0xFFE8EAED);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorSchemeSeed: zjuBlue,
      scaffoldBackgroundColor: background,

      // ── AppBar ──
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: surface,
        foregroundColor: onSurface,
        surfaceTintColor: Colors.transparent,
      ),

      // ── 卡片 ──
      cardTheme: CardThemeData(
        elevation: 0,
        shadowColor: Colors.black.withValues(alpha: 0.04),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: outline, width: 0.5),
        ),
        color: surface,
      ),

      // ── 底部导航 ──
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        shadowColor: Colors.transparent,
        backgroundColor: surface,
        indicatorColor: zjuBlue.withValues(alpha: 0.12),
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: zjuBlue);
          }
          return TextStyle(fontSize: 12, color: onSurfaceVariant);
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: zjuBlue, size: 24);
          }
          return IconThemeData(color: onSurfaceVariant, size: 24);
        }),
      ),

      // ── 输入框 ──
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceVariant,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: outline.withValues(alpha: 0.7)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: zjuBlue, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: dangerRed),
        ),
        labelStyle: TextStyle(color: onSurfaceVariant),
        hintStyle: TextStyle(color: onSurfaceVariant.withValues(alpha: 0.6)),
      ),

      // ── 按钮 ──
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          shadowColor: Colors.transparent,
          backgroundColor: zjuBlue,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: zjuBlue,
          side: const BorderSide(color: zjuBlue),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: zjuBlue,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),

      // ── 分割线 ──
      dividerTheme: const DividerThemeData(
        space: 1,
        thickness: 0.5,
        color: dividerColor,
      ),

      // ── 列表 ──
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        titleTextStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: onSurface),
        subtitleTextStyle: TextStyle(fontSize: 13, color: onSurfaceVariant),
        iconColor: onSurfaceVariant,
      ),

      // ── Chip ──
      chipTheme: ChipThemeData(
        backgroundColor: surfaceVariant,
        labelStyle: const TextStyle(fontSize: 13, color: onSurface),
        side: const BorderSide(color: outline, width: 0.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),

      // ── SnackBar ──
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF323232),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        contentTextStyle: const TextStyle(fontSize: 14, color: Color(0xFFFFFFFF)),
      ),

      // ── Dialog ──
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titleTextStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: onSurface),
      ),
    );
  }

  // ─── 暗色主题 ───────────────────────────────────────────

  static ThemeData get darkTheme {
    const surface = Color(0xFF161B22);
    const surfaceVariant = Color(0xFF21262D);
    const background = Color(0xFF0D1117);
    const onSurface = Color(0xFFE6EDF3);
    const onSurfaceVariant = Color(0xFF8B949E);
    const outline = Color(0xFF30363D);
    const dividerColor = Color(0xFF21262D);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: zjuBlue,
        brightness: Brightness.dark,
        primaryContainer: const Color(0xFF1A3A6E),
        surfaceContainerLow: const Color(0xFF121820),
      ),
      scaffoldBackgroundColor: background,

      // ── AppBar ──
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: surface,
        foregroundColor: onSurface,
        surfaceTintColor: Colors.transparent,
      ),

      // ── 卡片 ──
      cardTheme: CardThemeData(
        elevation: 0,
        shadowColor: Colors.black.withValues(alpha: 0.3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: outline, width: 0.5),
        ),
        color: surface,
      ),

      // ── 底部导航 ──
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        shadowColor: Colors.transparent,
        backgroundColor: surface,
        indicatorColor: zjuBlue.withValues(alpha: 0.25),
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: zjuBlueLight);
          }
          return TextStyle(fontSize: 12, color: onSurfaceVariant);
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: zjuBlueLight, size: 24);
          }
          return IconThemeData(color: onSurfaceVariant, size: 24);
        }),
      ),

      // ── 输入框 ──
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF0D1117),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: outline.withValues(alpha: 0.7)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: zjuBlueLight, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: dangerRedDark),
        ),
        labelStyle: TextStyle(color: onSurfaceVariant),
        hintStyle: TextStyle(color: onSurfaceVariant.withValues(alpha: 0.5)),
      ),

      // ── 按钮 ──
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          shadowColor: Colors.transparent,
          backgroundColor: zjuBlue,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: zjuBlueLight,
          side: const BorderSide(color: zjuBlueLight),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: zjuBlueLight,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),

      // ── 分割线 ──
      dividerTheme: const DividerThemeData(
        space: 1,
        thickness: 0.5,
        color: dividerColor,
      ),

      // ── 列表 ──
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        titleTextStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: onSurface),
        subtitleTextStyle: TextStyle(fontSize: 13, color: onSurfaceVariant),
        iconColor: onSurfaceVariant,
      ),

      // ── Chip ──
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFF21262D),
        labelStyle: const TextStyle(fontSize: 13, color: onSurface),
        side: const BorderSide(color: outline, width: 0.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),

      // ── SnackBar ──
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFFE0E0E0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        contentTextStyle: const TextStyle(fontSize: 14, color: Color(0xFF1A1D21)),
      ),

      // ── Dialog ──
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titleTextStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: onSurface),
        backgroundColor: const Color(0xFF21262D),
      ),
    );
  }

  // ─── 自定义主题：绿意不息风 ─────────────────────────────

  /// 绿意不息风 — 亮色绿调，为绿意不息团队定制。
  static ThemeData get evergreenTheme => _buildCustomLightTheme(
        seed: evergreenGreen,
        seedLight: evergreenGreenLight,
        seedDark: evergreenGreenDark,
      );

  // ─── 自定义主题：黎语未央风 ─────────────────────────────

  /// 黎语未央风 — 亮色红调，为黎语未央定制。
  static ThemeData get liyuTheme => _buildCustomLightTheme(
        seed: liyuRed,
        seedLight: liyuRedLight,
        seedDark: liyuRedDark,
      );

  // ─── 主题构造辅助 ───────────────────────────────────────

  /// 用指定色构建亮色主题（复用亮色主题的结构，仅换 seed）。
  static ThemeData _buildCustomLightTheme({
    required Color seed,
    required Color seedLight,
    required Color seedDark,
  }) {
    const surface = Color(0xFFFFFFFF);
    const surfaceVariant = Color(0xFFF2F3F5);
    const background = Color(0xFFF5F6F8);
    const onSurface = Color(0xFF1A1D21);
    const onSurfaceVariant = Color(0xFF656D78);
    const outline = Color(0xFFD0D5DD);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorSchemeSeed: seed,
      scaffoldBackgroundColor: background,
      appBarTheme: const AppBarTheme(
        centerTitle: false, elevation: 0, scrolledUnderElevation: 1,
        backgroundColor: surface, foregroundColor: onSurface,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shadowColor: Colors.black.withValues(alpha: 0.04),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: outline, width: 0.5),
        ),
        color: surface,
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0, shadowColor: Colors.transparent,
        backgroundColor: surface, surfaceTintColor: Colors.transparent,
        indicatorColor: seed.withValues(alpha: 0.12),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: seed);
          }
          return const TextStyle(fontSize: 12, color: onSurfaceVariant);
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: seed, size: 24);
          }
          return const IconThemeData(color: onSurfaceVariant, size: 24);
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true, fillColor: surfaceVariant,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: outline.withValues(alpha: 0.7)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: seed, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: dangerRed),
        ),
        labelStyle: const TextStyle(color: onSurfaceVariant),
        hintStyle: TextStyle(color: onSurfaceVariant.withValues(alpha: 0.6)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0, shadowColor: Colors.transparent,
          backgroundColor: seed, foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: seed, side: BorderSide(color: seed),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: seed,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      dividerTheme: const DividerThemeData(space: 1, thickness: 0.5, color: Color(0xFFE8EAED)),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        titleTextStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: onSurface),
        subtitleTextStyle: TextStyle(fontSize: 13, color: onSurfaceVariant),
        iconColor: onSurfaceVariant,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceVariant,
        labelStyle: const TextStyle(fontSize: 13, color: onSurface),
        side: const BorderSide(color: outline, width: 0.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF323232),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        contentTextStyle: const TextStyle(fontSize: 14, color: Color(0xFFFFFFFF)),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titleTextStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: onSurface),
      ),
    );
  }

  // ─── 辅助方法 ───────────────────────────────────────────

  /// 分数颜色（与原始 CSS 阈值一致）。
  static Color scoreColor(double? score) {
    if (score == null) return Colors.grey;
    if (score >= 9.0) return successGreen;
    if (score >= 7.0) return zjuBlue;
    if (score >= 5.0) return warningOrange;
    return dangerRed;
  }

  /// GPA 颜色。
  /// 高对比度变体 — WCAG AAA，黑白+蓝强调色。
  static ThemeData get highContrastTheme {
    const fg = Color(0xFF000000);
    const bg = Color(0xFFFFFFFF);
    const accent = Color(0xFF0044CC);
    const border = Color(0xFF000000);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: const ColorScheme.light(
        primary: accent,
        onPrimary: Color(0xFFFFFFFF),
        surface: bg,
        onSurface: fg,
        outline: border,
        primaryContainer: Color(0xFFCCDDFF),
        onPrimaryContainer: fg,
        surfaceContainerLow: Color(0xFFF0F0F0),
        surfaceContainerHighest: Color(0xFFDDDDDD),
      ),
      scaffoldBackgroundColor: bg,
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        foregroundColor: fg,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      cardTheme: CardThemeData(
        color: bg,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: border, width: 1.5),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: border, width: 2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: border, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: accent, width: 2.5),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: Color(0xFF000000),
        contentTextStyle: TextStyle(color: Color(0xFFFFFFFF), fontSize: 16),
      ),
    );
  }

  static Color gpaColor(double gpa) {
    if (gpa >= 4.5) return successGreen;
    if (gpa >= 3.5) return zjuBlue;
    if (gpa >= 2.5) return warningOrange;
    return dangerRed;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 主题变体存储扩展
// ═══════════════════════════════════════════════════════════════════════════

/// [ThemeVariant] ↔ `SharedPreferences` 存储键的序列化扩展。
///
/// 定义在 `theme.dart` 中以便 `app.dart` 和 `settings_screen.dart` 共用。
extension ThemeVariantStorage on ThemeVariant {
  /// 序列化为存储键（如 `"evergreen"`）。
  String toStorageKey() => name;

  /// 从存储键反序列化，无效键回退到 `system`。
  static ThemeVariant fromStorageKey(String key) {
    return ThemeVariant.values.firstWhere(
      (v) => v.name == key,
      orElse: () => ThemeVariant.system,
    );
  }
}
