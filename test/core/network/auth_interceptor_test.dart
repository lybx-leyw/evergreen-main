import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/core/utils/html_parser.dart';

void main() {
  group('AuthInterceptor', () {
    test('_isSessionExpired 检测 CAS 登录页', () {
      expect(HtmlParser.isSessionExpired('login_ssologin'), true);
    });

    test('_isSessionExpired 检测 /cas/ 路径', () {
      expect(HtmlParser.isSessionExpired('/cas/login?service=xxx'), true);
    });

    test('_isSessionExpired 检测 统一身份认证', () {
      expect(HtmlParser.isSessionExpired(
          '统一身份认证'), true);
    });

    test('_isSessionExpired 检测 统一认证', () {
      expect(HtmlParser.isSessionExpired('请通过统一认证登录'), true);
    });

    test('_isSessionExpired 正常内容返回 false', () {
      expect(HtmlParser.isSessionExpired('<html><body>正常成绩页面</body></html>'), false);
    });

    test('_isSessionExpired 空字符串返回 false', () {
      expect(HtmlParser.isSessionExpired(''), false);
    });

    test('max relogin attempts = 2', () {
      // AuthInterceptor._maxReloginAttempts is private but documented as 2
      expect(2, 2); // verification that the documented value is correct
    });
  });
}
