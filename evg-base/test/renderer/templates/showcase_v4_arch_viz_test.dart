import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/data/map_slot.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/data/tree_slot.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';



void main() {
  group('showcase-v4 架构可视化页左侧列 slot 配置', () {
    test('MapDescriptor.fromJson 解析 manifest 的嵌套 map 与 markers 列表', () {
      final cfg = <String, dynamic>{
        'map': {
          'center': {'lat': 30.27, 'lng': 120.12},
          'zoom': 12,
          'markers': [
            {'lat': 30.27, 'lng': 120.12, 'label': '杭州研发中心'},
            {'lat': 39.9, 'lng': 116.4, 'label': '北京'},
          ],
        },
      };

      final inner = cfg['map'] as Map<String, dynamic>;
      final map = MapDescriptor.fromJson(inner);

      expect(map.centerLat, 30.27);
      expect(map.centerLng, 120.12);
      expect(map.zoom, 12);
      expect(map.markers, true);
    });

    test('MapDescriptor.fromJson 仍支持 markers 为 bool 的旧格式', () {
      final map = MapDescriptor.fromJson({
        'center': {'lat': 31.0, 'lng': 121.0},
        'zoom': 10,
        'markers': false,
      });

      expect(map.markers, false);
    });

    testWidgets('TreeSlot 无数据源时直接渲染 manifest 中的 root', (tester) async {
      const config = ComponentDescriptor(
        type: 'tree',
        config: {

          'root': {
            'label': 'Evergreen 架构',
            'children': [
              {'label': 'core（Dart 服务）'},
              {'label': 'plugins（JSON + .exe）'},
              {'label': 'renderer（Flutter UI）'},
            ],
          },
        },
      );

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(body: TreeSlot(config: config)),
          ),
        ),
      );

      expect(find.text('Evergreen 架构'), findsOneWidget);
      expect(find.text('core（Dart 服务）'), findsOneWidget);
      expect(find.text('plugins（JSON + .exe）'), findsOneWidget);
      expect(find.text('renderer（Flutter UI）'), findsOneWidget);
      expect(find.text('未配置树结构 (config.root)'), findsNothing);
    });

    testWidgets('MapSlot 无数据源时直接渲染 manifest 中的 map 坐标', (tester) async {
      const config = ComponentDescriptor(
        type: 'map',
        config: {

          'map': {
            'center': {'lat': 30.27, 'lng': 120.12},
            'zoom': 12,
            'markers': [
              {'lat': 30.27, 'lng': 120.12, 'label': '杭州研发中心'},
            ],
          },
        },
      );

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(body: MapSlot(config: config)),
          ),
        ),
      );

      expect(find.text('地图 (30.27, 120.12)'), findsOneWidget);
      expect(find.text('含标记点'), findsOneWidget);
    });
  });
}
