/// 模板（modle）路由注册表（v5P）。
///
/// 按 manifest 顶层 `template` 字段路由到对应 [ModleRenderer]。
/// 未知/缺失 → 回退 'v4'（兼容现有全部 pages 模块）。
///
/// 注册表内容由生成器按 release profile 生成（多套打包支持）：
///   1. 编辑 `templates/templates_index.json`（模板清单）与 `build_profiles/<profile>.json`
///   2. 运行 `dart tool/gen_template_registry.dart --profile <name>`
///   3. 生成的 `generated/template_registry.g.dart` 只 import 选中模板，
///      其余模板由 Dart AOT tree-shaker 自动剔除出产物。
library;

import 'package:flutter/widgets.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'template.dart';
import 'generated/template_registry.g.dart';

/// 模板路由注册表。
///
/// 使用：
/// ```dart
/// // 渲染某模块（自动按 descriptor.template 选择模板）
/// TemplateRegistry.render(context, descriptor: descriptor, workingDirectory: wd);
///
/// // 运行时扩展新模板（不推荐：请走生成器，否则 tree-shaker 无法裁剪）
/// TemplateRegistry.register('xxx', const XxxModleTemplate());
/// ```
class TemplateRegistry {
  static final Map<String, ModleRenderer> _renderers = buildTemplateRegistry();

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
