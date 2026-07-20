/// v4-modle 模板入口——封装现有 v4 复合渲染（[CompositeView]）。
///
/// 这是"按模板渲染（v5P）"策略下的一个模板实现：v4 的 slot 分派、
/// 五种布局策略、47 个具名组件均为本模板内部私有，不对外共享。
///
/// 阶段 A：仅作为 v4 的收敛入口（封装 [CompositeView]），保持行为零回归。
/// 阶段 B 起由 [template_registry] 按 manifest `template: "v4"` 路由到此。
library;

import 'package:flutter/widgets.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'composite_view.dart';
import 'package:evergreen_base/renderer/templates/template.dart';

/// v4 模板渲染器——直接复用现有 [CompositeView]。
class V4ModleTemplate extends ModleRenderer {
  const V4ModleTemplate();

  @override
  Widget build(
    BuildContext context, {
    required ModuleDescriptor descriptor,
    String? workingDirectory,
  }) {
    return CompositeView(
      descriptor: descriptor,
      workingDirectory: workingDirectory,
    );
  }
}
