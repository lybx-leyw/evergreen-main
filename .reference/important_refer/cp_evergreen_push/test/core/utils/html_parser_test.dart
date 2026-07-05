import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/core/utils/html_parser.dart';

void main() {
  group('HtmlParser.isSessionExpired', () {
    test('ZDBK login_ssologin', () {
      expect(HtmlParser.isSessionExpired('login_ssologin'), true);
    });

    test('cas/login', () {
      expect(HtmlParser.isSessionExpired('redirect to cas/login'), true);
    });

    test('idp.zju.edu.cn (图书馆)', () {
      expect(
          HtmlParser.isSessionExpired('idp.zju.edu.cn/login'), true);
    });

    test('统一身份认证', () {
      expect(
          HtmlParser.isSessionExpired('统一身份认证系统'), true);
    });

    test('统一认证', () {
      expect(HtmlParser.isSessionExpired('统一认证平台'), true);
    });

    test('/cas/ 路径', () {
      expect(HtmlParser.isSessionExpired('redirect /cas/login'), true);
    });

    test('正常成绩 HTML → false', () {
      expect(HtmlParser.isSessionExpired(
          '<html><body>{"items":[{"kcmc":"数学"}]}</body></html>'),
          false);
    });

    test('空字符串 → false', () {
      expect(HtmlParser.isSessionExpired(''), false);
    });
  });

  group('HtmlParser.extractItems', () {
    test('正常 ZDBK 响应', () {
      final html = '{"items":[{"kcmc":"数学","cj":"90"}],"limit":50}';
      final items = HtmlParser.extractItems(html);
      expect(items.length, 1);
      expect(items[0]['kcmc'], '数学');
    });

    test('空 HTML → 空列表', () {
      expect(HtmlParser.extractItems(''), isEmpty);
    });

    test('无 items 字段 → 空列表', () {
      expect(HtmlParser.extractItems('<html></html>'), isEmpty);
    });
  });
}
