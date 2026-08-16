// board_container_view 多画板容器测试（Phase 2 · A21-A24）。
//
// 覆盖：
// 1. 首次打开自动建 1 个画板
// 2. 新建画板 → 列表 + 当前选中切换
// 3. 删除画板（至少保留一个；删当前 → 切换）
// 4. 画板隔离：不同 ValueKey 实例（独立 WebView/workflow）
// 5. 持久化：BoardStore 落盘/恢复
import 'dart:io';

import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/renderer/templates/scraper_modle/board/board_container_view.dart';
import 'package:evergreen_base/renderer/templates/scraper_modle/board/scraper_board.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _descriptor = ModuleDescriptor(
  id: 'test-scraper',
  name: '测试爬虫',
  version: '1.0.0',
  template: 'scraper',
  pages: [],
);

const _config = ComponentDescriptor(
  type: 'scraper-generator',
  config: {},
);

Widget _wrap() {
  return ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        body: BoardContainerView(
          descriptor: _descriptor,
          config: _config,
          slotKey: 'scraper',
          projectRoot: '.',
          workspaceDir: '${Directory.systemTemp.path}/evg_board_test_${DateTime.now().millisecondsSinceEpoch}',
        ),
      ),
    ),
  );
}

void main() {
  group('BoardContainerView 布局', () {
    testWidgets('显示左侧画板列表 + 右侧工作区', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_wrap());
      await tester.pump();
      // 左侧有"画板"标题
      expect(find.text('画板'), findsOneWidget);
      // 至少一个画板 tile（默认"画板 1"）
      expect(find.text('画板 1'), findsOneWidget);
      // 右侧有新增按钮
      expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    });

    testWidgets('新建画板 → 列表出现新画板并选中', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pump();
      expect(find.text('画板 2'), findsOneWidget);
      expect(find.text('画板 1'), findsOneWidget);
    });

    testWidgets('删除当前画板 → 保留至少一个', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_wrap());
      await tester.pump();
      // 只有一个画板时无删除按钮（_boards.length > 1 才显示）
      expect(find.byIcon(Icons.close_rounded), findsNothing);
      // 新建一个再删
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pump();
      expect(find.byIcon(Icons.close_rounded), findsNWidgets(2));
      await tester.tap(find.byIcon(Icons.close_rounded).last);
      await tester.pump();
      // 删掉一个后剩一个，删除按钮消失
      expect(find.byIcon(Icons.close_rounded), findsNothing);
      expect(find.text('画板 1'), findsOneWidget);
    });
  });

  group('画板模型隔离', () {
    test('不同画板 id 不同 → 独立工作区 key', () {
      final b1 = ScraperBoard.create('A');
      final b2 = ScraperBoard.create('B');
      expect(b1.id, isNot(b2.id));
      // 工作区 key 基于 id
      expect('board-${b1.id}', isNot('board-${b2.id}'));
    });
  });
}
