/// Port of reasonix/internal/sysproxy/sysproxy_test.go.
library;

import 'package:evergreen_base/core/agent/ref/sysproxy/sysproxy.dart'
    as sysproxy;
import 'package:test/test.dart';

void main() {
  group('parseProxyList', () {
    test('single all-protocol proxy', () {
      final got = sysproxy.parseProxyList('proxy.example.com:8080', 'https');
      expect(got, isNotNull);
      expect(got.toString(), 'http://proxy.example.com:8080');
    });

    test('per-protocol https', () {
      final got = sysproxy.parseProxyList('http=p1:80;https=p2:443', 'https');
      expect(got.toString(), 'http://p2:443');
    });

    test('per-protocol http', () {
      final got = sysproxy.parseProxyList('http=p1:80;https=p2:443', 'http');
      expect(got.toString(), 'http://p1:80');
    });

    test('scheme miss falls back to bare', () {
      final got = sysproxy.parseProxyList('p0:3128;ftp=p1:21', 'https');
      expect(got.toString(), 'http://p0:3128');
    });

    test('strips scheme prefix', () {
      final got = sysproxy.parseProxyList('http://p:8080', 'https');
      expect(got.toString(), 'http://p:8080');
    });

    test('empty list', () {
      expect(sysproxy.parseProxyList('', 'https'), isNull);
    });

    test('only other protocol no bare', () {
      expect(sysproxy.parseProxyList('ftp=p:21', 'https'), isNull);
    });
  });

  group('bypassed', () {
    test('local bypass only matches dotless hosts', () {
      expect(sysproxy.bypassed('api.deepseek.com', '<local>'), isFalse);
      expect(sysproxy.bypassed('intranet', '<local>'), isTrue);
    });

    test('wildcard suffix', () {
      expect(sysproxy.bypassed('host.corp.local', '*.corp.local'), isTrue);
    });

    test('wildcard does not bypass unrelated host', () {
      expect(sysproxy.bypassed('api.deepseek.com', '*.corp.local;<local>'),
          isFalse);
    });

    test('exact host match is case-insensitive', () {
      expect(sysproxy.bypassed('API.DeepSeek.com', 'api.deepseek.com'), isTrue);
    });

    test('empty bypass list', () {
      expect(sysproxy.bypassed('api.deepseek.com', ''), isFalse);
    });
  });
}
