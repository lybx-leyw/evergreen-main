/// 插件编排 Slot 注册 —— 在 CompositeView 的 SlotDispatch 中注册为 "plugin-designer"。
///
/// 用法：在 manifest.json 的 component 中设置 `"type": "plugin-designer"`
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'plugin_designer_view.dart';

/// SlotDispatch 中使用的插件编排视图入口。
///
/// 参数:
/// - [slotKey]: CompositeView 分配的 Slot 唯一标识
/// - [moduleId]: 所属模块 ID
/// - [pluginsDir]: plugins 根目录路径
class PluginDesignerSlot extends ConsumerWidget {
  final String slotKey;
  final String moduleId;
  final String? pluginsDir;

  const PluginDesignerSlot({
    super.key,
    required this.slotKey,
    required this.moduleId,
    this.pluginsDir,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PluginDesignerView(
      slotKey: slotKey,
      moduleId: moduleId,
      pluginsDir: pluginsDir,
    );
  }
}
