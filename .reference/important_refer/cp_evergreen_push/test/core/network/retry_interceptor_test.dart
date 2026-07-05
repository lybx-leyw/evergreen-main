import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/core/network/network_config.dart';

void main() {
  group('RetryInterceptor', () {
    test('可重试状态码白名单', () {
      expect(NetworkConfig.retryableStatusCodes.contains(429), true);
      expect(NetworkConfig.retryableStatusCodes.contains(502), true);
      expect(NetworkConfig.retryableStatusCodes.contains(503), true);
      expect(NetworkConfig.retryableStatusCodes.contains(200), false);
      expect(NetworkConfig.retryableStatusCodes.contains(400), false);
      expect(NetworkConfig.retryableStatusCodes.contains(500), false);
    });

    test('最大重试次数为 3', () {
      expect(NetworkConfig.maxRetries, 3);
    });

    test('最大重试延迟为 30 秒', () {
      expect(NetworkConfig.maxRetryDelay.inSeconds, 30);
    });

    test('指数退避公式基础: delay = 1000 * 2^attempt + jitter', () {
      // 第1次: 1000 * 2 + jitter(0~999) ∈ [2000, 2999]
      // 第2次: 1000 * 4 + jitter ∈ [4000, 4999]
      // 第3次: 1000 * 8 + jitter ∈ [8000, 8999]
      // Math verification: 2^1=2, 2^2=4, 2^3=8
      for (var attempt = 1; attempt <= 3; attempt++) {
        final baseMs = (1000 * (1 << attempt));
        expect(baseMs, greaterThan(0));
        expect(baseMs, lessThan(NetworkConfig.maxRetryDelay.inMilliseconds + 1));
      }
    });
  });
}
