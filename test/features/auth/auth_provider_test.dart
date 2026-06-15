import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/features/auth/providers/auth_provider.dart';

void main() {
  group('AuthState.parseExpiry', () {
    test('无过期信息时返回 null', () {
      final cookie = Cookie('iPlanetDirectoryPro', 'test-value');
      expect(AuthState.parseExpiry(cookie), isNull);
    });

    test('从 expires 提取过期时间', () {
      final expires = DateTime.now().add(const Duration(hours: 2));
      final cookie = Cookie('iPlanetDirectoryPro', 'test-value')
        ..expires = expires;
      final result = AuthState.parseExpiry(cookie);
      expect(result, isNotNull);
      // 精确到秒范围内
      expect(result!.difference(expires).inSeconds.abs(), lessThan(2));
    });

    test('从 maxAge 计算过期时间', () {
      final cookie = Cookie('iPlanetDirectoryPro', 'test-value')
        ..maxAge = 7200; // 2 hours
      final result = AuthState.parseExpiry(cookie);
      expect(result, isNotNull);
      final expected = DateTime.now().add(const Duration(seconds: 7200));
      expect(result!.difference(expected).inSeconds.abs(), lessThan(2));
    });

    test('maxAge 为 0 或负数时返回 null', () {
      final cookie = Cookie('iPlanetDirectoryPro', 'test-value')
        ..maxAge = 0;
      expect(AuthState.parseExpiry(cookie), isNull);

      final cookie2 = Cookie('iPlanetDirectoryPro', 'test-value')
        ..maxAge = -1;
      expect(AuthState.parseExpiry(cookie2), isNull);
    });

    test('expires 优先级高于 maxAge', () {
      final expires = DateTime.now().add(const Duration(hours: 1));
      final cookie = Cookie('iPlanetDirectoryPro', 'test-value')
        ..expires = expires
        ..maxAge = 7200;
      final result = AuthState.parseExpiry(cookie);
      expect(result, isNotNull);
      expect(result!.difference(expires).inSeconds.abs(), lessThan(2));
    });

    test('ssoExpiresAt 在 copyWith 中正确传递', () {
      final now = DateTime.now();
      final state1 = AuthState(isLoggedIn: true, ssoExpiresAt: now);
      expect(state1.ssoExpiresAt, now);

      // copyWith 保留原值
      final state2 = state1.copyWith(isLoggedIn: true);
      expect(state2.ssoExpiresAt, now);

      // clearExpiry 清除
      final state3 = state1.copyWith(clearExpiry: true);
      expect(state3.ssoExpiresAt, isNull);

      // 新值覆盖
      final later = now.add(const Duration(hours: 1));
      final state4 = state1.copyWith(ssoExpiresAt: later);
      expect(state4.ssoExpiresAt, later);
    });
  });
}
