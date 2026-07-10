/// RenderTokens — 跨引擎视觉常量（Dart Widget + HTML/CSS 共享）。
///
/// 所有颜色、间距、尺寸、字体等视觉参数集中定义于此。
/// 两套渲染引擎（Flutter Widget / HTML+CSS）均引用此常量，
/// 保证视觉一致性，避免硬编码分散在 4 个文件中。
///
/// # 主题适配
///
/// 调用 [RenderTokens.applyTheme] 可从 [ThemeDescriptor] 动态更新颜色，
/// [RenderTokens.colors] 返回当前活跃的颜色集。未调用时使用内置 dark 默认值。
///
/// # 颜色命名规则
/// - `bg*` = 背景色
/// - `border*` = 边框色
/// - `text*` = 文字色
/// - `accent*` = 强调色/品牌色（从主题 `primary` 派生）
/// - `state*` = 状态色（成功/错误/警告）
///
/// # 使用方式
/// ```dart
/// // Dart 端
/// Container(color: RenderTokens.colors.bgPrimary)
///
/// // HTML 端
/// final cssColor = RenderTokens.colors.bgPrimaryHex; // "#0d1117"
/// ```
library;

import 'dart:ui';
import 'package:evergreen_base/core/theme/theme_descriptor.dart';

// ============================================================
// 颜色
// ============================================================

/// 渲染层共享颜色令牌。
///
/// 默认值为 GitHub-dark 色板。调用 [RenderTokensColors.fromTheme]
/// 可从主题描述符构建自定义色集。
class RenderTokensColors {
  // ── 背景色 ──

  /// 主背景色（页面底色）
  final Color bgPrimary;
  final String bgPrimaryHex;

  /// 次级背景色（卡片/Slot/sidebar）
  final Color bgSecondary;
  final String bgSecondaryHex;

  /// 三级背景色（hover/表头/代码区）
  final Color bgTertiary;
  final String bgTertiaryHex;

  // ── 边框色 ──

  /// 默认边框色
  final Color borderDefault;
  final String borderDefaultHex;

  /// 强调边框色（从 primary 派生）
  final Color borderAccent;
  final String borderAccentHex;

  /// 成功边框色（绿）
  final Color borderSuccess;
  final String borderSuccessHex;

  // ── 文字色 ──

  /// 主文字色
  final Color textPrimary;
  final String textPrimaryHex;

  /// 次级文字色
  final Color textSecondary;
  final String textSecondaryHex;

  /// 三级文字色（行号/禁用）
  final Color textTertiary;
  final String textTertiaryHex;

  // ── 强调色/品牌色 ──

  /// 品牌色（文字强调）= 主题 `primary`
  final Color accentBlue;
  final String accentBlueHex;

  /// 品牌色背景（半透明）
  final Color accentBlueBg;
  final String accentBlueBgHex;

  /// 品牌色边框（半透明）
  final Color accentBlueBorder;
  final String accentBlueBorderHex;

  // ── 状态色 ──

  /// 成功绿
  final Color stateSuccess;
  final String stateSuccessHex;

  /// 成功绿背景（半透明）
  final Color stateSuccessBg;
  final String stateSuccessBgHex;

  /// 成功绿边框（半透明）
  final Color stateSuccessBorder;
  final String stateSuccessBorderHex;

  /// 错误红
  final Color stateError;
  final String stateErrorHex;

  /// 按钮绿
  final Color buttonGreen;
  final String buttonGreenHex;

  // ── 代码高亮 ──

  /// 关键字色
  final Color codeKeyword;
  final String codeKeywordHex;

  /// 函数名色
  final Color codeFunction;
  final String codeFunctionHex;

  /// 字符串色
  final Color codeString;
  final String codeStringHex;

  /// 数字色
  final Color codeNumber;
  final String codeNumberHex;

  /// 注释色
  final Color codeComment;
  final String codeCommentHex;

  // ── 图表色板 ──

  final List<Color> chartPalette;
  final List<String> chartPaletteHex;

  // ── 按钮色 ──

  /// 按钮默认背景
  final Color buttonBg;
  final String buttonBgHex;

  const RenderTokensColors._({
    required this.bgPrimary,
    required this.bgPrimaryHex,
    required this.bgSecondary,
    required this.bgSecondaryHex,
    required this.bgTertiary,
    required this.bgTertiaryHex,
    required this.borderDefault,
    required this.borderDefaultHex,
    required this.borderAccent,
    required this.borderAccentHex,
    required this.borderSuccess,
    required this.borderSuccessHex,
    required this.textPrimary,
    required this.textPrimaryHex,
    required this.textSecondary,
    required this.textSecondaryHex,
    required this.textTertiary,
    required this.textTertiaryHex,
    required this.accentBlue,
    required this.accentBlueHex,
    required this.accentBlueBg,
    required this.accentBlueBgHex,
    required this.accentBlueBorder,
    required this.accentBlueBorderHex,
    required this.stateSuccess,
    required this.stateSuccessHex,
    required this.stateSuccessBg,
    required this.stateSuccessBgHex,
    required this.stateSuccessBorder,
    required this.stateSuccessBorderHex,
    required this.stateError,
    required this.stateErrorHex,
    required this.buttonGreen,
    required this.buttonGreenHex,
    required this.codeKeyword,
    required this.codeKeywordHex,
    required this.codeFunction,
    required this.codeFunctionHex,
    required this.codeString,
    required this.codeStringHex,
    required this.codeNumber,
    required this.codeNumberHex,
    required this.codeComment,
    required this.codeCommentHex,
    required this.chartPalette,
    required this.chartPaletteHex,
    required this.buttonBg,
    required this.buttonBgHex,
  });

  /// 内置 dark 默认色板（GitHub-dark 风格）。
  static final defaultInstance = RenderTokensColors._(
    bgPrimary: const Color(0xFF0D1117),
    bgPrimaryHex: '#0d1117',
    bgSecondary: const Color(0xFF161B22),
    bgSecondaryHex: '#161b22',
    bgTertiary: const Color(0xFF1C2128),
    bgTertiaryHex: '#1c2128',
    borderDefault: const Color(0xFF30363D),
    borderDefaultHex: '#30363d',
    borderAccent: const Color(0xFF1F6FEB),
    borderAccentHex: '#1f6feb',
    borderSuccess: const Color(0xFF3FB950),
    borderSuccessHex: '#3fb950',
    textPrimary: const Color(0xFFC9D1D9),
    textPrimaryHex: '#c9d1d9',
    textSecondary: const Color(0xFF8B949E),
    textSecondaryHex: '#8b949e',
    textTertiary: const Color(0xFF484F58),
    textTertiaryHex: '#484f58',
    accentBlue: const Color(0xFF58A6FF),
    accentBlueHex: '#58a6ff',
    accentBlueBg: const Color(0x221F6FEB),
    accentBlueBgHex: '#1f6feb22',
    accentBlueBorder: const Color(0x441F6FEB),
    accentBlueBorderHex: '#1f6feb44',
    stateSuccess: const Color(0xFF3FB950),
    stateSuccessHex: '#3fb950',
    stateSuccessBg: const Color(0x223FB950),
    stateSuccessBgHex: '#3fb95022',
    stateSuccessBorder: const Color(0x443FB950),
    stateSuccessBorderHex: '#3fb95044',
    stateError: const Color(0xFFFF7B72),
    stateErrorHex: '#ff7b72',
    buttonGreen: const Color(0xFF238636),
    buttonGreenHex: '#238636',
    codeKeyword: const Color(0xFFFF7B72),
    codeKeywordHex: '#ff7b72',
    codeFunction: const Color(0xFFD2A8FF),
    codeFunctionHex: '#d2a8ff',
    codeString: const Color(0xFFA5D6FF),
    codeStringHex: '#a5d6ff',
    codeNumber: const Color(0xFF79C0FF),
    codeNumberHex: '#79c0ff',
    codeComment: const Color(0xFF8B949E),
    codeCommentHex: '#8b949e',
    chartPalette: const [
      Color(0xFFFF7B72), Color(0xFFD2A8FF), Color(0xFF79C0FF),
      Color(0xFF3FB950), Color(0xFFD29922), Color(0xFFF78166),
      Color(0xFFA5D6FF), Color(0xFFFFA198),
    ],
    chartPaletteHex: const [
      '#ff7b72', '#d2a8ff', '#79c0ff', '#3fb950',
      '#d29922', '#f78166', '#a5d6ff', '#ffa198',
    ],
    buttonBg: const Color(0xFF21262D),
    buttonBgHex: '#21262d',
  );

  /// 从 [ThemeDescriptor] 构建颜色集。
  ///
  /// 五层映射（未声明则回退 dark 默认）：
  /// - `app.sidebar.active` → accentBlue
  /// - `app.blank.bg` → bgPrimary
  /// - `components.card.bg` → bgSecondary
  /// - `components.codeBlock.bg` → bgTertiary
  /// - `slot.border.color` → borderDefault
  /// - `app.sidebar.text` → textPrimary
  /// - `components.button.primary` → stateSuccess / buttonGreen
  factory RenderTokensColors.fromTheme(ThemeDescriptor? theme) {
    if (theme == null) return defaultInstance;

    // ── 辅助：从指定层查 token ──
    String _l(LayerTokens layer, String comp, String tok, String fb) =>
        layer[comp]?[tok] ?? fb;

    // ── 从五层结构派生 ──
    final accentHex = _l(theme.app, 'sidebar', 'active', '#58a6ff');
    final accent = _parseHex(accentHex);

    final bgPrimaryHex = _l(theme.app, 'blank', 'bg', '#0D1117');
    final bgSecondaryHex = _l(theme.components, 'card', 'bg', '#161B22');
    final bgTertiaryHex = _l(theme.components, 'codeBlock', 'bg', '#1C2128');
    final borderDefaultHex = _l(theme.slot, 'border', 'color', '#30363D');
    final textPrimaryHex = _l(theme.app, 'sidebar', 'text', '#C9D1D9');
    final textSecondaryHex = _l(theme.components, 'chip', 'text', '#8B949E');
    final textTertiaryHex = _l(theme.components, 'tooltip', 'text', '#484F58');
    final successHex = _l(theme.components, 'button', 'primary', '#3FB950');
    final buttonGreenHex = _l(theme.components, 'button', 'primary', '#238636');
    final buttonBgHex = _l(theme.components, 'card', 'bg', '#21262D');

    return RenderTokensColors._(
      bgPrimary: _parseHex(bgPrimaryHex),
      bgPrimaryHex: bgPrimaryHex,
      bgSecondary: _parseHex(bgSecondaryHex),
      bgSecondaryHex: bgSecondaryHex,
      bgTertiary: _parseHex(bgTertiaryHex),
      bgTertiaryHex: bgTertiaryHex,
      borderDefault: _parseHex(borderDefaultHex),
      borderDefaultHex: borderDefaultHex,
      borderAccent: accent,
      borderAccentHex: accentHex,
      borderSuccess: _parseHex(successHex),
      borderSuccessHex: successHex,
      textPrimary: _parseHex(textPrimaryHex),
      textPrimaryHex: textPrimaryHex,
      textSecondary: _parseHex(textSecondaryHex),
      textSecondaryHex: textSecondaryHex,
      textTertiary: _parseHex(textTertiaryHex),
      textTertiaryHex: textTertiaryHex,
      // ── primary 派生：文本强调、半透明背景、半透明边框 ──
      accentBlue: accent,
      accentBlueHex: accentHex,
      accentBlueBg: accent.withValues(alpha: 0.13),
      accentBlueBgHex: _hexWithAlpha(accentHex, 0.13),
      accentBlueBorder: accent.withValues(alpha: 0.27),
      accentBlueBorderHex: _hexWithAlpha(accentHex, 0.27),
      // ── 状态色 ──
      stateSuccess: _parseHex(successHex),
      stateSuccessHex: successHex,
      stateSuccessBg: _parseHex(successHex).withValues(alpha: 0.13),
      stateSuccessBgHex: _hexWithAlpha(successHex, 0.13),
      stateSuccessBorder: _parseHex(successHex).withValues(alpha: 0.27),
      stateSuccessBorderHex: _hexWithAlpha(successHex, 0.27),
      stateError: const Color(0xFFFF7B72),
      stateErrorHex: '#ff7b72',
      buttonGreen: _parseHex(buttonGreenHex),
      buttonGreenHex: buttonGreenHex,
      // ── 代码高亮（保持独立，不跟随主题）──
      codeKeyword: const Color(0xFFFF7B72),
      codeKeywordHex: '#ff7b72',
      codeFunction: const Color(0xFFD2A8FF),
      codeFunctionHex: '#d2a8ff',
      codeString: const Color(0xFFA5D6FF),
      codeStringHex: '#a5d6ff',
      codeNumber: const Color(0xFF79C0FF),
      codeNumberHex: '#79c0ff',
      codeComment: const Color(0xFF8B949E),
      codeCommentHex: '#8b949e',
      // ── 图表色板（保持独立）──
      chartPalette: defaultInstance.chartPalette,
      chartPaletteHex: defaultInstance.chartPaletteHex,
      // ── 按钮背景 ──
      buttonBg: _parseHex(buttonBgHex),
      buttonBgHex: buttonBgHex,
    );
  }
}

// ============================================================
// 间距
// ============================================================

/// 渲染层共享间距令牌（单位：逻辑像素）。
class RenderTokensSpacing {
  const RenderTokensSpacing._();

  /// 紧凑间距（tab 内边距、标签 padding）
  static const double xs = 4.0;

  /// 小间距（元素内边距）
  static const double sm = 6.0;

  /// 标准间距（slot 间 gap、标准 padding）
  static const double md = 8.0;

  /// 中等间距（卡片内 padding）
  static const double lg = 12.0;

  /// 大间距（页面 padding、section 间）
  static const double xl = 16.0;

  /// 超大间距（空状态居中 padding）
  static const double xxl = 24.0;

  /// 巨大间距（占位符 padding）
  static const double xxxl = 40.0;
}

// ============================================================
// 圆角
// ============================================================

/// 渲染层共享圆角令牌。
class RenderTokensRadius {
  const RenderTokensRadius._();

  /// 小圆角（tag、徽章）
  static const double sm = 3.0;

  /// 标准圆角（按钮、输入框）
  static const double md = 4.0;

  /// 中等圆角（tab 顶部、card 小号）
  static const double lg = 6.0;

  /// 大圆角（card、slot、dialog）
  static const double xl = 8.0;

  /// 超大圆角（消息气泡、特殊卡片）
  static const double xxl = 12.0;

  /// 圆形（avatar、按钮、tag）
  static const double round = 20.0;

  /// 全圆（pill button）
  static const double pill = 999.0;
}

// ============================================================
// 组件尺寸
// ============================================================

/// 渲染层共享组件尺寸令牌。
class RenderTokensSize {
  const RenderTokensSize._();

  /// Slot 卡片默认高度
  static const double slotCardHeight = 400.0;

  /// 侧边栏宽度
  static const double sidebarWidth = 200.0;

  /// Slot header 高度
  static const double slotHeaderHeight = 28.0;

  /// Tab 栏高度
  static const double tabBarHeight = 32.0;

  /// 操作栏高度
  static const double actionBarHeight = 44.0;

  /// Avatar 尺寸
  static const double avatarSize = 28.0;

  /// 图表画布默认尺寸
  static const double chartCanvasSize = 200.0;

  /// 饼图默认尺寸
  static const double pieChartSize = 120.0;

  /// 转盘默认尺寸
  static const double lotteryWheelSize = 240.0;

  /// 消息气泡最大宽度比例
  static const double bubbleMaxWidthRatio = 0.8;

  /// 代码行号列最小宽度
  static const double codeLineNumberWidth = 36.0;

  /// 卡片网格最小列宽
  static const double cardGridMinColWidth = 180.0;

  /// 闪卡最大宽度
  static const double flashCardMaxWidth = 300.0;

  /// 闪卡高度
  static const double flashCardHeight = 160.0;

  /// 工具栏高度
  static const double toolbarHeight = 32.0;
}

// ============================================================
// 字体
// ============================================================

/// 渲染层共享字体令牌。
class RenderTokensFont {
  const RenderTokensFont._();

  /// 字体族
  static const String fontFamily = "'Segoe UI', system-ui, -apple-system, sans-serif";
  static const String fontFamilyMono = "'Cascadia Code', 'Fira Code', monospace";

  /// 字号
  static const double sizeXs = 9.0;
  static const double sizeSm = 10.0;
  static const double sizeBase = 11.0;
  static const double sizeMd = 12.0;
  static const double sizeLg = 13.0;
  static const double sizeXl = 14.0;
  static const double sizeXxl = 18.0;
  static const double sizeTitle = 20.0;

  /// 行高
  static const double lineHeightCompact = 1.4;
  static const double lineHeightNormal = 1.6;
  static const double lineHeightRelaxed = 1.8;
}

// ============================================================
// CSS 生成工具
// ============================================================

/// 为 HTML/CSS 引擎生成 CSS 变量和基础样式。
class RenderTokensCss {
  const RenderTokensCss._();

  /// 生成 CSS 变量声明块。
  ///
  /// 嵌入到 `<style>` 标签中，使 HTML 组件可通过 `var(--evg-*)` 引用令牌。
  /// [colors] 未传时使用当前活跃的 [RenderTokens.colors]。
  static String cssVariables({RenderTokensColors? colors}) {
    final c = colors ?? RenderTokens.colors;
    return '''
:root {
  /* 背景 */
  --evg-bg-primary: ${c.bgPrimaryHex};
  --evg-bg-secondary: ${c.bgSecondaryHex};
  --evg-bg-tertiary: ${c.bgTertiaryHex};

  /* 边框 */
  --evg-border-default: ${c.borderDefaultHex};
  --evg-border-accent: ${c.borderAccentHex};
  --evg-border-success: ${c.borderSuccessHex};

  /* 文字 */
  --evg-text-primary: ${c.textPrimaryHex};
  --evg-text-secondary: ${c.textSecondaryHex};
  --evg-text-tertiary: ${c.textTertiaryHex};

  /* 强调色 */
  --evg-accent-blue: ${c.accentBlueHex};
  --evg-accent-blue-bg: ${c.accentBlueBgHex};
  --evg-accent-blue-border: ${c.accentBlueBorderHex};

  /* 状态色 */
  --evg-state-success: ${c.stateSuccessHex};
  --evg-state-success-bg: ${c.stateSuccessBgHex};
  --evg-state-success-border: ${c.stateSuccessBorderHex};
  --evg-state-error: ${c.stateErrorHex};

  /* 按钮 */
  --evg-button-green: ${c.buttonGreenHex};
  --evg-button-bg: ${c.buttonBgHex};

  /* 代码 */
  --evg-code-kw: ${c.codeKeywordHex};
  --evg-code-fn: ${c.codeFunctionHex};
  --evg-code-str: ${c.codeStringHex};
  --evg-code-num: ${c.codeNumberHex};
  --evg-code-cmt: ${c.codeCommentHex};

  /* 间距 */
  --evg-space-xs: ${RenderTokensSpacing.xs}px;
  --evg-space-sm: ${RenderTokensSpacing.sm}px;
  --evg-space-md: ${RenderTokensSpacing.md}px;
  --evg-space-lg: ${RenderTokensSpacing.lg}px;
  --evg-space-xl: ${RenderTokensSpacing.xl}px;
  --evg-space-xxl: ${RenderTokensSpacing.xxl}px;

  /* 圆角 */
  --evg-radius-sm: ${RenderTokensRadius.sm}px;
  --evg-radius-md: ${RenderTokensRadius.md}px;
  --evg-radius-lg: ${RenderTokensRadius.lg}px;
  --evg-radius-xl: ${RenderTokensRadius.xl}px;
  --evg-radius-xxl: ${RenderTokensRadius.xxl}px;
  --evg-radius-round: ${RenderTokensRadius.round}px;

  /* 字体 */
  --evg-font-family: ${RenderTokensFont.fontFamily};
  --evg-font-mono: ${RenderTokensFont.fontFamilyMono};
  --evg-font-size-xs: ${RenderTokensFont.sizeXs}px;
  --evg-font-size-sm: ${RenderTokensFont.sizeSm}px;
  --evg-font-size-base: ${RenderTokensFont.sizeBase}px;
  --evg-font-size-md: ${RenderTokensFont.sizeMd}px;
  --evg-font-size-lg: ${RenderTokensFont.sizeLg}px;
  --evg-font-size-xl: ${RenderTokensFont.sizeXl}px;
}
''';
  }
}

// ============================================================
// 统一入口
// ============================================================

/// hex → [Color]。支持 `#RGB` / `#RRGGBB` / `#AARRGGBB`。
Color _parseHex(String hex) {
  final sanitized = hex.replaceFirst('#', '');
  final intVal = int.parse(
    sanitized.length == 6 ? 'FF$sanitized' : sanitized,
    radix: 16,
  );
  return Color(intVal);
}

/// 将 hex 颜色附加 alpha 通道（0.0–1.0），返回 hex 字符串。
String _hexWithAlpha(String hex, double alpha) {
  final sanitized = hex.replaceFirst('#', '');
  final rgb = sanitized.length == 6 ? sanitized : sanitized.substring(2);
  final a = (alpha * 255).round().toRadixString(16).padLeft(2, '0');
  return '#$a$rgb';
}

/// 渲染层共享令牌——单点访问所有视觉常量。
///
/// 调用 [applyTheme] 从主题描述符更新颜色后，[colors] 返回新色集。
/// 间距、圆角、尺寸、字体不受主题影响。
///
/// 用法：
/// ```dart
/// final bg = RenderTokens.colors.bgPrimary;          // Dart Color
/// final cssBg = RenderTokens.colors.bgPrimaryHex;    // CSS string
/// final gap = RenderTokens.spacing.md;               // 8.0
/// ```
abstract class RenderTokens {
  RenderTokens._();

  static RenderTokensColors _colors = RenderTokensColors.defaultInstance;

  /// 应用主题——从 [ThemeDescriptor] 派生颜色令牌。
  /// 传 null 恢复内置 dark 默认。
  static void applyTheme(ThemeDescriptor? theme) {
    _colors = RenderTokensColors.fromTheme(theme);
  }

  /// 当前活跃的颜色令牌。
  static RenderTokensColors get colors => _colors;

  /// 间距令牌
  static const spacing = RenderTokensSpacing._();

  /// 圆角令牌
  static const radius = RenderTokensRadius._();

  /// 组件尺寸令牌
  static const size = RenderTokensSize._();

  /// 字体令牌
  static const font = RenderTokensFont._();

  /// CSS 生成工具
  static const css = RenderTokensCss._();
}
