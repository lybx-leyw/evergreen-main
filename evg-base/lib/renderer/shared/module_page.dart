/// 模块完整页面——LayoutEngine → InteractionWrapper → ModuleDispatch。
///
/// 公开类：[EvergreenModulePage]
///
/// | 构造函数 | 参数 | 说明 |
/// |---------|------|------|
/// | `EvergreenModulePage({descriptor})` | ModuleDescriptor | 构建完整模块页面 |
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'layout_engine.dart';
import 'interaction_wrapper.dart';
import 'module_dispatch.dart';

/// 模块完整页面。
///
/// 将 [ModuleDescriptor] 渲染为完整的模块页面：
/// 1. [LayoutEngine] — 根据 [LayoutDescriptor] 构建布局结构
/// 2. [InteractionWrapper] — 根据 [ActionDescriptor] + [InputOptions] 添加交互层
/// 3. [ModuleDispatch] — 根据 `ui` 字段调度到具体范式视图
///
/// 附加描述符（form / timeline / map / workspace / media）由对应视图自行消费。
///
/// [workingDirectory] 为模块插件目录（如 `plugins/vocab-tutor/`），
/// 透传给 composite 模式的 [CompositeView] 用于进程管理。
class EvergreenModulePage extends StatelessWidget {
  final ModuleDescriptor descriptor;
  final String? workingDirectory;

  const EvergreenModulePage({
    super.key,
    required this.descriptor,
    this.workingDirectory,
  });

  @override
  Widget build(BuildContext context) {
    // composite / chat / settings / multichat 模式：视图自行管理布局和交互。
    // 跳过 LayoutEngine 避免 SingleChildScrollView + Expanded 嵌套冲突。
    if (descriptor.ui == 'composite' ||
        descriptor.ui == 'chat' ||
        descriptor.ui == 'settings' ||
        descriptor.ui == 'multichat') {
      return ModuleDispatch(
        descriptor: descriptor,
        workingDirectory: workingDirectory,
      );
    }
    return LayoutEngine(
      layout: descriptor.layout,
      child: InteractionWrapper(
        actions: descriptor.actions,
        input: descriptor.input,
        child: ModuleDispatch(
          descriptor: descriptor,
          workingDirectory: workingDirectory,
        ),
      ),
    );
  }
}
