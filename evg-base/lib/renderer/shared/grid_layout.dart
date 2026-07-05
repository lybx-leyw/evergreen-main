/// 网格布局——根据 [GridOptions.columns] 将子组件放入多列网格。
///
/// 公开类：[GridLayout]
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import '../docs/render_rules.dart';

/// 分框网格布局。
///
/// 读取 [GridOptions.columns]（计数），间距硬编码为 [GridRules.gap]。
class GridLayout extends StatelessWidget {
  final GridOptions options;
  final List<Widget> children;

  const GridLayout({
    super.key,
    required this.options,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();

    const gap = GridRules.gap;
    final columns = options.columns.clamp(1, GridRules.maxColumns);

    return GridView.count(
      crossAxisCount: columns,
      mainAxisSpacing: gap,
      crossAxisSpacing: gap,
      padding: const EdgeInsets.all(gap),
      children: children,
    );
  }
}
