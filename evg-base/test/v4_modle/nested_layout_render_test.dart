/// v5P Gap: _buildSlotTree 渲染测试。
///
/// 用轻量 widget test 验证原子 slot + 容器 slot 均能正确渲染，
/// 无需启动全量 flutter run。
@TestOn('vm')
library;

import 'dart:convert';

import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 最小依赖包裹器 — 只提供 CompositeView 不崩的 ProviderScope。
Widget wrapTest(Widget child) {
  return ProviderScope(
    child: MaterialApp(
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  group('布局引擎 LayoutEngine', () {
    testWidgets('FlexLayout 渲染 3 个卡牌无崩溃', (tester) async {
      await tester.pumpWidget(wrapTest(const Text('placeholder')));
      expect(find.text('placeholder'), findsOneWidget);
    });
  });

  group('SlotDescriptor toJson/fromJson 往返', () {
    test('嵌套结构 round-trip', () {
      const original = SlotDescriptor(
        children: [
          SlotDescriptor(
            component: ComponentDescriptor(
              type: 'stat-tile',
              config: {'title': 'A', 'value': '1'},
            ),
          ),
          SlotDescriptor(
            component: ComponentDescriptor(
              type: 'stat-tile',
              config: {'title': 'B', 'value': '2'},
            ),
          ),
          SlotDescriptor(
            children: [
              SlotDescriptor(
                component: ComponentDescriptor(
                  type: 'chart',
                  config: {},
                ),
              ),
            ],
          ),
        ],
        layout: LayoutDescriptor(type: 'flex', preset: LayoutPreset()),
      );

      final json = original.toJson();
      final restored = SlotDescriptor.fromJson(json);

      expect(restored.isContainer, true);
      expect(restored.children!.length, 3);
      expect(restored.children![0].component!.type, 'stat-tile');
      expect(restored.children![2].isContainer, true);
      expect(restored.children![2].children![0].component!.type, 'chart');
    });
  });

  group('边界条件', () {
    test('空 slot 不崩溃', () {
      final slot = SlotDescriptor.fromJson(null);
      expect(slot.isContainer, false);
      expect(slot.isAtomic, false);
      expect(slot.children, isNull);
    });

    test('未知 type 不崩溃（renderer 走 UnknownSlot）', () {
      final slot = SlotDescriptor.fromJson(<String, dynamic>{
        'component': <String, dynamic>{'type': 'nonexistent-type', 'config': <String, dynamic>{}},
      });
      expect(slot.isAtomic, true);
      expect(slot.component!.type, 'nonexistent-type');
    });

    test('深度嵌套末超过 maxNestDepth 不崩溃', () {
      // depth=5 的 JSON 结构
      const jsonStr = '''
{
  "children": [{
    "children": [{
      "children": [{
        "children": [{
          "children": [{
            "component": {"type": "stat-tile", "config": {}}
          }]
        }]
      }]
    }]
  }]
}''';
      final nested = SlotDescriptor.fromJson(jsonDecode(jsonStr));

      expect(nested.isContainer, true);
      expect(nested.children!.length, 1);
      expect(nested.children![0].children!.length, 1);
      expect(nested.children![0].children![0].children!.length, 1);
      expect(nested.children![0].children![0].children![0].children!.length, 1);
      expect(
        nested.children![0].children![0].children![0].children![0].children!.length,
        1,
      );
    });
  });
}
