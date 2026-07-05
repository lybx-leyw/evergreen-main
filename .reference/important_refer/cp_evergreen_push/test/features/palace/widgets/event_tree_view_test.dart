import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/core/palace/models/consciousness_event.dart';
import 'package:evergreen_multi_tools/features/palace/widgets/event_tree_view.dart';

void main() {
  List<ConsciousnessEvent> _makeEvents() {
    final now = DateTime.now();
    return [
      ConsciousnessEvent.create(
        type: EventType.thought,
        source: SourceTool.manual,
        rawContent: '深度工作很重要',
        tagIds: ['habit'],
        emotionalValence: 0.7,
        capturedAt: now,
      ),
      ConsciousnessEvent.create(
        type: EventType.thought,
        source: SourceTool.agent,
        rawContent: '运动提升专注力',
        tagIds: ['health'],
        capturedAt: now,
      ),
      ConsciousnessEvent.create(
        type: EventType.lesson,
        source: SourceTool.manual,
        rawContent: '保护上午时间',
        aiSummary: '用户认为上午是黄金时间',
        tagIds: ['deep-work'],
        capturedAt: now,
      ),
      ConsciousnessEvent.create(
        type: EventType.lesson,
        source: SourceTool.agent,
        rawContent: '每日反思很重要',
        aiSummary: '持续反思能帮助成长',
        tagIds: ['habit'],
        capturedAt: now.subtract(const Duration(days: 1)),
      ),
    ];
  }

  testWidgets('树状视图 → 显示类型节点', (tester) async {
    final events = _makeEvents();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: EventTreeView(events: events)),
      ),
    );

    // 类型节点默认展开 → 日期节点可见
    expect(find.textContaining('想法'), findsOneWidget);
    expect(find.textContaining('教训'), findsOneWidget);
    // 日期节点可见（默认折叠）
    expect(find.text('今天'), findsWidgets);
  });

  testWidgets('空事件 → 显示空状态', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EventTreeView(events: const []),
        ),
      ),
    );

    expect(find.text('宫殿空空如也'), findsOneWidget);
    expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
  });

  testWidgets('展开日期节点 → 可见事件卡片', (tester) async {
    final events = _makeEvents();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: EventTreeView(events: events)),
      ),
    );
    await tester.pump();

    // 找到并点击"今天"日期节点展开它
    final todayNodes = find.text('今天');
    expect(todayNodes, findsWidgets);
    await tester.tap(todayNodes.first);
    await tester.pump();

    // 现在事件卡片应该可见
    expect(find.text('深度工作很重要'), findsOneWidget);
    expect(find.text('运动提升专注力'), findsOneWidget);
  });

  testWidgets('点击事件卡片 → 展开详情', (tester) async {
    final events = _makeEvents();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: EventTreeView(events: events)),
      ),
    );
    await tester.pump();

    // 展开日期节点
    await tester.tap(find.text('今天').first);
    await tester.pump();

    // 点击第一条事件
    await tester.tap(find.text('深度工作很重要'));
    await tester.pump();

    // 详情面板出现
    expect(find.text('💡 想法'), findsOneWidget);
  });

  testWidgets('filterType 只显示指定类型', (tester) async {
    final events = _makeEvents();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EventTreeView(
            events: events,
            filterType: EventType.lesson,
          ),
        ),
      ),
    );
    await tester.pump();

    // 只显示教训类型
    expect(find.textContaining('教训'), findsOneWidget);
    // 想法类型不可见
    expect(find.textContaining('💡 想法'), findsNothing);

    // 展开日期节点
    final todayNodes = find.text('今天');
    if (todayNodes.evaluate().isNotEmpty) {
      await tester.tap(todayNodes.first);
      await tester.pump();
    }

    // 教训事件可见
    expect(find.text('保护上午时间'), findsOneWidget);
  });
}
