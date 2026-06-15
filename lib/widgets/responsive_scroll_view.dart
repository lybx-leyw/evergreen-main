import 'package:flutter/material.dart';
import 'breakpoints.dart';

/// 响应式滚动视图——内容居中且受限于最大宽度。
///
/// 在大屏幕上防止内容过度拉伸，同时保持在小屏幕的可滚动性。
///
/// ```dart
/// ResponsiveScrollView(
///   padding: EdgeInsets.all(16),
///   children: [...],
/// )
/// ```
class ResponsiveScrollView extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final ScrollController? controller;

  const ResponsiveScrollView({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.all(16),
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: controller,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Breakpoints.medium),
          child: Padding(
            padding: padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}
