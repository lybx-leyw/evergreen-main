// B1（auth 先行）认证层单元测试——纯函数/落盘/状态机，全部离线，不触网。
//
// 覆盖：
//   1. ZjuAmService.rsaEncrypt —— SSO RSA 加密纯函数（确定性 + 已知向量 + 128 位契约）
//   2. CookieStore —— SSO cookie 落盘（往返 / 旧格式迁移 / synjones token / 重载持久化）
//   3. AuthState.parseExpiry —— cookie 过期时间推导
//   4. ZdbkPatterns.executionToken —— CAS 登录页 execution 提取
//   5. HtmlParser —— 会话过期检测 + ZDBK items JSON 提取
//   6. AuthNotifier.login —— 凭证判空（configMissing），不触发真实网络
//
// 依据 2026-07-19 FAIL 经验：SSO 链路不得用真实凭证实跑，仅做离线单测。
import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:evergreen_base/core/errors.dart';
import 'package:evergreen_base/renderer/templates/zju_modle/zju_auth/auth_provider.dart';
import 'package:evergreen_base/renderer/templates/zju_modle/zju_auth/cookie_store.dart';
import 'package:evergreen_base/renderer/templates/zju_modle/zju_auth/html_parser.dart';
import 'package:evergreen_base/renderer/templates/zju_modle/zju_auth/zdbk_patterns.dart';
import 'package:evergreen_base/renderer/templates/zju_modle/zju_auth/zjuam_service.dart';
import 'package:evergreen_base/renderer/templates/zju_modle/zju_auth/zju_auth.dart' as auth;

void main() {
  group('zju_auth 聚合入口（编译冒烟）', () {
    test('导出核心认证符号（AuthService / AuthNotifier / Dio client）', () {
      // 仅引用顶层符号，确保聚合导出涉及的未直接 import 文件（auth_service、
      // auth_interceptor、debug/retry interceptor、network_config 等）被编译。
      expect(auth.zjuAuthProvider, isNotNull);
      expect(auth.AuthService, isNotNull);
      expect(auth.AuthNotifier, isNotNull);
      expect(auth.NetworkConfig, isNotNull);
      expect(auth.HtmlParser, isNotNull);
    });
  });

  group('ZjuAmService.rsaEncrypt（SSO RSA 加密纯函数）', () {
    test('确定性：相同输入产生相同输出', () {
      final a = ZjuAmService.rsaEncrypt('P@ssw0rd', 'aa', '10001');
      final b = ZjuAmService.rsaEncrypt('P@ssw0rd', 'aa', '10001');
      expect(a, b);
    });

    test('已知向量：65^5 mod 81 = 50 → hex 0x32，128 位补零', () {
      // 'A' = UTF-8 0x41 = 65；modulus 0x51 = 81；exponent 0x05 = 5。
      // 65^5 mod 81：65²=4225→13；65⁴=169→7；65⁵=455→50 = 0x32。
      final out = ZjuAmService.rsaEncrypt('A', '51', '05');
      expect(out.length, 128);
      expect(out.substring(126), '32');
    });

    test('输出恒为 128 位 hex（ZJU getPubKey 契约）', () {
      for (final pwd in ['a', 'hello', '浙大密码']) {
        expect(ZjuAmService.rsaEncrypt(pwd, '10001', '3').length, 128);
      }
    });

    test('UTF-8 多字节明文（中文密码）不抛异常', () {
      final out = ZjuAmService.rsaEncrypt('中文密码123', '10001', '3');
      expect(out.length, 128);
    });
  });

  group('CookieStore（SSO cookie 落盘）', () {
    late Directory tmp;
    late CookieStore store;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('zju_cookie_test');
      store =
          await CookieStore.createForTesting('${tmp.path}/zju_cookies.json');
    });

    tearDown(() async {
      await tmp.delete(recursive: true);
    });

    test('setSsoCookie → ssoCookie 往返', () async {
      await store.setSsoCookie('ABC123');
      expect(store.ssoCookie, 'ABC123');
    });

    test('旧格式 "iPlanetDirectoryPro=xxx" 迁移剥离前缀', () async {
      await store.setCookie('iPlanetDirectoryPro', 'iPlanetDirectoryPro=OLD');
      expect(store.ssoCookie, 'OLD');
    });

    test('synjones-auth token 存取与清除', () async {
      await store.setSynjonesAuthToken('bearer-token-xyz');
      expect(store.synjonesAuthToken, 'bearer-token-xyz');
      await store.clearSynjonesAuthToken();
      expect(store.synjonesAuthToken, isNull);
    });

    test('clearSsoCookie 后 ssoCookie 为 null', () async {
      await store.setSsoCookie('X');
      await store.clearSsoCookie();
      expect(store.ssoCookie, isNull);
    });

    test('重新加载（新实例）仍能读到落盘 cookie', () async {
      await store.setSsoCookie('PERSISTED');
      final reloaded =
          await CookieStore.createForTesting('${tmp.path}/zju_cookies.json');
      expect(reloaded.ssoCookie, 'PERSISTED');
    });
  });

  group('AuthState.parseExpiry', () {
    test('expires 优先返回', () {
      final when = DateTime(2026, 8, 12, 10, 30);
      final c = Cookie('iPlanetDirectoryPro', 'x')..expires = when;
      expect(AuthState.parseExpiry(c), when);
    });

    test('maxAge → 相对 now 推导（约 1 小时）', () {
      final c = Cookie('iPlanetDirectoryPro', 'x')..maxAge = 3600;
      final e = AuthState.parseExpiry(c);
      expect(e, isNotNull);
      expect(e!.difference(DateTime.now()),
          greaterThan(const Duration(minutes: 59)));
    });

    test('无过期信息 → null', () {
      final c = Cookie('iPlanetDirectoryPro', 'x');
      expect(AuthState.parseExpiry(c), isNull);
    });
  });

  group('ZdbkPatterns.executionToken', () {
    test('从 CAS 登录页 HTML 提取 execution', () {
      const html = '<html><body>'
          '<input type="hidden" name="execution" value="e1s1_abc"/>'
          '<input type="hidden" name="_eventId" value="submit"/></body></html>';
      final m = ZdbkPatterns.executionToken.firstMatch(html);
      expect(m, isNotNull);
      expect(m!.group(1), 'e1s1_abc');
    });
  });

  group('HtmlParser', () {
    test('isSessionExpired 命中各 CAS 变体', () {
      expect(HtmlParser.isSessionExpired('<a href="login_ssologin.html">'),
          isTrue);
      expect(HtmlParser.isSessionExpired('统一身份认证'), isTrue);
      expect(HtmlParser.isSessionExpired('window.location="/cas/login"'),
          isTrue);
      expect(HtmlParser.isSessionExpired('正常教务页面数据'), isFalse);
    });

    test('extractItems 提取 limit / totalResult 两种边界', () {
      expect(HtmlParser.extractItems('{"items":[{"a":1}],"limit":10}'),
          hasLength(1));
      expect(
          HtmlParser.extractItems(
              '{"items":[{"a":1},{"b":2}],"totalResult":2}'),
          hasLength(2));
      expect(HtmlParser.extractItems('<html>无数据</html>'), isEmpty);
    });
  });

  group('AuthNotifier.login 凭证判空（不触发网络）', () {
    test('未配置学号密码 → configMissing 错误', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final tmp = await Directory.systemTemp.createTemp('zju_jar_test');
      final notifier = AuthNotifier(
        Dio(),
        PersistCookieJar(storage: FileStorage('${tmp.path}/.cookies')),
        HttpClient(),
        prefs,
      );
      final ok = await notifier.login();
      expect(ok, isFalse);
      expect(notifier.state.isLoggedIn, isFalse);
      expect(notifier.state.error, isA<ConfigError>());
      // ConfigError.configMissing 的 userMessage 为「缺少必要配置」，
      // 缺失项在 debugMessage 中（evg-base 错误契约）。
      expect(notifier.state.error!.debugMessage, contains('学号和密码'));
      await tmp.delete(recursive: true);
    });
  });
}
