/// dsh-modle 模板入口（v5P · DSH 平台级常驻 Agent）。
///
/// 独立 modle：DSH-mode 承载用户本地 DSH（DeepSeek Harness）的 Web UI。
///
/// 架构（最终决策）：
/// - 用户自装 DSH（`npx @deepseek-ai/dsh web`），跑在本地端口（默认 3080）；
/// - 本模板要求用户填写 DSH 端口号，用 WebView（WebView2）承载 DSH Web UI；
/// - 平台不打包 DSH、不改语言——DSH 终端（agent 循环/工具）在用户机照旧，
///   前端由平台 WebView 承载 HTML。
///
/// 与 scraper-modle 的区别：这里不需要网络捕获/CDP/JS 桥接，只需一个
/// 承载 DSH Web UI 的普通浏览器视图 + 端口配置。
library;

import 'package:flutter/widgets.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/renderer/templates/template.dart';

import 'dsh_modle_view.dart';

/// DSH 模板渲染器。
class DshModleTemplate extends ModleRenderer {
  const DshModleTemplate();

  @override
  Widget build(
    BuildContext context, {
    required ModuleDescriptor descriptor,
    String? workingDirectory,
  }) {
    return DshModleView(descriptor: descriptor);
  }
}
