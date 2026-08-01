/// v5P Gap: 集成渲染测试 — 加载真实 showcase-v5 manifest 渲染 CompositeView。
///
/// 目标：在无 flutter run 的情况下定位嵌套布局黑屏根因。
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/providers.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/composite_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 包裹测试用最小 ProviderScope + MaterialApp。
Widget wrapForV4Test(ModuleDescriptor descriptor) {
  return ProviderScope(
    overrides: [
      // 注入虚拟 pluginsDir 防止 pluginsDirProvider 未注入崩溃
      pluginsDirProvider.overrideWith((ref) => Directory.systemTemp.path),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: CompositeView(
          descriptor: descriptor,
        ),
      ),
    ),
  );
}

void main() {
  late ModuleDescriptor nestedOnlyDescriptor;

  setUpAll(() {
    // 构建最小 manifest：仅 nested 页面，2 个 slot（1 原子 + 1 容器含 3 stat-tile）
    nestedOnlyDescriptor = ModuleDescriptor.fromJson(jsonDecode(r'''
{
  "schemaVersion": "2.0",
  "type": "module",
  "id": "test-nested",
  "name": "测试嵌套",
  "pages": [{
    "id": "nested",
    "label": "嵌套测试",
    "layout": {
      "type": "flex",
      "preset": {"direction": "column", "gap": 8},
      "slots": {
        "intro": {
          "component": {
            "type": "markdown",
            "config": {"content": "before"}
          }
        },
        "group": {
          "layout": {"type": "flex", "preset": {"direction": "row", "gap": 8}},
          "children": [
            {"component": {"type": "stat-tile", "config": {"title": "A", "value": "1"}}},
            {"component": {"type": "stat-tile", "config": {"title": "B", "value": "2"}}},
            {"component": {"type": "stat-tile", "config": {"title": "C", "value": "3"}}}
          ]
        }
      }
    }
  }]
}
''') as Map<String, dynamic>);
  });

  group('CompositeView 嵌套渲染', () {
    testWidgets('不崩溃 + 找到 nested 页面的 slot 内容', (tester) async {
      // 触发懒注册（_registrations.dart 的 initV4ModleRegistrations）
      // CompositeViewState.initState() 会调用它

      // 使用 pump 渲染，用 pumpWithoutSettling 避免内部 FutureBuilder 无限等待
      await tester.pumpWidget(wrapForV4Test(nestedOnlyDescriptor));
      await tester.pump(); // 两轮 pump

      // 检查是否正确渲染（不崩溃）
      // 期望找到 stat-tile 的标题文本
      expect(find.text('A'), findsOneWidget,
          reason: '容器内 stat-tile "A" 应渲染');
      expect(find.text('B'), findsOneWidget);
      expect(find.text('C'), findsOneWidget);
    });

    testWidgets('容器 slot kpi-group 子 slot 通过 LayoutEngine 渲染', (tester) async {
      await tester.pumpWidget(wrapForV4Test(nestedOnlyDescriptor));
      await tester.pump();

      // Card title栏显示 slot key
      expect(find.textContaining('📌 group'), findsAtLeast(1),
          reason: '容器 slot 自身标题栏应有 key "group"');
      expect(find.textContaining('📌 intro'), findsOneWidget,
          reason: '原子 slot intro 标题栏应有');
    });

    testWidgets('未知 type 的 slot 不走 UnknownSlot（懒注册已触发）', (tester) async {
      await tester.pumpWidget(wrapForV4Test(nestedOnlyDescriptor));
      await tester.pump();

      // 不应有任何 "尚未实现渲染" 的文本
      expect(find.textContaining('尚未实现渲染'), findsNothing);
    });
  });

  group('纯原子 slot 回归', () {
    test('纯原子不触发嵌套路径', () {
      final d = ModuleDescriptor.fromJson(jsonDecode(r'''
{
  "schemaVersion": "2.0",
  "type": "module",
  "id": "test-atomic",
  "name": "纯原子",
  "pages": [{
    "id": "main",
    "label": "主页",
    "layout": {
      "type": "flex",
      "slots": {
        "a": {"component": {"type": "markdown", "config": {"content": "hello"}}}
      }
    }
  }]
}
''') as Map<String, dynamic>);

      final page = d.pages[0];
      final slots = page.layout.slots;
      expect(slots.length, 1);
      
      final slot = slots['a']!;
      expect(slot.isContainer, false);
      expect(slot.isAtomic, true);
    });
  });
}
