import 'package:flutter/widgets.dart';

/// 侧边栏分类——支持内置 + 插件自定义。
///
/// 模块通过 [ModuleDescriptor.sidebar] 的 section 字段指定所属分类。
/// 也可在代码中直接创建实例用于自定义分组。
///
/// ```dart
/// static const mySection = SidebarSection('我的分类', order: 35);
/// ```
class SidebarSection {
  /// UI 展示文本。
  final String label;

  /// 分类间排序权重（越小越靠前）。
  final int order;

  const SidebarSection(this.label, {this.order = 50});

  @override
  bool operator ==(Object other) =>
      other is SidebarSection && other.label == label && other.order == order;

  @override
  int get hashCode => label.hashCode ^ order.hashCode;

  @override
  String toString() => 'SidebarSection($label, order=$order)';
}

