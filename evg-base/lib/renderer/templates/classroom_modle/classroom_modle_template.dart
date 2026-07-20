/// classroom-modle 模板入口（v5P）。
///
/// 独立 modle：数据经 manifest 模块级 `dataSource`（orch://<type>）拉取，
/// 自身私有组件（video/ppt/subtitle）全在 `classroom_modle/` 内，不依赖 v4。
library;

import 'package:flutter/widgets.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/core/utils/greenix_path.dart';
import 'package:evergreen_base/renderer/templates/template.dart';

import 'classroom_view.dart';

/// 教室模板渲染器。
class ClassroomModleTemplate extends ModleRenderer {
  const ClassroomModleTemplate();

  @override
  Widget build(
    BuildContext context, {
    required ModuleDescriptor descriptor,
    String? workingDirectory,
  }) {
    // 注意：上层传入的 workingDirectory 是「模块目录」（plugins/<id>/，已含 moduleId）。
    // 但 ClassroomView._resolvePath 走 resolvePluginAssetPath(raw, moduleId, pluginsDir)，
    // 该函数在内部会再拼一次 moduleId → 若直接传模块目录会得到
    // plugins/<id>/<id>/... 的错误双层路径。故此处必须传「插件根目录」，
    // 让 resolvePluginAssetPath 拼出 plugins/<id>/<raw> 的正确绝对路径。
    return ClassroomView(
      dataSource: descriptor.dataSource,
      moduleId: descriptor.id,
      pluginsDir: resolvePluginsRoot(),
    );
  }
}
