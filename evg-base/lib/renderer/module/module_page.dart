/// 模块完整页面（V2）——直接派发到 ModuleDispatch。
///
/// V2: LayoutEngine 和 InteractionWrapper 是页面级/组件级关注点，
/// 不再在模块级包裹。ModuleDispatch 内部按 pages/workspace 自动选择视图。
///
/// 公开类：[EvergreenModulePage]
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/marketplace/plugin_state_provider.dart';
import 'module_dispatch.dart';

/// 模块完整页面。
///
/// [workingDirectory] 为模块插件目录（如 `plugins/vocab-tutor/`），
/// 透传给 composite 模式的 [CompositeView] 用于进程管理。
class EvergreenModulePage extends ConsumerStatefulWidget {
  final ModuleDescriptor descriptor;
  final String? workingDirectory;
  final String renderMode;
  /// 来自路由 query 的 AI 预填 prompt（classroom-modle 的 AI 笔记按钮带入）。
  final String? initialPrompt;

  const EvergreenModulePage({
    super.key,
    required this.descriptor,
    this.workingDirectory,
    this.renderMode = 'dart',
    this.initialPrompt,
  });

  @override
  ConsumerState<EvergreenModulePage> createState() => _EvergreenModulePageState();
}

class _EvergreenModulePageState extends ConsumerState<EvergreenModulePage> {
  @override
  void initState() {
    super.initState();
    // 记录插件打开时间（lastUsedAt）——驱动插件中心「按最近使用」排序。
    // 页面每次被打开（路由推入）都会新建 State，initState 恰好对应一次「使用」。
    // 内置模块（无状态记录）也会由 touch() 补建默认记录。
    ref.read(pluginStateProvider.notifier).touch(widget.descriptor.id);
  }

  @override
  Widget build(BuildContext context) {
    return ModuleDispatch(
      descriptor: widget.descriptor,
      workingDirectory: widget.workingDirectory,
      renderMode: widget.renderMode,
      initialPrompt: widget.initialPrompt,
    );
  }
}
