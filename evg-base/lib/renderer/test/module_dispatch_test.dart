/// ModuleDispatch 范式调度测试——shared/ 层调度器的 widgetTest。
///
/// 验证根据 descriptor.ui 字段正确分发到对应范式视图。
/// 验证未知 ui 值回退到 DefaultView（容错设计）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/renderer/module/module_dispatch.dart';
import 'package:evergreen_base/renderer/components/data/card_list_slot.dart';
import 'package:evergreen_base/renderer/components/data/chart_slot.dart';
import 'package:evergreen_base/renderer/components/document/code_editor_slot.dart';
import 'package:evergreen_base/renderer/page/composite_view.dart';

void main() {
  group('ModuleDispatch — 范式调度', () {
    // ── 已知范式 ──

    testWidgets('dispatches to DefaultView for "default" ui', (tester) async {
      const descriptor = ModuleDescriptor(
        id: 'test',
        name: 'Test',
        ui: 'default',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ModuleDispatch(descriptor: descriptor),
          ),
        ),
      );

      expect(find.byType(DefaultView), findsOneWidget);
    });

    testWidgets('dispatches to DashboardView for "dashboard" ui', (tester) async {
      const descriptor = ModuleDescriptor(
        id: 'test',
        name: 'Test',
        ui: 'dashboard',
        dataBindings: [
          DataBindingDescriptor(
            dataType: 'kpi',
            display: 'card',
            columns: ['title', 'value'],
          ),
        ],
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ModuleDispatch(descriptor: descriptor),
          ),
        ),
      );

      expect(find.byType(DashboardView), findsOneWidget);
    });

    testWidgets('dispatches to EditorView for "editor" ui', (tester) async {
      const descriptor = ModuleDescriptor(
        id: 'test',
        name: 'Test',
        ui: 'editor',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ModuleDispatch(descriptor: descriptor),
          ),
        ),
      );

      expect(find.byType(EditorView), findsOneWidget);
    });

    testWidgets('dispatches to CompositeView for "composite" ui', (tester) async {
      const descriptor = ModuleDescriptor(
        id: 'test',
        name: 'Test',
        ui: 'composite',
        pages: [
          PageDescriptor(
            id: 'page1',
            label: '页面1',
          ),
        ],
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ModuleDispatch(descriptor: descriptor),
          ),
        ),
      );

      expect(find.byType(CompositeView), findsOneWidget);
    });

    // ── 未知范式（容错） ──

    testWidgets('falls back to DefaultView for unknown ui value', (tester) async {
      const descriptor = ModuleDescriptor(
        id: 'test',
        name: 'Test',
        ui: 'unknown-paradigm-xyz',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ModuleDispatch(descriptor: descriptor),
          ),
        ),
      );

      // 未知值应回退到 DefaultView，不崩溃
      expect(find.byType(DefaultView), findsOneWidget);
    });

    testWidgets('falls back to DefaultView for empty ui string', (tester) async {
      const descriptor = ModuleDescriptor(
        id: 'test',
        name: 'Test',
        ui: '',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ModuleDispatch(descriptor: descriptor),
          ),
        ),
      );

      expect(find.byType(DefaultView), findsOneWidget);
    });

    // ── 边界条件 ──

    testWidgets('handles descriptor with minimal fields', (tester) async {
      const descriptor = ModuleDescriptor(
        id: 'minimal',
        name: 'Minimal',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ModuleDispatch(descriptor: descriptor),
          ),
        ),
      );

      // 不崩溃，应该渲染 DefaultView（默认 ui = 'default'）
      expect(find.byType(DefaultView), findsOneWidget);
    });

    testWidgets('renders module name in UI', (tester) async {
      const descriptor = ModuleDescriptor(
        id: 'test-module',
        name: '测试模块名称',
        ui: 'default',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ModuleDispatch(descriptor: descriptor),
          ),
        ),
      );

      // 模块名称应出现在 UI 中
      expect(find.text('测试模块名称'), findsOneWidget);
    });
  });
}
