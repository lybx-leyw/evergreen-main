import 'package:flutter/material.dart';
import 'breakpoints.dart';

/// 自适应布局——根据窗口宽度自动切换 desktop / mobile。
///
/// ≤ [Breakpoints.mobile] → [mobile]，否则 → [desktop]。
///
/// ```dart
/// AdaptiveLayout(
///   desktop: (ctx) => Row(children: [Sidebar(), Expanded(child: child)]),
///   mobile: (ctx) => Scaffold(body: child, bottomNavigationBar: NavBar()),
/// )
/// ```
class AdaptiveLayout extends StatelessWidget {
  final WidgetBuilder desktop;
  final WidgetBuilder mobile;

  const AdaptiveLayout({
    super.key,
    required this.desktop,
    required this.mobile,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <= Breakpoints.mobile) {
          return mobile(context);
        }
        return desktop(context);
      },
    );
  }
}
