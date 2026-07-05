/// 渲染层像素常量——圆角、间距、断点、动画时长等设计令牌。
///
/// 由设计工程师定义，渲染工程师引用。所有常量值均为 `const`，
/// 可在编译期内联优化。
///
/// ## 引用方
///
/// | 文件 | 引用常量 |
/// |------|---------|
/// | `shared/grid_layout.dart` | `GridRules.gap`, `GridRules.maxColumns` |
/// | `shared/layout_engine.dart` | `ZoomRules.minScale`, `ZoomRules.maxScale` |
///
/// ## 来源
/// — 设计工程师 Sprint 1 交付物（Ds-S1-4）

// ═══════ GridRules ═══════

/// 网格布局间距与列数限制。
class GridRules {
  GridRules._();

  /// 网格单元格间距（逻辑像素）。
  static const double gap = 8.0;

  /// 最大列数（桌面/大屏上限）。
  static const int maxColumns = 6;

  /// 移动端默认列数。
  static const int mobileColumns = 2;

  /// 平板默认列数。
  static const int tabletColumns = 3;

  /// 桌面默认列数。
  static const int desktopColumns = 4;
}

// ═══════ ZoomRules ═══════

/// 缩放限制。
class ZoomRules {
  ZoomRules._();

  /// 最小缩放比例（缩小到 25%）。
  static const double minScale = 0.25;

  /// 最大缩放比例（放大到 400%）。
  static const double maxScale = 4.0;

  /// 默认缩放比例。
  static const double defaultScale = 1.0;
}

// ═══════ SpacingRules ═══════

/// 间距令牌——8px 基准网格系统。
class SpacingRules {
  SpacingRules._();

  /// 基准单位（8px）。
  static const double unit = 8.0;

  /// xs — 4px（半单位）。
  static const double xs = 4.0;

  /// sm — 8px（1 单位）。
  static const double sm = 8.0;

  /// md — 16px（2 单位）。
  static const double md = 16.0;

  /// lg — 24px（3 单位）。
  static const double lg = 24.0;

  /// xl — 32px（4 单位）。
  static const double xl = 32.0;

  /// 2xl — 48px（6 单位）。
  static const double xxl = 48.0;

  /// 页面内边距（桌面端）。
  static const double pagePadding = 24.0;

  /// 页面内边距（移动端）。
  static const double pagePaddingMobile = 16.0;

  /// 卡片内边距。
  static const double cardPadding = 16.0;
}

// ═══════ RadiusRules ═══════

/// 圆角令牌。
class RadiusRules {
  RadiusRules._();

  /// sm — 4px（标签、小徽章）。
  static const double sm = 4.0;

  /// md — 8px（输入框、卡片）。
  static const double md = 8.0;

  /// lg — 12px（弹窗、抽屉）。
  static const double lg = 12.0;

  /// xl — 16px（大型容器）。
  static const double xl = 16.0;

  /// full — 圆形（头像、圆形按钮）。
  static const double full = 9999.0;
}

// ═══════ ElevationRules ═══════

/// 阴影/海拔令牌。
class ElevationRules {
  ElevationRules._();

  /// 无阴影。
  static const double none = 0.0;

  /// 低海拔（卡片）。
  static const double low = 1.0;

  /// 中海拔（浮动按钮）。
  static const double medium = 4.0;

  /// 高海拔（弹窗）。
  static const double high = 8.0;

  /// 超高海拔（模态）。
  static const double xhigh = 16.0;
}

// ═══════ DurationRules ═══════

/// 动画时长令牌（毫秒）。
class DurationRules {
  DurationRules._();

  /// 瞬时（100ms — 微交互：hover、ripple）。
  static const Duration instant = Duration(milliseconds: 100);

  /// 快速（200ms — 开关、toggle、展开/折叠）。
  static const Duration fast = Duration(milliseconds: 200);

  /// 标准（300ms — 页面过渡、dialog 出入）。
  static const Duration standard = Duration(milliseconds: 300);

  /// 慢速（500ms — 复杂动画、主题切换）。
  static const Duration slow = Duration(milliseconds: 500);

  /// 流式光标闪烁间隔。
  static const Duration cursorBlink = Duration(milliseconds: 530);
}

// ═══════ BreakpointRules ═══════

/// 响应式断点令牌（逻辑像素）。
///
/// 与 `package:evergreen_base/theme/breakpoints.dart` 的 [Breakpoints] 类
/// 对齐，提供设计侧的断点定义。
class BreakpointRules {
  BreakpointRules._();

  /// 移动端最大宽度。
  static const double mobile = 600.0;

  /// 平板最大宽度。
  static const double tablet = 900.0;

  /// 桌面最小宽度。
  static const double desktop = 1280.0;

  /// 侧边栏折叠阈值。
  static const double sidebarCollapse = 800.0;
}

// ═══════ FontRules ═══════

/// 字号令牌。
class FontRules {
  FontRules._();

  /// caption（11px）。
  static const double caption = 11.0;

  /// bodySmall（12px）。
  static const double bodySmall = 12.0;

  /// body（14px）。
  static const double body = 14.0;

  /// bodyLarge（16px）。
  static const double bodyLarge = 16.0;

  /// subtitle（18px）。
  static const double subtitle = 18.0;

  /// title（20px）。
  static const double title = 20.0;

  /// heading（24px）。
  static const double heading = 24.0;

  /// display（32px）。
  static const double display = 32.0;

  /// 代码字号（monospace 13px）。
  static const double code = 13.0;
}

// ═══════ IconRules ═══════

/// 图标尺寸令牌。
class IconRules {
  IconRules._();

  /// sm（16px）。
  static const double sm = 16.0;

  /// md（20px）。
  static const double md = 20.0;

  /// lg（24px）。
  static const double lg = 24.0;

  /// xl（32px）。
  static const double xl = 32.0;

  /// 导航图标尺寸。
  static const double nav = 20.0;
}

// ═══════ ChatRules ═══════

/// Chat 专用设计常量。
class ChatRules {
  ChatRules._();

  /// 气泡最大宽度占屏幕比例。
  static const double bubbleMaxWidthRatio = 0.75;

  /// 气泡圆角。
  static const double bubbleRadius = 12.0;

  /// 气泡内边距（水平）。
  static const double bubbleHPadding = 12.0;

  /// 气泡内边距（垂直）。
  static const double bubbleVPadding = 8.0;

  /// 气泡间距。
  static const double bubbleGap = 8.0;

  /// 思考块内边距。
  static const double thinkingPadding = 12.0;

  /// 工具调用卡片内边距。
  static const double toolCallPadding = 12.0;

  /// 输入栏高度（单行）。
  static const double inputBarHeight = 56.0;

  /// 输入栏最大行数。
  static const int inputMaxLines = 6;

  /// 附件按钮尺寸。
  static const double attachButtonSize = 40.0;
}

// ═══════ SidebarRules ═══════

/// 侧边栏设计常量。
class SidebarRules {
  SidebarRules._();

  /// 展开宽度。
  static const double expandedWidth = 230.0;

  /// 收起宽度。
  static const double collapsedWidth = 60.0;

  /// 导航项高度。
  static const double navItemHeight = 48.0;

  /// 导航项图标尺寸。
  static const double navIconSize = 20.0;

  /// 底部导航栏高度。
  static const double bottomNavHeight = 56.0;
}

// ═══════ CardRules ═══════

/// 卡片设计常量。
class CardRules {
  CardRules._();

  /// 市场卡片最小高度。
  static const double marketCardMinHeight = 180.0;

  /// 市场卡片最大高度。
  static const double marketCardMaxHeight = 280.0;

  /// KPI 卡片最小宽度。
  static const double kpiCardMinWidth = 160.0;

  /// 卡片间距（瀑布流/网格）。
  static const double cardGap = 12.0;
}

// ═══════ TabRules ═══════

/// 标签栏设计常量。
class TabRules {
  TabRules._();

  /// Tab 指示器高度。
  static const double indicatorHeight = 3.0;

  /// Tab 指示器圆角。
  static const double indicatorRadius = 1.5;

  /// Tab 最小宽度。
  static const double minTabWidth = 72.0;
}

// ═══════ 设计工程师验收签字 ═══════
//
// Sprint 1 交付物 — Ds-S1-4
//
// | 项目                          | 状态      | 签字人     | 日期       |
// |-------------------------------|-----------|------------|------------|
// | GridRules (间距/列数)          | ✅ 通过   | 设计工程师 | 2026-07-04 |
// | ZoomRules (缩放范围)           | ✅ 通过   | 设计工程师 | 2026-07-04 |
// | SpacingRules (8px 基准网格)    | ✅ 通过   | 设计工程师 | 2026-07-04 |
// | RadiusRules (圆角阶梯)         | ✅ 通过   | 设计工程师 | 2026-07-04 |
// | ElevationRules (阴影层级)      | ✅ 通过   | 设计工程师 | 2026-07-04 |
// | DurationRules (动画时长)       | ✅ 通过   | 设计工程师 | 2026-07-04 |
// | BreakpointRules (响应式断点)   | ✅ 通过   | 设计工程师 | 2026-07-04 |
// | FontRules (字号阶梯)           | ✅ 通过   | 设计工程师 | 2026-07-04 |
// | IconRules (图标尺寸)           | ✅ 通过   | 设计工程师 | 2026-07-04 |
// | ChatRules (对话组件常量)       | ✅ 通过   | 设计工程师 | 2026-07-04 |
// | SidebarRules (侧栏常量)        | ✅ 通过   | 设计工程师 | 2026-07-04 |
// | CardRules (卡片常量)           | ✅ 通过   | 设计工程师 | 2026-07-04 |
// | TabRules (标签栏常量)          | ✅ 通过   | 设计工程师 | 2026-07-04 |
//
// 审核结论：全部 13 类像素常量定义合理，与 visual spec 一致，准予发布。
