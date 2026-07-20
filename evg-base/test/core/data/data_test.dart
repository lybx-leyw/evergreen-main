/// M2 P1 数据层单测：json_path / transform_registry / data_source_resolver。
///
/// 运行：cd evg-base && flutter test test/renderer/data_test.dart
import 'package:evergreen_base/core/data/data.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/renderer/atomic/data_source_resolver.dart';
import 'package:evergreen_base/renderer/atomic/json_path.dart';
import 'package:evergreen_base/renderer/atomic/transform_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('extractPath', () {
    final root = {
      'a': {
        'b': [
          {'c': 42},
          {'c': 43},
        ]
      }
    };

    test('点路径 + 数组下标', () {
      expect(extractPath(root, 'a.b[0].c'), 42);
      expect(extractPath(root, 'a.b[1].c'), 43);
    });

    test('缺段返回 null（不崩）', () {
      expect(extractPath(root, 'a.x.y'), isNull);
      expect(extractPath(root, 'a.b[0].z'), isNull);
    });

    test('下标越界返回 null', () {
      expect(extractPath(root, 'a.b[9].c'), isNull);
    });

    test('空路径返回 root，null root 返回 null', () {
      expect(extractPath(root, ''), root);
      expect(extractPath(null, 'a'), isNull);
    });
  });

  group('applyTransform', () {
    test('toRows: List 原样 / Map 包装', () {
      expect(applyTransform('toRows', [{'x': 1}]), [
        {'x': 1}
      ]);
      expect(applyTransform('toRows', {'x': 1}), [
        {'x': 1}
      ]);
    });

    test('toChart: 规整为 {labels, series:[{name,data}]}', () {
      final out = applyTransform('toChart', [
        {'label': 'A', 'value': 3},
        {'label': 'B', 'value': 5}
      ]);
      expect(out['labels'], ['A', 'B']);
      expect(out['series'][0]['data'], [3, 5]);
    });

    test('toChart: 已是标准结构则原样', () {
      final std = {
        'labels': ['X'],
        'series': [
          {'name': 's', 'data': [1]}
        ]
      };
      expect(applyTransform('toChart', std), std);
    });

    test('toCalendar: 规整为 {events:[...]}', () {
      final out = applyTransform('toCalendar', [
        {'date': '2026-07-01', 'title': 'X'}
      ]);
      expect(out['events'], hasLength(1));
    });

    test('未知名称回退 identity', () {
      expect(applyTransform('nope', 'raw'), 'raw');
    });
  });

  group('resolveDataSource', () {
    test('dataType 路径经 DataOrchestrator 拉取', () async {
      final orch = DataOrchestrator();
      orch.register(
        DataType<dynamic>(name: 'myType'),
        () async => {'hello': 'world'},
      );
      final result = await resolveDataSource(
        ds: const DataSourceDescriptor(),
        orch: orch,
        dataType: 'myType',
      );
      expect(result, {'hello': 'world'});
    });

    test('endpoint 路径经注入 httpFetcher 拉取', () async {
      final result = await resolveDataSource(
        ds: const DataSourceDescriptor(endpoint: 'http://example.com/api'),
        httpFetcher: (_) async => {
          'results': [
            {'id': 1}
          ]
        },
      );
      expect(result, {
        'results': [
          {'id': 1}
        ]
      });
    });

    test('endpoint + dataPath + transform 串联', () async {
      final result = await resolveDataSource(
        ds: const DataSourceDescriptor(
          endpoint: 'http://x',
          dataPath: 'results',
          transform: 'toRows',
        ),
        httpFetcher: (_) async => {
          'results': [
            {'a': 1},
            {'a': 2}
          ]
        },
      );
      expect(result, [
        {'a': 1},
        {'a': 2}
      ]);
    });

    test('拉取异常 → 降级返回 null（不抛）', () async {
      final result = await resolveDataSource(
        ds: const DataSourceDescriptor(endpoint: 'http://x'),
        httpFetcher: (_) async => throw Exception('boom'),
      );
      expect(result, isNull);
    });

    test('无 endpoint 也无 dataType → 返回 null', () async {
      final result = await resolveDataSource(ds: const DataSourceDescriptor());
      expect(result, isNull);
    });
  });
}
