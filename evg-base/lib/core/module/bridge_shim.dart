/// 多版本 bridge shim 路由（M2-6，纯逻辑）。
///
/// 同一宿主可同时挂多个 bridge shim 版本：旧插件拿旧 shim，新插件拿新 shim。
/// 路由规则：取「宿主支持且 ≤ 插件请求版本」的最高 shim；插件未声明版本时
/// 回退到宿主默认（通常最低兼容版本），保证旧插件不崩。
library;

/// bridge shim 路由表。
class BridgeShimRouter {
  /// 宿主实际支持的 shim 版本集合（降序无关，内部排序）。
  final Set<int> supported;

  /// 未声明版本时回退的默认 shim（通常为最低兼容版本）。
  final int defaultVersion;

  BridgeShimRouter({
    required this.supported,
    required this.defaultVersion,
  }) {
    if (!supported.contains(defaultVersion)) {
      throw ArgumentError(
          'defaultVersion $defaultVersion 不在 supported $supported 中');
    }
  }

  /// 为某插件选择 shim 版本（纯函数）。
  ///
  /// [requested] 为插件 `platform.hello` 声明的 bridge 版本；
  /// 为 null 表示旧插件（未握手）→ 回退 [defaultVersion]。
  int selectShim(int? requested) {
    if (requested == null) return defaultVersion;
    // 取 supported 中 ≤ requested 的最高版本。
    final candidates = supported.where((v) => v <= requested).toList();
    if (candidates.isEmpty) {
      // 插件请求的版本低于宿主任何 shim → 给最低支持版本（尽量兼容）。
      return supported.reduce((a, b) => a < b ? a : b);
    }
    candidates.sort((a, b) => b.compareTo(a));
    return candidates.first;
  }
}
