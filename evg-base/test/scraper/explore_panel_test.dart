// 探索面板与数据源多选弹窗 widget 测试（Phase 4 · D1/D4）。
//
// 覆盖：
// 1. idle：渲染「开始探索」按钮并回调
// 2. exploring：阶段标识 + 页数/请求计数 + 同域提示
// 3. confirming：候选 chips + 「重新打开选择框」
// 4. 多选弹窗：默认全选、取消勾选、改名、确认返回
import 'package:evergreen_base/renderer/templates/scraper_modle/explore/explore_panel.dart';
import 'package:evergreen_base/renderer/templates/scraper_modle/explore/explore_workflow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('ExplorePanel', () {
    testWidgets('idle：开始探索按钮触发回调', (tester) async {
      final wf = ExploreWorkflow();
      var called = false;
      await tester.pumpWidget(_wrap(ExplorePanel(
        exploreWorkflow: wf,
        onStartExplore: () async => called = true,
      )));
      expect(find.text('探索模式'), findsOneWidget);
      expect(find.text('待开始'), findsOneWidget);
      await tester.tap(find.text('开始探索'));
      await tester.pump();
      expect(called, isTrue);
    });

    testWidgets('exploring：显示阶段、计数与同域', (tester) async {
      final wf = ExploreWorkflow();
      wf.startExploring(startUrl: 'https://site.com/');
      await tester.pumpWidget(_wrap(ExplorePanel(exploreWorkflow: wf)));
      expect(find.text('探索中'), findsOneWidget);
      expect(find.text('0 / 20'), findsOneWidget);
      expect(find.text('0 / 50'), findsOneWidget);
      expect(find.textContaining('site.com'), findsOneWidget);
    });

    testWidgets('confirming：候选 chips + 重新打开选择框按钮回调', (tester) async {
      final wf = ExploreWorkflow();
      wf.startExploring(startUrl: 'https://site.com/');
      wf.startCategorizing();
      wf.presentCandidates(const [
        CandidateDataSource(name: 'courses', displayName: '课程', category: '课程', url: 'https://site.com/api'),
      ]);
      var reselect = false;
      await tester.pumpWidget(_wrap(ExplorePanel(
        exploreWorkflow: wf,
        onReselectSources: () => reselect = true,
      )));
      expect(find.text('等待确认'), findsOneWidget);
      expect(find.text('courses · 课程'), findsOneWidget);
      await tester.tap(find.text('重新打开选择框'));
      await tester.pump();
      expect(reselect, isTrue);
    });

    testWidgets('done：完成状态 + 选择 chips', (tester) async {
      final wf = ExploreWorkflow();
      wf.startExploring();
      wf.startCategorizing();
      wf.presentCandidates(const [
        CandidateDataSource(name: 'a', displayName: 'A', category: 'cat', url: 'https://x.com/1'),
      ]);
      wf.confirmSelection(const [
        CandidateDataSource(name: 'a', displayName: 'A', category: 'cat', url: 'https://x.com/1'),
      ]);
      wf.startRegistering();
      wf.markDone();
      await tester.pumpWidget(_wrap(ExplorePanel(exploreWorkflow: wf)));
      expect(find.text('✅ 完成'), findsOneWidget);
      expect(find.textContaining('数据看板'), findsOneWidget);
      expect(find.text('a'), findsOneWidget);
    });
  });

  group('showExploreSourcePicker 多选弹窗（D4）', () {
    const candidates = [
      CandidateDataSource(
        name: 'courses',
        displayName: '课程列表',
        category: '课程',
        url: 'https://site.com/api/courses',
        fields: [CandidateField(name: 'id', type: 'number')],
      ),
      CandidateDataSource(
        name: 'teachers',
        displayName: '教师列表',
        category: '教师',
        url: 'https://site.com/api/teachers',
      ),
    ];

    testWidgets('默认全选 → 取消一个 → 改名 → 确认返回', (tester) async {
      List<CandidateDataSource>? result;
      await tester.pumpWidget(_wrap(Builder(
        builder: (ctx) => TextButton(
          onPressed: () async {
            result = await showExploreSourcePicker(ctx, candidates);
          },
          child: const Text('open'),
        ),
      )));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('☑️ 选择要构建的数据源'), findsOneWidget);
      expect(find.byType(Checkbox), findsNWidgets(2));
      expect(find.text('课程列表'), findsOneWidget);
      expect(find.text('教师列表'), findsOneWidget);

      // 取消第二个候选
      await tester.tap(find.byType(Checkbox).at(1));
      await tester.pump();

      // 改名第一个 → renamed
      await tester.enterText(find.byType(TextField).first, 'renamed');
      await tester.pump();

      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.length, 1);
      expect(result!.single.name, 'renamed');
      expect(result!.single.displayName, '课程列表');
    });

    testWidgets('取消按钮 → 返回空列表', (tester) async {
      List<CandidateDataSource>? result;
      await tester.pumpWidget(_wrap(Builder(
        builder: (ctx) => TextButton(
          onPressed: () async {
            result = await showExploreSourcePicker(ctx, candidates);
          },
          child: const Text('open'),
        ),
      )));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(result, isEmpty);
    });

    testWidgets('P0-2：证据徽标展示来源日志与字段路径', (tester) async {
      const withEvidence = [
        CandidateDataSource(
          name: 'courses',
          displayName: '课程列表',
          category: '课程',
          url: 'https://site.com/api/courses',
          sourceLogId: 'log-7',
          fields: [
            CandidateField(
              name: 'id',
              type: 'number',
              sourceJsonPath: r'$.data[0].id',
            ),
          ],
        ),
      ];
      await tester.pumpWidget(_wrap(Builder(
        builder: (ctx) => TextButton(
          onPressed: () => showExploreSourcePicker(ctx, withEvidence),
          child: const Text('open'),
        ),
      )));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.textContaining('📋 log-7'), findsOneWidget);
      expect(find.textContaining(r'id → $.data[0].id'), findsOneWidget);
    });
  });
}
