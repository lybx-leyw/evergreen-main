// per-type CLI 拉取超时测试（协议 file-data-plugin-protocol-v1 §10 / 依赖 D4）。
//
// 背景：全局 kCliDataSourceTimeout = 60s 且超时会 kill 子进程，大文件冷启动
// 必然被杀。本测试锁定 `dataTypes[].timeoutSeconds` 的解析语义与边界：
// 有效范围 1..3600 秒，越界/非整数一律回落 null（→ 全局 60s），绝不抛。
import 'package:flutter_test/flutter_test.dart';

import 'package:evergreen_base/core/data/plugin/data_source_manifest.dart';

void main() {
  group('parseDataSourceTimeoutSeconds', () {
    test('有效整数 → Duration', () {
      expect(parseDataSourceTimeoutSeconds(90), equals(const Duration(seconds: 90)));
      expect(parseDataSourceTimeoutSeconds(1), equals(const Duration(seconds: 1)));
      expect(parseDataSourceTimeoutSeconds(3600), equals(const Duration(hours: 1)));
    });

    test('<= 0 → null（回落默认，不抛）', () {
      expect(parseDataSourceTimeoutSeconds(0), isNull);
      expect(parseDataSourceTimeoutSeconds(-5), isNull);
    });

    test('> 3600 → null（防天文数字导致永不超时）', () {
      expect(parseDataSourceTimeoutSeconds(3601), isNull);
      expect(parseDataSourceTimeoutSeconds(999999), isNull);
    });

    test('非整数 → null（严格，不做字符串兜底）', () {
      expect(parseDataSourceTimeoutSeconds('90'), isNull,
          reason: '与 ttl 不同：超时不做字符串兜底，避免静默误配');
      expect(parseDataSourceTimeoutSeconds(90.5), isNull);
      expect(parseDataSourceTimeoutSeconds(true), isNull);
      expect(parseDataSourceTimeoutSeconds(null), isNull);
    });

    test('上限常量与解析器一致', () {
      expect(kDataSourceMaxTimeoutSeconds, equals(3600));
      expect(parseDataSourceTimeoutSeconds(kDataSourceMaxTimeoutSeconds),
          equals(const Duration(seconds: 3600)));
    });
  });

  group('DataSourceTypeDecl.timeout（manifest 集成）', () {
    Map<String, dynamic> decl({Object? timeoutSeconds}) => {
          'name': 'demo_file',
          if (timeoutSeconds != null) 'timeoutSeconds': timeoutSeconds,
        };

    test('声明 timeoutSeconds → 解析进 timeout', () {
      final d = DataSourceTypeDecl.fromJson(decl(timeoutSeconds: 600));
      expect(d.timeout, equals(const Duration(minutes: 10)));
    });

    test('未声明 → timeout 为 null（回落全局 60s，零行为变化）', () {
      expect(DataSourceTypeDecl.fromJson(decl()).timeout, isNull);
    });

    test('越界 → timeout 为 null 且不抛', () {
      expect(DataSourceTypeDecl.fromJson(decl(timeoutSeconds: 0)).timeout, isNull);
      expect(DataSourceTypeDecl.fromJson(decl(timeoutSeconds: 99999)).timeout, isNull);
    });

    test('toJson 往返保留 timeoutSeconds', () {
      final d = DataSourceTypeDecl.fromJson(decl(timeoutSeconds: 900));
      expect(d.toJson()['timeoutSeconds'], equals(900));
      final back = DataSourceTypeDecl.fromJson(d.toJson());
      expect(back.timeout, equals(const Duration(seconds: 900)));
    });

    test('未声明 timeout 时 toJson 不写该键（零行为变化）', () {
      expect(DataSourceTypeDecl.fromJson(decl()).toJson().containsKey('timeoutSeconds'),
          isFalse);
    });

    test('与既有可选段共存（fallbackJson / persistentKey / ttl）', () {
      final d = DataSourceTypeDecl.fromJson({
        'name': 'v',
        'category': '视频',
        'ttl': '24h',
        'persistentKey': 'v1',
        'fallbackJson': {'status': 'missing', 'path': null},
        'timeoutSeconds': 1800,
      });
      expect(d.ttl, equals(const Duration(hours: 24)));
      expect(d.persistentKey, equals('v1'));
      expect(d.fallbackJson, isNotNull);
      expect(d.timeout, equals(const Duration(minutes: 30)));
    });
  });
}
