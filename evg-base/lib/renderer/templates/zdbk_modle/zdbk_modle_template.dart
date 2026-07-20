/// zdbk-modle 模板入口（v5P）。
///
/// 独立 modle：经数据中枢（orch://zdbk_*）拉取 8 类教务数据，内部按
/// 「成绩 / 课程 / 其他」路由渲染。UI 逻辑照抄 `.reference` 的 zdbk 相关
/// 页面，仅将数据来源由「内嵌/直连」改为「调用数据中枢」。
library;

import 'package:flutter/widgets.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/core/utils/greenix_path.dart';
import 'package:evergreen_base/renderer/templates/template.dart';

import 'zdbk_view.dart';

/// ZDBK 教务模板渲染器。
class ZdbkModleTemplate extends ModleRenderer {
  const ZdbkModleTemplate();

  @override
  Widget build(
    BuildContext context, {
    required ModuleDescriptor descriptor,
    String? workingDirectory,
  }) {
    return ZdbkView(
      descriptor: descriptor,
      moduleId: descriptor.id,
      pluginsDir: resolvePluginsRoot(),
    );
  }
}
