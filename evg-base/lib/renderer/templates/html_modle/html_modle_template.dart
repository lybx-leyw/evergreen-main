/// html-modle 模板入口 —— 用 WebView + HTML 渲染插件内容。
///
/// 插件在 manifest.json 中声明 `"template": "html"` 即可使用此模板。
/// 插件只需提供 HTML/CSS/JS 文件，平台提供数据中枢、Agent、设置等 API。
///
/// 与 v4_modle 的区别：
///   - v4_modle: 插件从 47 个预定义组件中选择配置
///   - html_modle: 插件自由定义 HTML 界面，通过 JS Bridge 调用平台能力
library;

import 'package:flutter/widgets.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/renderer/templates/template.dart';
import 'html_modle_view.dart';

/// HTML 模板渲染器。
class HtmlModleTemplate extends ModleRenderer {
  const HtmlModleTemplate();

  @override
  Widget build(
    BuildContext context, {
    required ModuleDescriptor descriptor,
    String? workingDirectory,
  }) {
    return HtmlModleView(
      descriptor: descriptor,
      workingDirectory: workingDirectory,
    );
  }
}
