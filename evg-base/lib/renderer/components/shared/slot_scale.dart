/// Slot 自适应缩放模型。
///
/// 原则：
/// - 滑动方向：scale=1.0（允许内容超出，不缩放）
/// - 非滑动方向：scale = (available / 400).clamp(0.5, 2.0)（等比缩放确保不超屏）
/// - 所有 fontSize、padding、icon size 等硬编码值统一乘 scale
///
/// 用法：
/// ```dart
/// final scale = SlotScale.of(context);
/// // fontSize: 14 * scale, IconSize: 24 * scale, padding: EdgeInsets.all(16 * scale)
/// ```
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 双向缩放因子 — 通过 [SlotScaleScope] 注入。
class SlotScale extends InheritedWidget {
  /// 水平缩放（基准 400px 宽）
  final double hScale;

  /// 垂直缩放（基准 400px 高）
  final double vScale;

  /// 统一缩放 = min(h, v)，用作字体/图标等比缩放。
  double get scale => math.min(hScale, vScale);

  const SlotScale({
    super.key,
    required this.hScale,
    required this.vScale,
    required super.child,
  });

  static SlotScale of(BuildContext context) {
    final s = context.dependOnInheritedWidgetOfExactType<SlotScale>();
    return s ?? const SlotScale(hScale: 1, vScale: 1, child: SizedBox.shrink());
  }

  @override
  bool updateShouldNotify(SlotScale old) => hScale != old.hScale || vScale != old.vScale;

  /// 根据 slot 尺寸和滚动能力计算缩放因子。
  factory SlotScale.compute({
    required double availWidth,
    required double availHeight,
    bool scrollHorizontal = false,
    bool scrollVertical = false,
    Widget? child,
  }) {
    const base = 400.0;
    final h = scrollHorizontal ? 1.0 : (availWidth / base).clamp(0.7, 2.0);
    final v = scrollVertical   ? 1.0 : (availHeight / base).clamp(0.7, 2.0);
    return SlotScale(hScale: h, vScale: v, child: child ?? const SizedBox.shrink());
  }
}

/// 便捷 widget：用 [SlotScale.compute] 包裹子组件。
///
/// [constrain]：为 true 时额外用 `SizedBox(slotWidth, slotHeight)` 包裹，
/// 向子组件注入 tight 约束。用于 `Stack + Positioned`（不带 width/height）
/// 这种无界父容器场景，避免子组件内 `Column(CrossAxisAlignment.stretch)`
/// 因 `BoxConstraints(w=Infinity)` 崩溃。默认 false（仅注入缩放上下文）。
class ScaledSlot extends StatelessWidget {
  final Widget child;
  final double slotWidth;
  final double slotHeight;
  final bool scrollableH;
  final bool scrollableV;
  final bool constrain;

  const ScaledSlot({
    super.key,
    required this.child,
    required this.slotWidth,
    required this.slotHeight,
    this.scrollableH = false,
    this.scrollableV = false,
    this.constrain = false,
  });

  @override
  Widget build(BuildContext context) {
    final scaled = SlotScale.compute(
      availWidth: slotWidth,
      availHeight: slotHeight,
      scrollHorizontal: scrollableH,
      scrollVertical: scrollableV,
      child: child,
    );
    if (constrain) {
      return SizedBox(width: slotWidth, height: slotHeight, child: scaled);
    }
    return scaled;
  }
}
