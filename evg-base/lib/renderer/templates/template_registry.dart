/// 模板（modle）路由注册表（v5P）。
///
/// 按 manifest 顶层 `template` 字段路由到对应 [ModleRenderer]。
/// 未知/缺失 → 回退 'v4'（兼容现有全部 pages 模块）。
library;

import 'package:flutter/widgets.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'template.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/v4_modle_template.dart';
import 'package:evergreen_base/renderer/templates/zju_modle/zju_modle_template.dart';
import 'package:evergreen_base/renderer/templates/paper_reading_modle/paper_reading_modle_template.dart';
import 'package:evergreen_base/renderer/templates/html_modle/html_modle_template.dart';
import 'package:evergreen_base/renderer/templates/scraper_modle/scraper_template.dart';
import 'package:evergreen_base/renderer/templates/theme_creator_modle/theme_creator_modle_template.dart';

/// 模板路由注册表。
///
/// 使用：
/// ```dart
/// // 渲染某模块（自动按 descriptor.template 选择模板）
/// TemplateRegistry.render(context, descriptor: descriptor, workingDirectory: wd);
///
/// // 扩展新模板
/// TemplateRegistry.register('zju', const ZjuModleTemplate());
/// ```
class TemplateRegistry {
  static final Map<String, ModleRenderer> _renderers = {
    'v4': const V4ModleTemplate(),
    'zju': const ZjuModleTemplate(),
    // 兼容别名：旧插件 manifest 若声明 classroom/zdbk，仍路由到合并后的 zju 渲染器。
    'classroom': const ZjuModleTemplate(),
    'zdbk': const ZjuModleTemplate(),
    'paper_reading': const PaperReadingModleTemplate(),
    'html': const HtmlModleTemplate(),
    'scraper': const ScraperTemplate(),
    'theme-creator': const ThemeCreatorModleTemplate(),
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
