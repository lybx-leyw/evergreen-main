import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/core/palace/models/consciousness_event.dart';
import 'package:evergreen_multi_tools/features/palace/widgets/event_card.dart';

void main() {
  testWidgets('EventCard 渲染标题 + 情绪 emoji', (tester) async {
    final event = ConsciousnessEvent.create(
      type: EventType.thought,
      source: SourceTool.manual,
      rawContent: '关于深度工作的重要发现',
      emotionalValence: 0.8,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: EventCard(event: event)),
      ),
    );

    // 标题渲染
    expect(find.text(event.title), findsOneWidget);
    // 正面情绪
    expect(find.text('😄'), findsOneWidget);
    // 无 AI 标记（没有摘要）
    expect(find.byIcon(Icons.auto_awesome), findsNothing);
  });

  testWidgets('EventCard 有 AI 摘要 → 显示标记', (tester) async {
    final event = ConsciousnessEvent.create(
      type: EventType.lesson,
      source: SourceTool.agent,
      rawContent: '教训内容',
      aiSummary: 'AI 认为用户学到了重要经验',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: EventCard(event: event)),
      ),
    );

    expect(find.text(event.title), findsOneWidget);
    expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
  });

  testWidgets('EventCard 选中态 → 高亮', (tester) async {
    final event = ConsciousnessEvent.create(
      type: EventType.reflection,
      source: SourceTool.manual,
      rawContent: '反思内容',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EventCard(
            event: event,
            isSelected: true,
          ),
        ),
      ),
    );

    final card = tester.widget<Card>(find.byType(Card));
    // isSelected 用 primaryContainer 高亮
    expect(card.color, isNotNull);
  });

  testWidgets('EventCard onTap 回调触发', (tester) async {
    final event = ConsciousnessEvent.create(
      type: EventType.thought,
      source: SourceTool.manual,
      rawContent: '测试',
    );

    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EventCard(
            event: event,
            onTap: () => tapped = true,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(InkWell));
    expect(tapped, isTrue);
  });
}
