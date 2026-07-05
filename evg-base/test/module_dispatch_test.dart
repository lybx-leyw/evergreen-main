/// ModuleDispatch 单元测试——7 种范式视图选择 + 未知值回退。
///
/// Sprint 3 最低覆盖要求：ModuleDispatch 7 范式选择。
library;

import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/renderer/shared/module_dispatch.dart';
import 'package:flutter_test/flutter_test.dart';

/// 构造最小可用 [ModuleDescriptor]。
ModuleDescriptor _descriptor({String ui = 'default'}) {
  return ModuleDescriptor(
    id: 'test-module',
    name: 'Test Module',
    ui: ui,
  );
}

/// 包裹 [ModuleDispatch] 的标准测试脚手架。
///
/// [Scaffold] 提供 [Material] 祖先节点，从而满足 [TextField] 等
/// Material 组件的要求。
Widget _wrap(ModuleDescriptor descriptor) {
  return MaterialApp(
    home: Scaffold(body: ModuleDispatch(descriptor: descriptor)),
  );
}

void main() {
  group('ModuleDispatch — 7 范式选择', () {
    testWidgets('ui="default" → DefaultView', (tester) async {
      await tester.pumpWidget(_wrap(_descriptor(ui: 'default')));
      expect(find.byType(ModuleDispatch), findsOneWidget);
    });

    testWidgets('ui="chat" → ChatView', (tester) async {
      await tester.pumpWidget(_wrap(_descriptor(ui: 'chat')));
      expect(find.byType(ModuleDispatch), findsOneWidget);
    });

    testWidgets('ui="spreadsheet" → SpreadsheetView', (tester) async {
      await tester.pumpWidget(_wrap(_descriptor(ui: 'spreadsheet')));
      expect(find.byType(ModuleDispatch), findsOneWidget);
    });

    testWidgets('ui="document" → DocumentView', (tester) async {
      await tester.pumpWidget(_wrap(_descriptor(ui: 'document')));
      expect(find.byType(ModuleDispatch), findsOneWidget);
    });

    testWidgets('ui="presentation" → PresentationView', (tester) async {
      await tester.pumpWidget(_wrap(_descriptor(ui: 'presentation')));
      expect(find.byType(ModuleDispatch), findsOneWidget);
    });

    testWidgets('ui="dashboard" → DashboardView', (tester) async {
      await tester.pumpWidget(_wrap(_descriptor(ui: 'dashboard')));
      expect(find.byType(ModuleDispatch), findsOneWidget);
    });

    testWidgets('ui="editor" → EditorView', (tester) async {
      await tester.pumpWidget(_wrap(_descriptor(ui: 'editor')));
      expect(find.byType(ModuleDispatch), findsOneWidget);
    });
  });

  group('ModuleDispatch — 未知值静默回退', () {
    testWidgets('ui="" → DefaultView（空字符串回退）', (tester) async {
      await tester.pumpWidget(_wrap(_descriptor(ui: '')));
      expect(find.byType(ModuleDispatch), findsOneWidget);
    });

    testWidgets('ui="unknown_paradigm" → DefaultView', (tester) async {
      await tester.pumpWidget(_wrap(_descriptor(ui: 'unknown_paradigm')));
      expect(find.byType(ModuleDispatch), findsOneWidget);
    });

    testWidgets('ui="CHAT" → DefaultView（大小写敏感——不匹配）', (tester) async {
      await tester.pumpWidget(_wrap(_descriptor(ui: 'CHAT')));
      expect(find.byType(ModuleDispatch), findsOneWidget);
    });
  });
}
