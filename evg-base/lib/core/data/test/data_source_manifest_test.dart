/// DataSourceManifest 统一 typed model 测试。
///
/// 覆盖：
/// - 模型 A（CLI）/ 模型 B（HTTP）旧 manifest 回归解析（含 `id`/`name` 缺省、`endpoint` 可缺省）
/// - `process` 字符串 / 对象双形态、`script`/`process` 互斥
/// - 新增可选字段 `auth` / `stream` / `file` / process 增强（scope/autoStart/autoRestart/protocol/preferredPort）
/// - `category` 默认「未分类」、TTL（s/m/h/ms/纯秒数）统一、`androidSupport` 严格 bool
/// - 未知字段静默忽略、toJson 可选段仅非默认值写出
///
/// 纯 Dart 测试，不触文件系统 / 进程 / Flutter。
library;

import 'package:test/test.dart';

import '../plugin/data_source_manifest.dart';

void main() {
  group('模型 B（HTTP 长驻）回归解析', () {
    test('process 为字符串的旧 manifest 仍可解析', () {
      final m = DataSourceManifest.fromJson({
        'type': 'data-source',
        'id': 'scores',
        'name': '成绩数据源',
        'process': 'plugin.exe',
        'preferredPort': 8765,
        'dataTypes': [
          {
            'name': 'scores',
            'category': '教务',
            'displayName': '成绩单',
            'endpoint': '/api/scores',
          }
        ],
      });
      expect(m.process, isNotNull);
      expect(m.process!.exe, 'plugin.exe');
      expect(m.processExe, 'plugin.exe');
      expect(m.preferredPort, 8765);
      expect(m.dataTypes.single.endpoint, '/api/scores');
    });

    test('process 为对象（mesh_demo/super_app 漂移形态）可解析', () {
      final m = DataSourceManifest.fromJson({
        'type': 'data-source',
        'id': 'mesh_demo_data',
        'name': '微服务网格演示数据',
        'process': {'exe': 'mesh_server.py'},
        'runtime': 'python',
        'dataTypes': [
          {'name': 'mesh_status', 'endpoint': '/mesh/status'}
        ],
      });
      expect(m.process!.exe, 'mesh_server.py');
      expect(m.processExe, 'mesh_server.py');
      expect(m.runtime, 'python');
    });

    test('id/name 缺省时（统一后为可选）不抛错', () {
      final m = DataSourceManifest.fromJson({
        'type': 'data-source',
        'process': 'server.py',
        'dataTypes': [
          {'name': 't', 'endpoint': '/t'}
        ],
      });
      expect(m.id, '');
      expect(m.name, '');
    });
  });

  group('模型 A（CLI）回归解析', () {
    test('script + typeArg 旧 manifest 可解析（含未知字段静默忽略）', () {
      final m = DataSourceManifest.fromJson({
        'type': 'data-source',
        'runtime': 'python',
        'script': 'scraper.py',
        'boardId': 'board_1787204819382_0004', // 未知字段
        'createdBy': 'scraper-capture', // 未知字段
        'dataTypes': [
          {
            'name': 'zju_grades',
            'typeArg': 'zju_grades',
            'ttl': '5m',
            'persistentKey': 'custom-zju_grades:zju_grades',
            'category': 'zju_grades',
            'displayName': 'zju_grades',
            'fields': <Map<String, dynamic>>[], // 未知字段
          }
        ],
      });
      expect(m.script, 'scraper.py');
      expect(m.process, isNull);
      expect(m.id, '');
      expect(m.dataTypes.single.typeArg, 'zju_grades');
      expect(m.dataTypes.single.endpoint, isNull); // 模型 A endpoint 可缺省
      expect(m.dataTypes.single.category, 'zju_grades');
      expect(m.dataTypes.single.persistentKey, 'custom-zju_grades:zju_grades');
    });

    test('category 缺省统一为「未分类」', () {
      final m = DataSourceManifest.fromJson({
        'type': 'data-source',
        'script': 'fetch.py',
        'dataTypes': [
          {'name': 'x'}
        ],
      });
      expect(m.dataTypes.single.category, '未分类');
    });
  });

  group('script/process 互斥', () {
    test('两者都缺 → 抛 FormatException', () {
      expect(
        () => DataSourceManifest.fromJson({
          'type': 'data-source',
          'dataTypes': [
            {'name': 'x'}
          ],
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('两者都给 → 抛 FormatException', () {
      expect(
        () => DataSourceManifest.fromJson({
          'type': 'data-source',
          'script': 'fetch.py',
          'process': 'server.py',
          'dataTypes': [
            {'name': 'x'}
          ],
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('type 非 data-source → 抛 FormatException', () {
      expect(
        () => DataSourceManifest.fromJson({
          'type': 'other',
          'script': 'fetch.py',
          'dataTypes': [
            {'name': 'x'}
          ],
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('dataTypes 为空 → 抛 FormatException', () {
      expect(
        () => DataSourceManifest.fromJson({
          'type': 'data-source',
          'script': 'fetch.py',
          'dataTypes': <dynamic>[],
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('TTL 统一解析', () {
    test('parseDataSourceTtl 支持 s/m/h/ms/纯秒数', () {
      expect(parseDataSourceTtl('30s'), const Duration(seconds: 30));
      expect(parseDataSourceTtl('5m'), const Duration(minutes: 5));
      expect(parseDataSourceTtl('1h'), const Duration(hours: 1));
      expect(parseDataSourceTtl('500ms'), const Duration(milliseconds: 500));
      expect(parseDataSourceTtl('90'), const Duration(seconds: 90));
      expect(parseDataSourceTtl(120), const Duration(seconds: 120));
      expect(parseDataSourceTtl(null), isNull);
      expect(parseDataSourceTtl('abc'), isNull);
    });

    test('dataType ttl 缺省默认 5 分钟', () {
      final m = DataSourceManifest.fromJson({
        'type': 'data-source',
        'script': 'fetch.py',
        'dataTypes': [
          {'name': 'x'}
        ],
      });
      expect(m.dataTypes.single.ttl, const Duration(minutes: 5));
    });

    test('dataType ttl 支持 ms（原模型 A 内联正则缺失）', () {
      final m = DataSourceManifest.fromJson({
        'type': 'data-source',
        'script': 'fetch.py',
        'dataTypes': [
          {'name': 'x', 'ttl': '750ms'}
        ],
      });
      expect(m.dataTypes.single.ttl, const Duration(milliseconds: 750));
    });
  });

  group('androidSupport 严格 bool 解析', () {
    test('parseDataSourceAndroidSupport：缺省 true / 仅 bool 有效 / 非 bool 视为 false',
        () {
      expect(parseDataSourceAndroidSupport(null), isTrue);
      expect(parseDataSourceAndroidSupport(true), isTrue);
      expect(parseDataSourceAndroidSupport(false), isFalse);
      expect(parseDataSourceAndroidSupport('false'), isFalse);
      expect(parseDataSourceAndroidSupport('true'), isFalse);
      expect(parseDataSourceAndroidSupport(1), isFalse);
      expect(parseDataSourceAndroidSupport(0), isFalse);
      expect(parseDataSourceAndroidSupport(<String>[]), isFalse);
    });

    test('fromJson 缺省 androidSupport=true', () {
      final m = DataSourceManifest.fromJson({
        'type': 'data-source',
        'script': 'fetch.py',
        'dataTypes': [
          {'name': 'x'}
        ],
      });
      expect(m.androidSupport, isTrue);
    });

    test('fromJson 非 bool androidSupport 视为 false', () {
      final m = DataSourceManifest.fromJson({
        'type': 'data-source',
        'script': 'fetch.py',
        'androidSupport': 'false',
        'dataTypes': [
          {'name': 'x'}
        ],
      });
      expect(m.androidSupport, isFalse);
    });
  });

  group('新增可选字段解析', () {
    test('auth 解析（引用凭据 key，不重复声明值）', () {
      final m = DataSourceManifest.fromJson({
        'type': 'data-source',
        'script': 'fetch.py',
        'auth': {
          'sessionProvider': 'zju',
          'sessionDomain': 'jwxt.zju.edu.cn',
          'credentialKeys': ['ZJU_USERNAME', 'ZJU_PASSWORD'],
        },
        'dataTypes': [
          {'name': 'x'}
        ],
      });
      expect(m.auth, isNotNull);
      expect(m.auth!.sessionProvider, 'zju');
      expect(m.auth!.sessionDomain, 'jwxt.zju.edu.cn');
      expect(m.auth!.credentialKeys, ['ZJU_USERNAME', 'ZJU_PASSWORD']);
    });

    test('auth.sessionDomain 缺省为 null（回退 sessionProvider 分组）', () {
      final m = DataSourceManifest.fromJson({
        'type': 'data-source',
        'script': 'fetch.py',
        'auth': {'sessionProvider': 'zju'},
        'dataTypes': [
          {'name': 'x'}
        ],
      });
      expect(m.auth!.sessionDomain, isNull);
    });

    test('auth 缺省为 null（零行为变化）', () {
      final m = DataSourceManifest.fromJson({
        'type': 'data-source',
        'script': 'fetch.py',
        'dataTypes': [
          {'name': 'x'}
        ],
      });
      expect(m.auth, isNull);
    });

    test('process 对象增强字段解析', () {
      final m = DataSourceManifest.fromJson({
        'type': 'data-source',
        'process': {
          'exe': 'server.py',
          'scope': 'short',
          'autoStart': false,
          'autoRestart': true,
          'protocol': 'stdio',
          'preferredPort': 9000,
        },
        'dataTypes': [
          {'name': 'x', 'endpoint': '/x'}
        ],
      });
      expect(m.process!.scope, 'short');
      expect(m.process!.autoStart, isFalse);
      expect(m.process!.autoRestart, isTrue);
      expect(m.process!.protocol, 'stdio');
      expect(m.process!.preferredPort, 9000);
      expect(m.preferredPort, 9000);
    });

    test('stream/file 解析', () {
      final m = DataSourceManifest.fromJson({
        'type': 'data-source',
        'script': 'fetch.py',
        'dataTypes': [
          {
            'name': 'live',
            'stream': {
              'enabled': true,
              'protocol': 'hls',
              'mime': 'video/mp4',
              'credentialed': true,
            },
            'file': {'enabled': true, 'downloadEndpoint': '/download'},
          }
        ],
      });
      final d = m.dataTypes.single;
      expect(d.stream, isNotNull);
      expect(d.stream!.enabled, isTrue);
      expect(d.stream!.protocol, 'hls');
      expect(d.stream!.mime, 'video/mp4');
      expect(d.stream!.credentialed, isTrue);
      expect(d.file, isNotNull);
      expect(d.file!.enabled, isTrue);
      expect(d.file!.downloadEndpoint, '/download');
    });

    test('stream/file 缺省为 null', () {
      final m = DataSourceManifest.fromJson({
        'type': 'data-source',
        'script': 'fetch.py',
        'dataTypes': [
          {'name': 'x'}
        ],
      });
      expect(m.dataTypes.single.stream, isNull);
      expect(m.dataTypes.single.file, isNull);
    });

    test('fallbackJson 解析为顶层 Map（静态兜底）', () {
      final m = DataSourceManifest.fromJson({
        'type': 'data-source',
        'script': 'fetch.py',
        'dataTypes': [
          {
            'name': 'x',
            'fallbackJson': {'items': <dynamic>[], 'fromFallback': true},
          }
        ],
      });
      final d = m.dataTypes.single;
      expect(d.fallbackJson, isNotNull);
      expect(d.fallbackJson!['fromFallback'], isTrue);
      // toDataType 透传 fallback 到 DataType
      expect(d.toDataType().fallback, d.fallbackJson);
    });

    test('fallbackJson 缺省为 null（零行为变化）', () {
      final m = DataSourceManifest.fromJson({
        'type': 'data-source',
        'script': 'fetch.py',
        'dataTypes': [
          {'name': 'x'}
        ],
      });
      expect(m.dataTypes.single.fallbackJson, isNull);
      expect(m.dataTypes.single.toDataType().fallback, isNull);
    });

    test('fallbackJson 非 Map 类型静默忽略（不抛）', () {
      final m = DataSourceManifest.fromJson({
        'type': 'data-source',
        'script': 'fetch.py',
        'dataTypes': [
          {'name': 'x', 'fallbackJson': 'not-a-map'},
        ],
      });
      expect(m.dataTypes.single.fallbackJson, isNull);
    });
  });

  group('toJson 序列化', () {
    test('可选段仅非默认值写出', () {
      final m = DataSourceManifest.fromJson({
        'type': 'data-source',
        'script': 'fetch.py',
        'dataTypes': [
          {
            'name': 'x',
            'stream': {'enabled': false}, // 默认关闭 → 不写出
          }
        ],
      });
      final json = m.toJson();
      expect(json.containsKey('auth'), isFalse);
      final dtJson = (json['dataTypes'] as List).single as Map;
      expect(dtJson.containsKey('stream'), isFalse);
      expect(dtJson.containsKey('file'), isFalse);
    });

    test('新增字段 toJson → fromJson 可逆', () {
      final src = {
        'type': 'data-source',
        'id': 'p',
        'name': 'P',
        'process': {
          'exe': 'server.py',
          'protocol': 'stdio',
          'autoRestart': true
        },
        'auth': {
          'sessionProvider': 'zju',
          'sessionDomain': 'jwxt.zju.edu.cn',
          'credentialKeys': ['K']
        },
        'dataTypes': [
          {
            'name': 'x',
            'endpoint': '/x',
            'stream': {'enabled': true, 'protocol': 'sse'},
            'file': {'enabled': true, 'downloadEndpoint': '/dl'},
          }
        ],
      };
      final m = DataSourceManifest.fromJson(src);
      final rt = DataSourceManifest.fromJson(m.toJson());
      expect(rt.auth!.sessionProvider, 'zju');
      expect(rt.auth!.sessionDomain, 'jwxt.zju.edu.cn');
      expect(rt.auth!.credentialKeys, ['K']);
      expect(rt.process!.protocol, 'stdio');
      expect(rt.process!.autoRestart, isTrue);
      expect(rt.dataTypes.single.stream!.protocol, 'sse');
      expect(rt.dataTypes.single.file!.downloadEndpoint, '/dl');
    });

    test('process 字符串形态 round-trip 保持字符串', () {
      final m = DataSourceManifest.fromJson({
        'type': 'data-source',
        'id': 's',
        'name': 'S',
        'process': 'server.py',
        'dataTypes': [
          {'name': 'x', 'endpoint': '/x'}
        ],
      });
      expect(m.toJson()['process'], 'server.py');
    });

    test('buildUrl 替换 {port} 占位符；缺 endpoint 抛 StateError', () {
      final m = DataSourceManifest.fromJson({
        'type': 'data-source',
        'process': 'server.py',
        'dataTypes': [
          {'name': 'x', 'endpoint': '/api/{port}/data'}
        ],
      });
      expect(m.dataTypes.single.buildUrl(8080), '/api/8080/data');

      final noEp = DataSourceManifest.fromJson({
        'type': 'data-source',
        'script': 'fetch.py',
        'dataTypes': [
          {'name': 'y'}
        ],
      });
      expect(() => noEp.dataTypes.single.buildUrl(8080), throwsStateError);
    });
  });
}
