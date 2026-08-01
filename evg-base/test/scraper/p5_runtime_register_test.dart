/// A-P5 Batch 2（B1 运行期热注册 + B2 闭环验证出数）单元测试。
///
/// 覆盖 [registerDataSourcesFromManifest]（与启动扫描同契约）以及
/// 「注册 → resolveDataSource → 非 null」的闭环验证（fake fetcher）。
library;

import 'dart:io';

import 'package:evergreen_base/core/data/orchestrator.dart';
import 'package:evergreen_base/core/data/register_data_source.dart';
import 'package:evergreen_base/core/data/type.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/renderer/atomic/data_source_resolver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('registerDataSourcesFromManifest', () {
    test('从 data/manifest.json 注册 dataType（脚本可不存在仍注册）', () {
      final dir = Directory(p.join('.dart_tool', 'p5_b2_test', 'weather'))
        ..createSync(recursive: true);
      final dataDir = Directory(p.join(dir.path, 'data'))..createSync();
      File(p.join(dataDir.path, 'manifest.json')).writeAsStringSync('''
{
  "type": "data-source",
  "script": "scraper.py",
  "dataTypes": [
    {"name": "weather", "typeArg": "weather", "ttl": "5m", "category": "气象"}
  ]
}
''');

      final orch = DataOrchestrator();
      final registered = registerDataSourcesFromManifest(
        orch: orch,
        pluginDir: dir.path,
        projectRoot: '.',
      );

      expect(registered, equals(['weather']));
      expect(orch.isRegistered(const DataType(name: 'weather')), isTrue);

      // 同一份契约：typeArg 透传给 CLI fetcher（缺脚本 → 调用时优雅失败，但注册成功）
      dir.deleteSync(recursive: true);
    });

    test('onlyType 过滤只注册指定类型', () {
      final dir = Directory(p.join('.dart_tool', 'p5_b2_test', 'multi'))
        ..createSync(recursive: true);
      final dataDir = Directory(p.join(dir.path, 'data'))..createSync();
      File(p.join(dataDir.path, 'manifest.json')).writeAsStringSync('''
{
  "type": "data-source",
  "script": "scraper.py",
  "dataTypes": [
    {"name": "a", "typeArg": "a"},
    {"name": "b", "typeArg": "b"}
  ]
}
''');

      final orch = DataOrchestrator();
      final registered = registerDataSourcesFromManifest(
        orch: orch,
        pluginDir: dir.path,
        projectRoot: '.',
        onlyType: 'b',
      );

      expect(registered, equals(['b']));
      expect(orch.isRegistered(const DataType(name: 'b')), isTrue);
      expect(orch.isRegistered(const DataType(name: 'a')), isFalse);

      dir.deleteSync(recursive: true);
    });

    test('manifest 缺失 → 返回空列表且不抛', () {
      final dir = Directory(p.join('.dart_tool', 'p5_b2_test', 'empty'))
        ..createSync(recursive: true);
      final orch = DataOrchestrator();
      final registered = registerDataSourcesFromManifest(
        orch: orch,
        pluginDir: dir.path,
        projectRoot: '.',
      );
      expect(registered, isEmpty);
      dir.deleteSync(recursive: true);
    });
  });

  group('B2 闭环：注册 → resolveDataSource 非 null', () {
    test('fake fetcher 注册后 orch://courses 可解析出真实数据', () async {
      final orch = DataOrchestrator();
      orch.register<Map<String, dynamic>>(
        const DataType<Map<String, dynamic>>(name: 'courses'),
        () async => {
          'source': 'evergreen',
          'items': [
            {'id': 1, 'title': '数学'},
            {'id': 2, 'title': '物理'},
          ]
        },
      );

      const ds = DataSourceDescriptor(endpoint: 'orch://courses');
      final data = await resolveDataSource(ds: ds, orch: orch);

      expect(data, isNotNull);
      expect(data['source'], equals('evergreen'));
      expect((data['items'] as List).length, equals(2));
    });

    test('未注册类型 → resolveDataSource 返回 null（优雅降级）', () async {
      final orch = DataOrchestrator();
      const ds = DataSourceDescriptor(endpoint: 'orch://unknown');
      final data = await resolveDataSource(ds: ds, orch: orch);
      expect(data, isNull);
    });
  });
}
