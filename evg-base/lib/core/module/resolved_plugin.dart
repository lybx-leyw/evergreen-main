/// 解析后的插件单一事实源（M0 · 3.4）。
///
/// 一份 manifest 同时驱动：installer(签名/哈希) = registry(路由) = loader(运行时)
/// = 权限执行器(白名单)。为避免四方各读各的 JSON，引入 [ResolvedPlugin]——
/// 由 [ModuleDescriptor]（输入）解析而来的**不可变**运行时事实源，以上四方只消费它。
///
/// 设计上游：`plugin-ecosphere.md` M0 · 3.4 / `evg-base/docs/m0-lattice-contract-design.md`。
library;

import 'lattice.dart';
import 'module_descriptor.dart';
import 'runtime.dart';

/// 插件运行时单一事实源——manifest 解析后的不可变视图。
///
/// 持有原始 [ModuleDescriptor] 引用，并向上暴露契约层关键字段
/// （lattice / runtime / capabilities），供 registry / loader / 权限执行器统一消费。
class ResolvedPlugin {
  /// 原始模块描述符（不可变，seal 后不再变）。
  final ModuleDescriptor descriptor;

  /// 六格契约等级（已解析为具体值，显式或推断）。
  final Lattice lattice;

  /// 是否为 manifest 中显式声明的 lattice（区分显式与推断）。
  final bool latticeExplicit;

  /// sidecar 运行时描述符（仅 [Lattice.sidecar] 非空）。
  final RuntimeDescriptor? runtime;

  /// 能力申请（仅 sidecar 格由 [runtime] 携带；其它格为 deny-all）。
  RuntimeCapabilities get capabilities =>
      runtime?.capabilities ?? const RuntimeCapabilities();

  const ResolvedPlugin({
    required this.descriptor,
    required this.lattice,
    required this.latticeExplicit,
    this.runtime,
  });

  /// 从 [ModuleDescriptor] 解析为 [ResolvedPlugin]。
  ///
  /// [ModuleDescriptor] 在 `fromJson` 时已完成 lattice/runtime 的解析与校验，
  /// 此处直接消费其已解析字段（不重复解析 JSON）。
  factory ResolvedPlugin.fromDescriptor(ModuleDescriptor d) {
    return ResolvedPlugin(
      descriptor: d,
      lattice: d.lattice ?? Lattice.staticWeb,
      latticeExplicit: d.latticeExplicit,
      runtime: d.runtime,
    );
  }

  /// 模块 id（[descriptor.id]）。
  String get id => descriptor.id;

  /// 模块名（[descriptor.name]）。
  String get name => descriptor.name;

  /// 是否 sidecar 格（需启动语言运行时进程）。
  bool get isSidecar => lattice == Lattice.sidecar;

  /// 是否纯静态（无需任何进程 / bridge 开票）。
  bool get isStatic => lattice == Lattice.staticWeb;

  /// 是否外部应用（深链，不内嵌）。
  bool get isExternalApp => lattice == Lattice.externalApp;

  @override
  bool operator ==(Object other) =>
      other is ResolvedPlugin && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'ResolvedPlugin($id, lattice=$lattice, sidecar=$isSidecar)';
}
