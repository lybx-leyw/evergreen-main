/// theme-creator-modle 模板入口（v5P）。
///
/// 主题创作中心：可视化编辑扁平 8 色主题 → Dart 实时预览 → 一键导出为
/// 主题插件（`plugins/<id>/theme/theme.json`）并热注册到 ThemeStore。
/// 参照 html-creator 的三栏 IDE 交互，但预览为 Dart 渲染（非 WebView/HTML）。
library;

import 'package:flutter/widgets.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/renderer/templates/template.dart';

import 'theme_creator_view.dart';

/// 主题创作中心模板渲染器。
class ThemeCreatorModleTemplate extends ModleRenderer {
  const ThemeCreatorModleTemplate();

  @override
  Widget build(
    BuildContext context, {
    required ModuleDescriptor descriptor,
    String? workingDirectory,
  }) {
    return ThemeCreatorView(descriptor: descriptor);
  }
}
