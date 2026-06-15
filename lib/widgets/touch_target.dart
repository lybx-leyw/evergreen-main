import 'package:flutter/material.dart';

/// 确保 widget 满足 48×48dp 最小触摸区域（Material 无障碍规范）。
///
/// ```dart
/// IconButton(
///   icon: Icon(Icons.close),
///   onPressed: () {},
/// ).minTouchTarget  // extension method
/// ```
extension MinTouchTarget on Widget {
  Widget get minTouchTarget => SizedBox(
        width: 48,
        height: 48,
        child: Center(child: this),
      );
}
