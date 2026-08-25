/// Android 数据源过滤纯 Dart 测试 —— 规划 §5.3 C 安全网。
///
/// 扩展 data_source_android_support_test.dart，增加：
/// - DataSourceManifest 边界条件（type 校验、空 dataTypes、畸形容器）
/// - toJson 往返一致性（默认 androidSupport=true 时不输出）
/// - isSupportedOn 各种平台组合
/// - cliDataSourceSupportedOn 各种容器形态
/// - 多数据源 manifest 全量字段解析
///
/// 全为纯 Dart 测试，不挂载 widget、不依赖 SharedPreferences。
library;

import 'package:evergreen_base/core/data/plugin/data_source_manifest.dart';
import 'package:evergreen_base/core/data/register_data_source.dart';
import 'package:flutter_test/flutter_test.dart';

const _fullManifestJson = <String, dynamic>{
  'type': 'data-source',
  'id': 'data-courses',
  'name': 'Courses',
  'process': 'server.py',
  'runtime': 'python',
  'preferredPort': 8765,
  'androidSupport': false,
  'dataTypes': [
    {
      'name': 'courses',
      'category': '教务',
      'displayName': '课程数据',
      'ttl': '10m',
      'persistentKey': 'courses_cache',
      'endpoint': 'http://localhost:{port}/courses',
    },
    {
      'name': 'grades',
      'category': '教务',
      'displayName': '成绩数据',
      'ttl': '1h',
      'endpoint': 'http://localhost:{port}/grades',
    },
  ],
};

void main() {
  group('DataSourceManifest 全量字段解析', () {
    test('解析含全部字段的完整 manifest', () {
      final m = DataSourceManifest.fromJson(_fullManifestJson);
      expect(m.id, 'data-courses');
      expect(m.name, 'Courses');
      expect(m.processExe, 'server.py');
      expect(m.runtime, 'python');
      expect(m.preferredPort, 8765);
      expect(m.androidSupport, false);
      expect(m.dataTypes.length, 2);

      // 第一个 dataType
      final t1 = m.dataTypes[0];
      expect(t1.name, 'courses');
      expect(t1.category, '教务');
      expect(t1.displayName, '课程数据');
      expect(t1.ttl, const Duration(minutes: 10));
      expect(t1.persistentKey, 'courses_cache');
      expect(t1.endpoint, 'http://localhost:{port}/courses');

      // 第二个 dataType
      final t2 = m.dataTypes[1];
      expect(t2.name, 'grades');
      expect(t2.ttl, const Duration(hours: 1));
      expect(t2.endpoint, 'http://localhost:{port}/grades');
    });

    test('type 字段不为 data-source 时抛 FormatException', () {
      expect(
        () => DataSourceManifest.fromJson({
          ..._fullManifestJson,
          'type': 'wrong-type',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('type 字段缺失时抛 FormatException', () {
      final json = Map<String, dynamic>.from(_fullManifestJson);
      json.remove('type');
      expect(
        () => DataSourceManifest.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });

    test('dataTypes 为空数组时抛 FormatException', () {
      expect(
        () => DataSourceManifest.fromJson({
          ..._fullManifestJson,
          'dataTypes': <dynamic>[],
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('id 缺失时回退为空字符串（模型 A 兼容，由目录 basename 派生）', () {
      // T1 统一后 id/name 为可选（模型 A scraper 产物无 id/name 仍可解析）
      final json = Map<String, dynamic>.from(_fullManifestJson);
      json.remove('id');
      expect(DataSourceManifest.fromJson(json).id, '');
    });

    test('process 缺失时抛 FormatException', () {
      final json = Map<String, dynamic>.from(_fullManifestJson);
      json.remove('process');
      expect(
        () => DataSourceManifest.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('DataSourceManifest.toJson 往返', () {
    test('完整字段 toJson → fromJson 可逆', () {
      final original = DataSourceManifest.fromJson(_fullManifestJson);
      final roundTrip = DataSourceManifest.fromJson(original.toJson());

      expect(roundTrip.id, original.id);
      expect(roundTrip.name, original.name);
      expect(roundTrip.process, original.process);
      expect(roundTrip.runtime, original.runtime);
      expect(roundTrip.preferredPort, original.preferredPort);
      expect(roundTrip.androidSupport, original.androidSupport);
      expect(roundTrip.dataTypes.length, original.dataTypes.length);
      for (var i = 0; i < roundTrip.dataTypes.length; i++) {
        expect(roundTrip.dataTypes[i].name, original.dataTypes[i].name);
        expect(roundTrip.dataTypes[i].ttl, original.dataTypes[i].ttl);
        expect(roundTrip.dataTypes[i].endpoint, original.dataTypes[i].endpoint);
      }
    });

    test('androidSupport=true（默认）时 toJson 不含 androidSupport 键', () {
      final m = DataSourceManifest.fromJson({
        'type': 'data-source',
        'id': 'test',
        'name': 'Test',
        'process': 'test.py',
        'dataTypes': [
          {'name': 't', 'endpoint': '/t'}
        ],
      });
      final json = m.toJson();
      expect(json.containsKey('androidSupport'), isFalse);
    });

    test('runtime=native 时 toJson 不含 runtime 键', () {
      final m = DataSourceManifest.fromJson({
        'type': 'data-source',
        'id': 'test',
        'name': 'Test',
        'process': 'test.exe',
        'dataTypes': [
          {'name': 't', 'endpoint': '/t'}
        ],
      });
      final json = m.toJson();
      expect(json.containsKey('runtime'), isFalse);
    });
  });

  group('isSupportedOn 边界条件', () {
    final supported =
        DataSourceManifest.fromJson(_fullManifestJson); // androidSupport=false

    test('桌面平台 — 即使 androidSupport=false 也加载', () {
      expect(
          DataSourceManifest.isSupportedOn(supported, isAndroid: false),
          isTrue);
      expect(
          DataSourceManifest.isSupportedOn(supported, isAndroid: false),
          isTrue);
    });

    test('安卓平台 — androidSupport=false 隐藏', () {
      expect(
          DataSourceManifest.isSupportedOn(supported, isAndroid: true),
          isFalse);
    });

    test('安卓平台 — androidSupport=true 加载', () {
      final yes = DataSourceManifest.fromJson({
        ..._fullManifestJson,
        'androidSupport': true,
      });
      expect(DataSourceManifest.isSupportedOn(yes, isAndroid: true), isTrue);
    });
  });

  group('cliDataSourceSupportedOn 边界条件', () {
    test('空 JSON（无 type 字段）仍可通过 androidSupport 检查', () {
      // cliDataSourceSupportedOn 不校验 type，仅看 androidSupport
      expect(cliDataSourceSupportedOn({}, isAndroid: true), isTrue);
    });

    test('androidSupport=true 显式写死', () {
      expect(
          cliDataSourceSupportedOn(
              {'androidSupport': true}, isAndroid: true),
          isTrue);
    });

    test('androidSupport 为非布尔值 → 严格视为 false（跳过）', () {
      // T1 严格 bool：字符串/数字不再视为 true（fail-closed，避免 C 扩展在安卓崩溃）
      expect(
          cliDataSourceSupportedOn(
              {'androidSupport': 'true'}, isAndroid: true),
          isFalse);
      expect(
          cliDataSourceSupportedOn(
              {'androidSupport': 1}, isAndroid: true),
          isFalse);
    });

    test('androidSupport=null → 视为 true', () {
      // null as bool? → ?? true → true
      expect(
          cliDataSourceSupportedOn(
              {'androidSupport': null}, isAndroid: true),
          isTrue);
    });

    test('桌面平台 — 永远返回 true（不管 androidSupport）', () {
      expect(cliDataSourceSupportedOn(
          {'androidSupport': false}, isAndroid: false), isTrue);
      expect(cliDataSourceSupportedOn(
          {'androidSupport': true}, isAndroid: false), isTrue);
      expect(cliDataSourceSupportedOn({}, isAndroid: false), isTrue);
    });
  });
}
