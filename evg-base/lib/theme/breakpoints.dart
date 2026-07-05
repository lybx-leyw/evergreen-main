/// 响应式断点——兼容性 stub，委托到 renderer 已有常量。
///
/// 渲染层通过 `package:evergreen_base/theme/breakpoints.dart` 引用，
/// 实际常量与 `renderer/shared/renderer_providers.dart` 中的
/// `kMobileBreakpoint` / `kMediumBreakpoint` 保持对齐。
///
/// 公开类：[Breakpoints]
library;

/// 响应式断点常量。
class Breakpoints {
  const Breakpoints._();

  /// 移动端断点（≤600px 切换为移动端布局）。
  static const double mobile = 600;

  /// 平板断点（≤900px）。
  static const double tablet = 900;

  /// 桌面断点（≥1280px）。
  static const double desktop = 1280;
}
