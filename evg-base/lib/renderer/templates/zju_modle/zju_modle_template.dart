/// zju-modle 模板入口（v5P）——classroom + zdbk 合并后的统一入口。
///
/// 独立 modle：数据经 manifest 模块级 `dataSource` / `dataSources`（orch://<type>）
/// 拉取，UI 按 [ZjuModleView] 分派到教室录播回看（classroom/，视频+PPT+字幕）
/// 或教务页（zdbk/，成绩/课表/考试/开课/培养方案/通知）。两套 UI 家族
/// 均为 modle 私有组件，不依赖 v4。
///
/// 注册键 `'zju'`；同时保留 `'classroom'` / `'zdbk'` 别名指向本渲染器，
/// 兼容旧插件（manifest 的 template 字段与目录名相互独立）。
library;

import 'package:flutter/widgets.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/core/utils/greenix_path.dart';
import 'package:evergreen_base/renderer/templates/template.dart';

import 'zju_view.dart';

/// zju 统一模板渲染器。
class ZjuModleTemplate extends ModleRenderer {
  const ZjuModleTemplate();

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
    return ZjuModleView(
      descriptor: descriptor,
      moduleId: descriptor.id,
      pluginsDir: resolvePluginsRoot(),
    );
  }
}
