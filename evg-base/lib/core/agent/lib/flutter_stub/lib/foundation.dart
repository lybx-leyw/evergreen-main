/// Flutter foundation stub for agent package（纯 Dart 测试隔离）。
///
/// 副本 — 与 flutter SDK foundation 库最小签名对齐，仅覆盖 agent 子包
/// 及其 core 副本（plugin_runner / python_env / log）实际用到的符号。
library foundation;

/// 调试打印（镜像 flutter foundation.debugPrint 签名）。
void debugPrint(String? message, {int? wrapWidth}) {
  // 测试环境直接输出到 stdout/stderr，便于失败用例观察。
  // ignore: avoid_print
  print(message ?? '');
}

/// 可见性注解（镜像 flutter foundation.visibleForTesting）。
const visibleForTesting = _VisibleForTesting();

class _VisibleForTesting {
  const _VisibleForTesting();
}
