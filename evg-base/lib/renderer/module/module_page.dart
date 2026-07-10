/// 模块完整页面（V2）——直接派发到 ModuleDispatch。
///
/// V2: LayoutEngine 和 InteractionWrapper 是页面级/组件级关注点，
/// 不再在模块级包裹。ModuleDispatch 内部按 pages/workspace 自动选择视图。
///
/// 公开类：[EvergreenModulePage]
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'module_dispatch.dart';

/// 模块完整页面。
///
/// [workingDirectory] 为模块插件目录（如 `plugins/vocab-tutor/`），
/// 透传给 composite 模式的 [CompositeView] 用于进程管理。
///
/// HTML 模块不经过此页面 — 侧边栏直接 url_launcher 打开外置浏览器。
class EvergreenModulePage extends StatelessWidget {
  final ModuleDescriptor descriptor;
  final String? workingDirectory;
  final String renderMode;

  const EvergreenModulePage({
    super.key,
    required this.descriptor,
    this.workingDirectory,
    this.renderMode = 'dart',
  });

  @override
  Widget build(BuildContext context) {
    return ModuleDispatch(
      descriptor: descriptor,
      workingDirectory: workingDirectory,
      renderMode: renderMode,
    );
  }
}
