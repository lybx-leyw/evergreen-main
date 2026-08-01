/// 样式预设 — CSS 式的声明样式系统。
///
/// 从 Widget 代码中分离间距、圆角、阴影、字号等空间属性，
/// 让同一套组件树可通过切换预设实现"紧凑 / 标准 / 宽松"模式。
///
/// # 与 ThemeDescriptor 的关系
///
/// | 层 | 负责 | 示例 |
/// |----|------|------|
/// | **ThemeDescriptor** (已有) | 颜色 + 字体族 | primaryColor, fontFamily |
/// | **StylePreset** (新增) | 空间 + 比例 | padding, gap, radius, scale |
///
/// 两者互补，不冲突。暗色/亮色切换走 ThemeDescriptor；紧凑/宽松切换走 StylePreset。
///
/// # 用法
/// ```dart
/// // 获取当前预设的空间属性
/// final style = StylePreset.of(context);
/// Padding(padding: EdgeInsets.all(style.slotPadding));
/// ```
library;

import 'package:flutter/widgets.dart';

/// 样式预设 — 声明式空间属性集合。
class StylePreset {
  // ── 页面级 ──
  final double pagePadding;

  // ── slot 级 ──
  final double slotPadding;      // slot 内容区内边距
  final double slotGap;          // slot 之间间距
  final double cardGap;          // Card 内部子元素间距

  // ── 标题栏 ──
  final double titlePaddingH;    // 标题栏水平内边距
  final double titlePaddingV;    // 标题栏垂直内边距

  // ── 圆角 ──
  final double cardRadius;       // Card 圆角
  final double chipRadius;       // Chip/Tag 圆角

  // ── 阴影 ──
  final double cardElevation;    // Card 阴影高度

  // ── 字号缩放 ──
  final double titleScale;       // 标题字号倍率
  final double bodyScale;        // 正文字号倍率
  final double captionScale;     // 辅助文字倍率

  const StylePreset({
    this.pagePadding = 16,
    this.slotPadding = 12,
    this.slotGap = 16,
    this.cardGap = 8,
    this.titlePaddingH = 10,
    this.titlePaddingV = 6,
    this.cardRadius = 10,
    this.chipRadius = 4,
    this.cardElevation = 1,
    this.titleScale = 1.0,
    this.bodyScale = 1.0,
    this.captionScale = 1.0,
  });

  /// 紧凑预设。
  static const compact = StylePreset(
    pagePadding: 8, slotPadding: 8, slotGap: 8, cardGap: 4,
    titlePaddingH: 8, titlePaddingV: 4, cardRadius: 6, chipRadius: 3,
    titleScale: 0.9, bodyScale: 0.9, captionScale: 0.85,
  );

  /// 宽松预设。
  static const spacious = StylePreset(
    pagePadding: 24, slotPadding: 20, slotGap: 24, cardGap: 16,
    titlePaddingH: 16, titlePaddingV: 12, cardRadius: 14, chipRadius: 6,
    cardElevation: 2, titleScale: 1.1, bodyScale: 1.05,
  );

  /// 标准预设（默认）。
  static const standard = StylePreset();
}

/// InheritedWidget 注入 [StylePreset]。
class StylePresetScope extends InheritedWidget {
  final StylePreset preset;

  const StylePresetScope({super.key, required this.preset, required super.child});

  static StylePreset of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<StylePresetScope>();
    return scope?.preset ?? StylePreset.standard;
  }

  @override
  bool updateShouldNotify(StylePresetScope old) => preset != old.preset;
}
