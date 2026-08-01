// 纯 Dart 测试：安卓数据源安全网（规划 §5.3 C）。
// 验证 DataSourceManifest.androidSupport 解析 + isSupportedOn / cliDataSourceSupportedOn
// 在「安卓且 androidSupport=false」时正确隐藏数据源。
// 不挂载 widget、不碰 SharedPreferences，绝不挂死。

import 'package:evergreen_base/core/data/plugin/data_source_manifest.dart';
import 'package:evergreen_base/core/data/register_data_source.dart';
import 'package:flutter_test/flutter_test.dart';

const _httpManifestJson = <String, dynamic>{
  'type': 'data-source',
  'id': 'demo-http',
  'name': 'Demo HTTP',
  'process': 'server.py',
  'preferredPort': 8765,
  'dataTypes': [
    {
      'name': 'demo',
      'endpoint': 'http://localhost:{port}/data',
    }
  ],
};

void main() {
  group('DataSourceManifest.androidSupport', () {
    test('默认 androidSupport=true', () {
      final m = DataSourceManifest.fromJson(_httpManifestJson);
      expect(m.androidSupport, isTrue);
    });

    test('显式 androidSupport=false 被读取', () {
      final m = DataSourceManifest.fromJson({
        ..._httpManifestJson,
        'androidSupport': false,
      });
      expect(m.androidSupport, isFalse);
    });

    test('toJson 仅当 false 时写出 androidSupport', () {
      final defaultJson =
          DataSourceManifest.fromJson(_httpManifestJson).toJson();
      expect(defaultJson.containsKey('androidSupport'), isFalse);

      final offJson = DataSourceManifest.fromJson({
        ..._httpManifestJson,
        'androidSupport': false,
      }).toJson();
      expect(offJson['androidSupport'], isFalse);
    });
  });

  group('isSupportedOn (http 长驻路径)', () {
    final supported =
        DataSourceManifest.fromJson(_httpManifestJson); // androidSupport=true
    final unsupported = DataSourceManifest.fromJson({
      ..._httpManifestJson,
      'androidSupport': false,
    });

    test('桌面平台始终加载', () {
      expect(DataSourceManifest.isSupportedOn(supported, isAndroid: false),
          isTrue);
      expect(DataSourceManifest.isSupportedOn(unsupported, isAndroid: false),
          isTrue);
    });

    test('安卓平台按 androidSupport 隐藏', () {
      expect(DataSourceManifest.isSupportedOn(supported, isAndroid: true),
          isTrue);
      expect(DataSourceManifest.isSupportedOn(unsupported, isAndroid: true),
          isFalse);
    });
  });

  group('cliDataSourceSupportedOn (CLI 一次性路径)', () {
    test('缺省 androidSupport → 安卓也加载', () {
      expect(
          cliDataSourceSupportedOn(
              {'type': 'data-source'}, isAndroid: true),
          isTrue);
    });

    test('androidSupport=false → 安卓隐藏', () {
      expect(
          cliDataSourceSupportedOn(
              {'type': 'data-source', 'androidSupport': false},
              isAndroid: true),
          isFalse);
    });

    test('androidSupport=false 但桌面 → 仍加载', () {
      expect(
          cliDataSourceSupportedOn(
              {'type': 'data-source', 'androidSupport': false},
              isAndroid: false),
          isTrue);
    });
  });
}
