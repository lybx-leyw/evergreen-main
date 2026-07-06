/// 网格布局——根据 [LayoutPreset.columns] 将子组件放入多列网格。
///
/// V2: 使用 LayoutPreset 替代 V1 的 GridOptions。
///
/// 公开类：[GridLayout]
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import '../docs/render_rules.dart';

/// 分框网格布局。
///
/// 读取 [LayoutPreset.columns]（计数），间距硬编码为 [GridRules.gap]。
class GridLayout extends StatelessWidget {
  final LayoutPreset preset;
  final List<Widget> children;

  const GridLayout({
    super.key,
    required this.preset,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();

    const gap = GridRules.gap;
    final columns = (preset.columns ?? 1).clamp(1, GridRules.maxColumns);

    return GridView.count(
      crossAxisCount: columns,
      mainAxisSpacing: gap,
      crossAxisSpacing: gap,
      padding: const EdgeInsets.all(gap),
      children: children,
    );
  }
}
