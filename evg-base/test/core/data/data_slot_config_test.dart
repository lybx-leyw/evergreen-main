import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/data/map_slot.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/data/tree_slot.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('TreeSlot 渲染静态 root 配置', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: TreeSlot(
              config: ComponentDescriptor(
                type: 'tree',
                config: {
                  'root': {
                    'label': 'Evergreen 架构',
                    'children': [
                      {'label': 'core'},
                      {'label': 'plugins'},
                    ],
                  }
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Evergreen 架构'), findsOneWidget);
    expect(find.text('core'), findsOneWidget);
    expect(find.text('plugins'), findsOneWidget);
    expect(find.text('未配置树结构 (config.root)'), findsNothing);
  });

  testWidgets('MapSlot 解析嵌套 map 配置', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: MapSlot(
              config: ComponentDescriptor(
                type: 'map',
                config: {
                  'map': {
                    'center': {'lat': 30.27, 'lng': 120.12},
                    'zoom': 12,
                    'markers': [
                      {'lat': 30.27, 'lng': 120.12, 'label': '杭州'},
                    ],
                  }
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('地图 (30.27, 120.12)'), findsOneWidget);
    expect(find.text('地图 (null, null)'), findsNothing);
    expect(find.text('含标记点'), findsOneWidget);
  });
}
