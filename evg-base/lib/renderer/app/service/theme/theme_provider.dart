/// 主题解析——扁平语义色板 → Material [ThemeData]。
///
/// 公开函数：[buildAppThemeFromDescriptor]
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/theme/theme_descriptor.dart';
import 'render_tokens.dart';

// ═══════ 扁平色板 → ThemeData 构建 ═══════

/// 从 [ThemeDescriptor] 构建 App 壳层 [ThemeData]。
///
/// 此主题用于 MaterialApp.router 的 `theme`/`darkTheme` 参数。
/// 8 语义字段映射到 ColorScheme：
/// - `accent` → primary
/// - `background` → scaffoldBackgroundColor
/// - `surface` → surface
/// - `border` → outline
/// - `text` → onSurface
/// - `textSecondary` → onSurfaceVariant
/// - `error` → error
/// - `others` → secondary
ThemeData buildAppThemeFromDescriptor(
  ThemeDescriptor descriptor, {
  Brightness brightness = Brightness.light,
}) {
  final c = RenderTokensColors.fromTheme(descriptor);
  final isDark = brightness == Brightness.dark;

  final colorScheme = ColorScheme(
    brightness: brightness,
    primary: c.accentBlue,
    onPrimary: isDark ? const Color(0xFF0D1117) : const Color(0xFFFFFFFF),
    primaryContainer: c.accentBlue.withValues(alpha: 0.18),
    onPrimaryContainer: c.accentBlue,
    secondary: c.others,
    onSecondary: isDark ? const Color(0xFF0D1117) : const Color(0xFFFFFFFF),
    error: c.stateError,
    onError: isDark ? const Color(0xFF0D1117) : const Color(0xFFFFFFFF),
    // errorContainer / onErrorContainer：必须显式声明（否则 Flutter 自动从 error
    // 派生 → 深色主题下 errorContainer ≈ error 深红，文字同色看不清）。
    // 配对原则：背景用 error 的低 alpha 容器色，文字用主背景色（与 onError 相反）
    // 保证错误提示在任何主题下都有足够对比度。
    errorContainer: c.stateError.withValues(alpha: isDark ? 0.22 : 0.14),
    onErrorContainer: isDark ? c.bgPrimary : c.stateError,
    surface: c.bgSecondary,
    onSurface: c.textPrimary,
    onSurfaceVariant: c.textSecondary,
    outline: c.borderDefault,
    outlineVariant: c.borderDefault,
    surfaceContainerHighest: c.bgSecondary,
    surfaceContainer: c.bgTertiary,
    surfaceContainerLow: c.bgPrimary,
    shadow: Colors.black,
  );

  return ThemeData(
    colorScheme: colorScheme,
    useMaterial3: true,
    scaffoldBackgroundColor: c.bgPrimary,
  );
}
