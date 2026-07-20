/// 模板（modle）路由注册表（v5P）。
///
/// 按 manifest 顶层 `template` 字段路由到对应 [ModleRenderer]。
/// 未知/缺失 → 回退 'v4'（兼容现有全部 pages 模块）。
library;

import 'package:flutter/widgets.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'template.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/v4_modle_template.dart';
import 'package:evergreen_base/renderer/templates/classroom_modle/classroom_modle_template.dart';
import 'package:evergreen_base/renderer/templates/zdbk_modle/zdbk_modle_template.dart';

/// 模板路由注册表。
///
/// 使用：
/// ```dart
/// // 渲染某模块（自动按 descriptor.template 选择模板）
/// TemplateRegistry.render(context, descriptor: descriptor, workingDirectory: wd);
///
/// // 扩展新模板
/// TemplateRegistry.register('classroom', const ClassroomModleTemplate());
/// ```
class TemplateRegistry {
  static final Map<String, ModleRenderer> _renderers = {
    'v4': const V4ModleTemplate(),
    'classroom': const ClassroomModleTemplate(),
    'zdbk': const ZdbkModleTemplate(),
  };

  /// 注册自定义模板渲染器（插件 / 新模板扩展点）。
  static void register(String name, ModleRenderer renderer) {
    _renderers[name] = renderer;
  }

  /// 解析模板名 → 渲染器，未命中回退 'v4'。
  static ModleRenderer resolve(String? template) {
    final key = (template?.isEmpty ?? true) ? 'v4' : template!;
    return _renderers[key] ?? _renderers['v4']!;
  }

  /// 按描述符渲染：自动按 [ModuleDescriptor.template] 选择对应模板。
  static Widget render(
    BuildContext context, {
    required ModuleDescriptor descriptor,
    String? workingDirectory,
  }) {
    return resolve(descriptor.template).build(
      context,
      descriptor: descriptor,
      workingDirectory: workingDirectory,
    );
  }
}
