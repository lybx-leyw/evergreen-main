/// 模板（modle）渲染器统一接口。
///
/// v5P 渲染策略：渲染按"模板类型"分派。每个 modle 实现 [ModleRenderer]，
/// 由 [template_registry] 按 manifest 顶层 `template` 字段路由。
///
/// 共享原子层（`renderer/atomic/`）提供取数原语；本接口与实现均不含
/// 任何跨模板共享的具名组件或布局策略——那些是各 modle 内部私有。
library;

import 'package:flutter/widgets.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';

/// 单个模板的渲染入口。
///
/// [descriptor] 为已解析的模块描述符（manifest.json）；
/// [workingDirectory] 为插件目录路径（用于进程管理 / 资源解析），可为空。
abstract class ModleRenderer {
  const ModleRenderer();

  Widget build(
    BuildContext context, {
    required ModuleDescriptor descriptor,
    String? workingDirectory,
  });
}
