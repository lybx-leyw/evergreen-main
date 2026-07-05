import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:evergreen_multi_tools/core/connectivity/connection_manager.dart';
import 'package:evergreen_multi_tools/features/auth/providers/auth_provider.dart';

void main() {
  group('ConnectionResult', () {
    test('ok=true 构造', () {
      final r = ConnectionResult(
        service: 'ZJUAM SSO', ok: true, elapsed: Duration.zero,
      );
      expect(r.ok, true);
      expect(r.service, 'ZJUAM SSO');
      expect(r.message, isNull);
    });

    test('ok=false 携带错误消息', () {
      final r = ConnectionResult(
        service: 'ZDBK 教务网', ok: false,
        message: 'SSO 未登录', elapsed: const Duration(milliseconds: 100),
      );
      expect(r.ok, false);
      expect(r.message, 'SSO 未登录');
    });

    test('elapsed 正确记录', () {
      final r = ConnectionResult(
        service: 'test', ok: true,
        elapsed: const Duration(milliseconds: 500),
      );
      expect(r.elapsed.inMilliseconds, 500);
    });
  });

  group('ConnectionManager', () {
    late HttpClient httpClient;
    late PersistCookieJar jar;

    setUp(() {
      httpClient = HttpClient();
      jar = PersistCookieJar(ignoreExpires: true);
    });

    tearDown(() {
      httpClient.close();
    });

    // 注意：checkAll/checkOne 需要真实 SSO cookie，这里只测基本构造
    test('构造函数不抛异常', () {
      final mgr = ConnectionManager(
        httpClient, jar,
        AuthState(isLoggedIn: false),
        () => throw UnimplementedError('no ZDBK'),
      );
      expect(mgr, isNotNull);
    });
  });
}
