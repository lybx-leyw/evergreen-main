/// Flutter foundation stub for data package（纯 Dart 测试隔离）。
///
/// 副本 — 与 flutter SDK foundation 库最小签名对齐，仅覆盖 data 子包
/// 及其 core 副本（orchestrator / greenix_path / plugin_runner）用到的符号。
library foundation;

/// 可见性注解：与 flutter SDK 一致，从 meta 导出同一声明，
/// 避免与显式 import meta 的模块（如 orchestrator.dart）产生歧义冲突。
export 'package:meta/meta.dart' show visibleForTesting;

/// 调试打印（镜像 flutter foundation.debugPrint 签名）。
void debugPrint(String? message, {int? wrapWidth}) {
  // ignore: avoid_print
  print(message ?? '');
}
