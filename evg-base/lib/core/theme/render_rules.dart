/// 像素级设计常量——供渲染层引用的间距/圆角/字号/阴影/动效规范。
///
/// # 类一览
///
/// | 类 | 常量 | 说明 |
/// |-----|------|------|
/// | `Spacing` | `xs=4, sm=8, md=16, lg=24, xl=32, xxl=48` | 4px 基准间距体系 |
/// | `Radii` | `sm=4, md=8, lg=12, xl=16, full=9999` | 圆角体系 |
/// | `FontSize` | `caption=12, body=14, subtitle=16, title=20, heading=24, display=32` | 字号体系 |
/// | `Shadows` | `none, card, elevated, modal, drawer, fab` | CSS box-shadow 预设 |
/// | `Durations` | `fast=150ms, normal=300ms, slow=500ms, verySlow=800ms` | 动画时长 |
/// | `ComponentSize` | `sidebarWidth, headerHeight, buttonHeight, inputHeight, avatarMd, bubbleMaxWidth, ...` | 组件尺寸规范 |
library;

// ═══════ Spacing ═══════

/// 间距体系（4px 基准）。
class Spacing {
  Spacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

// ═══════ Radius ═══════

/// 圆角体系。
class Radii {
  Radii._();

  static const double sm = 4;
  static const double md = 8;
  static const double lg = 12;
  static const double xl = 16;
  static const double full = 9999;
}

// ═══════ FontSize ═══════

/// 字号体系。
class FontSize {
  FontSize._();

  static const double caption = 12;
  static const double body = 14;
  static const double subtitle = 16;
  static const double title = 20;
  static const double heading = 24;
  static const double display = 32;
}

// ═══════ Shadows ═══════

/// 阴影预设（elevation → 样式描述）。
class Shadows {
  Shadows._();

  /// 无阴影。
  static const String none = 'none';

  /// 卡片阴影（elevation 2）。
  static const String card = '0 1px 3px rgba(0,0,0,0.12), 0 1px 2px rgba(0,0,0,0.08)';

  /// 浮层阴影（elevation 4）。
  static const String elevated = '0 4px 6px rgba(0,0,0,0.12), 0 2px 4px rgba(0,0,0,0.08)';

  /// 模态阴影（elevation 8）。
  static const String modal = '0 10px 20px rgba(0,0,0,0.15), 0 4px 8px rgba(0,0,0,0.10)';

  /// 抽屉阴影。
  static const String drawer = '2px 0 8px rgba(0,0,0,0.15)';

  /// FAB 阴影。
  static const String fab = '0 6px 16px rgba(0,0,0,0.2), 0 2px 6px rgba(0,0,0,0.12)';
}

// ═══════ Durations ═══════

/// 动画时长（毫秒）。
class Durations {
  Durations._();

  /// 快速（hover、ripple）。
  static const int fast = 150;

  /// 常规（过渡、淡入淡出）。
  static const int normal = 300;

  /// 慢速（页面切换、模态进出）。
  static const int slow = 500;

  /// 极慢（启动动画）。
  static const int verySlow = 800;
}

// ═══════ ComponentSize ═══════

/// 组件尺寸规范。
class ComponentSize {
  ComponentSize._();

  // ── 布局 ──
  static const double sidebarWidth = 260;
  static const double headerHeight = 56;
  static const double footerHeight = 48;
  static const double drawerWidth = 320;

  // ── 按钮 ──
  static const double buttonMinWidth = 64;
  static const double buttonHeight = 40;
  static const double buttonHeightSm = 32;
  static const double buttonHeightLg = 48;
  static const double iconButtonSize = 40;

  // ── 输入 ──
  static const double inputHeight = 40;
  static const double inputHeightMultiline = 80;

  // ── 头像 ──
  static const double avatarSm = 24;
  static const double avatarMd = 40;
  static const double avatarLg = 56;

  // ── 聊天 ──
  static const double bubbleMaxWidth = 600;
  static const double bubbleRadius = 16;

  // ── 表格 ──
  static const double tableRowHeight = 48;
  static const double tableHeaderHeight = 40;
}
