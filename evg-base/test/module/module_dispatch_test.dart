/// ModuleDispatch 单元测试 — V2 API（按 pages/workspace 判断视图）。
///
/// Sprint 3 最低覆盖要求：ModuleDispatch 视图选择 + 未知值回退。
library;

import 'dart:async';

import 'package:evergreen_base/core/agent/event.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/providers.dart';
import 'package:evergreen_base/renderer/module/module_dispatch.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 构造 V2 ModuleDescriptor。
ModuleDescriptor _descriptor({
  List<PageDescriptor> pages = const [],
  WorkspaceDescriptor? workspace,
}) {
  return ModuleDescriptor(
    id: 'test-module',
    name: 'Test Module',
    pages: pages,
    workspace: workspace,
  );
}

/// 构造有单页的 ModuleDescriptor。
ModuleDescriptor _withPage() {
  return const ModuleDescriptor(
    id: 'test-module',
    name: 'Test Module',
    pages: [
      PageDescriptor(id: 'main', label: 'Main'),
    ],
  );
}

/// 构造有 workspace 的 ModuleDescriptor。
ModuleDescriptor _withWorkspace() {
  return const ModuleDescriptor(
    id: 'test-module',
    name: 'Test Module',
    workspace: WorkspaceDescriptor(enabled: true),
  );
}

/// 包裹 [ModuleDispatch] 的标准测试脚手架。
Widget _wrap(ModuleDescriptor descriptor) {
  return ProviderScope(
    overrides: [
      agentEventStreamProvider.overrideWithValue(
        const Stream<AgentEvent>.empty(),
      ),
    ],
    child: MaterialApp(
      home: Scaffold(body: ModuleDispatch(descriptor: descriptor)),
    ),
  );
}

void main() {
  group('ModuleDispatch — V2 视图选择', () {
    testWidgets('有 pages → CompositeView', (tester) async {
      await tester.pumpWidget(_wrap(_withPage()));
      expect(find.byType(ModuleDispatch), findsOneWidget);
    });

    testWidgets('无 pages + 有 workspace → EditorView', (tester) async {
      await tester.pumpWidget(_wrap(_withWorkspace()));
      expect(find.byType(ModuleDispatch), findsOneWidget);
    });

    testWidgets('无 pages + 无 workspace → DefaultView（兜底）', (tester) async {
      await tester.pumpWidget(_wrap(_descriptor()));
      expect(find.byType(ModuleDispatch), findsOneWidget);
    });

    testWidgets('空 pages → DefaultView（兜底）', (tester) async {
      await tester.pumpWidget(_wrap(_descriptor(pages: const [])));
      expect(find.byType(ModuleDispatch), findsOneWidget);
    });
  });

  group('ModuleDispatch — 回退不崩溃', () {
    testWidgets('workspace disabled → DefaultView', (tester) async {
      await tester.pumpWidget(_wrap(_descriptor(
        workspace: const WorkspaceDescriptor(enabled: false),
      )));
      expect(find.byType(ModuleDispatch), findsOneWidget);
    });

    testWidgets('workspace null → DefaultView', (tester) async {
      await tester.pumpWidget(_wrap(_descriptor(workspace: null)));
      expect(find.byType(ModuleDispatch), findsOneWidget);
    });
  });
}
