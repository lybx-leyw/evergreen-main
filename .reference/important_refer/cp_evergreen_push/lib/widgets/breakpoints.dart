/// 响应式布局断点（Material 3 + 小桌面适配）。
///
/// 参考 Window Size Class，增加 768 过渡断点以兼容现有 sidebar。
///
/// 用法：
/// ```dart
/// if (constraints.maxWidth <= Breakpoints.mobile) {
///   return mobileLayout;
/// }
/// ```
class Breakpoints {
  Breakpoints._();

  /// 移动端 → 桌面端过渡（sidebar 切换点）。
  static const double mobile = 768;

  /// 紧凑布局（小桌面 / 平板横屏）。
  static const double compact = 1024;

  /// 标准桌面布局。
  static const double medium = 1280;

  /// 展开布局（大屏 / 全屏）。
  static const double expanded = 1600;
}
