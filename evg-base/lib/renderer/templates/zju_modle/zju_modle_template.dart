/// zju-modle 模板入口（v5P）——浙大 9 个校园 feature 的统一入口。
///
/// B2（2026-08-12）删旧：classroom/ 与 zdbk/ 旧实现已移除，data-zdbk 插件删除，
/// 凭证迁至 settings（ZJU_USERNAME / ZJU_PASSWORD）。UI 按 [ZjuModleView] 的
/// modleRoute 分派到各 feature 视图（B3 逐个移植后填充），数据经数据中枢
/// （orch://zju_*）拉取，全部为 modle 私有组件，不依赖 v4。
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
    // 注意：B3-classroom 起，zju_modle 各 feature 均改为「数据中枢 + SSO 直连」，
    // 不再读取插件本地资源（旧 ClassroomView._resolvePath 已删除）。workingDirectory
    // 仅作兼容占位；pluginsDir 统一传插件根目录供未来可能需要相对资源解析的 feature 使用。
    return ZjuModleView(
      descriptor: descriptor,
      moduleId: descriptor.id,
      pluginsDir: resolvePluginsRoot(),
    );
  }
}
