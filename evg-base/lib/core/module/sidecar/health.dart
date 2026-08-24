/// sidecar 健康检查协议（M1-2）。
///
/// 定义 `/health` GET 200 判活的**纯逻辑**部分：
/// - 重试次数上限
/// - 退避间隔序列（指数退避 + 抖动上限）
/// - 单次健康判定结果模型
///
/// 真实 HTTP 请求由调用方（依赖 dart:io）注入，本文件不含任何 I/O，可单测。
library;

/// 健康检查配置（纯数据）。
class SidecarHealthPolicy {
  /// 最大重试次数（不含首次）。默认 3。
  final int maxRetries;

  /// 首次重试前的基础等待毫秒。默认 1000。
  final int baseDelayMs;

  /// 退避倍数（指数：base * factor^i）。默认 2。
  final double backoffFactor;

  /// 退避间隔上限（毫秒）。默认 8000。
  final int maxDelayMs;

  const SidecarHealthPolicy({
    this.maxRetries = 3,
    this.baseDelayMs = 1000,
    this.backoffFactor = 2,
    this.maxDelayMs = 8000,
  });

  /// 第 [attempt] 次重试（0-based）前应等待的毫秒。
  ///
  /// 序列：`base * factor^attempt`，封顶 [maxDelayMs]。
  /// [attempt] 越界（≥ maxRetries）返回 -1 表示「不应再等待」。
  int delayForRetry(int attempt) {
    if (attempt < 0 || attempt >= maxRetries) return -1;
    final raw = baseDelayMs * _pow(backoffFactor, attempt);
    final capped = raw > maxDelayMs ? maxDelayMs : raw;
    return capped.toInt();
  }

  /// 完整退避序列（用于日志/测试检视）。长度 = [maxRetries]。
  List<int> get retryDelays => [
        for (var i = 0; i < maxRetries; i++) delayForRetry(i),
      ];
}

double _pow(double base, int exp) {
  var r = 1.0;
  for (var i = 0; i < exp; i++) r *= base;
  return r;
}

/// 单次健康探测结果。
enum HealthVerdict {
  /// 返回 200，健康。
  healthy,

  /// 返回非 200 或抛错，但仍可重试。
  unhealthy,

  /// 已耗尽所有重试，判定死亡。
  dead,
}

/// 把「HTTP 状态码 + 是否抛错」归约为 [HealthVerdict]（纯函数）。
///
/// [attempt] 为当前已尝试次数（含本次，1-based）。[statusCode] 为 null 表示连接失败。
HealthVerdict judgeHealth({
  required int attempt,
  required int? statusCode,
  required int maxRetries,
}) {
  final ok = statusCode == 200;
  if (ok) return HealthVerdict.healthy;
  // 已用尽：本次是第 (maxRetries + 1) 次且仍不健康 → 死亡。
  if (attempt >= maxRetries + 1) return HealthVerdict.dead;
  return HealthVerdict.unhealthy;
}
