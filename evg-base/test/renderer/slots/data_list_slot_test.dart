/// DataListSlot 单元测试。
///
/// 验证：
/// 1. 静态渲染（无 dataSource）— 渲染配置中的 items
/// 2. 搜索过滤 — 关键字过滤正确
/// 3. 尾部操作按钮 — 4 种 action 类型渲染
/// 4. 空态渲染
/// 5. 分隔线配置
/// 6. PageEventBus 事件分发
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/core/module/page_event_bus.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/data/data_list_slot.dart';

void main() {
  // ─── 辅助：构造 ComponentDescriptor ───
  ComponentDescriptor _desc(Map<String, dynamic> config) {
    return ComponentDescriptor(
      type: 'data-list',
      config: config,
    );
  }

  // ─── 测试 1：静态渲染 — 有 items 时显示 ListTile ───
  testWidgets('静态渲染 — 渲染 items 列表', (tester) async {
    final desc = _desc({
      'title': '测试列表',
      'items': [
        {'name': '课程A', 'teacherName': '张老师', 'type': '必修'},
        {'name': '课程B', 'teacherName': '李老师', 'type': '选修'},
      ],
      'item': {
        'titleField': 'name',
        'subtitle': {
          'fields': ['teacherName', 'type'],
          'separator': ' · ',
        },
      },
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DataListSlot(config: desc)),
    ));
    await tester.pump();

    // 标题可见
    expect(find.text('测试列表'), findsOneWidget);
    // 两个课程条目可见
    expect(find.text('课程A'), findsOneWidget);
    expect(find.text('课程B'), findsOneWidget);
    // subtitle 拼接
    expect(find.textContaining('张老师'), findsOneWidget);
    expect(find.textContaining('李老师'), findsOneWidget);
  });

  // ─── 测试 2：搜索过滤 ───
  testWidgets('搜索过滤 — 按 titleField 过滤', (tester) async {
    final desc = _desc({
      'searchable': true,
      'searchPlaceholder': '搜索课程...',
      'items': [
        {'name': '微积分', 'teacher': '王老师'},
        {'name': '线性代数', 'teacher': '赵老师'},
        {'name': '大学物理', 'teacher': '钱老师'},
      ],
      'item': {'titleField': 'name'},
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DataListSlot(config: desc)),
    ));
    await tester.pump();

    // 初始 3 条全显示
    expect(find.text('微积分'), findsOneWidget);
    expect(find.text('线性代数'), findsOneWidget);
    expect(find.text('大学物理'), findsOneWidget);

    // 输入 "微积" → 应该只剩 1 条
    await tester.enterText(find.byType(TextField), '微积');
    await tester.pump();

    expect(find.text('微积分'), findsOneWidget);
    expect(find.text('线性代数'), findsNothing);
    expect(find.text('大学物理'), findsNothing);

    // 清空搜索
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    expect(find.text('微积分'), findsOneWidget);
    expect(find.text('线性代数'), findsOneWidget);
    expect(find.text('大学物理'), findsOneWidget);
  });

  // ─── 测试 3：尾部操作按钮 — 4 种 action 类型 ───
  testWidgets('尾部操作按钮 — 4 种 action 类型渲染', (tester) async {
    final desc = _desc({
      'items': [
        {'name': '课程A'},
      ],
      'item': {
        'titleField': 'name',
        'trailingActions': [
          {'icon': 'person_search', 'tooltip': '查老师', 'action': 'navigate', 'target': '/teachers'},
          {'icon': 'download', 'tooltip': '下载', 'action': 'link', 'target': 'https://example.com'},
          {'icon': 'search', 'tooltip': '搜索页', 'action': 'switch_page', 'target': 'page_5'},
          {'icon': 'star', 'tooltip': '收藏', 'action': 'custom', 'target': 'favorite'},
        ],
      },
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DataListSlot(config: desc)),
    ));
    await tester.pump();

    // 4 个按钮 + 1 个搜索清除按钮(搜索栏无 → 不渲染) → 应该有 4 个 IconButton
    expect(find.byType(IconButton), findsNWidgets(4));
    // tooltip 文本存在
    expect(find.byTooltip('查老师'), findsOneWidget);
    expect(find.byTooltip('下载'), findsOneWidget);
    expect(find.byTooltip('搜索页'), findsOneWidget);
    expect(find.byTooltip('收藏'), findsOneWidget);
  });

  // ─── 测试 4：PageEventBus 事件分发 ───
  testWidgets('PageEventBus — 点击按钮发出正确事件', (tester) async {
    final bus = PageEventBus(pageId: 'test_page');
    final events = <String>[];
    bus.all.listen((e) => events.add(e.event));

    final desc = _desc({
      'items': [
        {'name': '课程A'},
      ],
      'item': {
        'titleField': 'name',
        'trailingActions': [
          {'icon': 'info', 'tooltip': '详情', 'action': 'navigate', 'target': '/detail'},
          {'icon': 'search', 'tooltip': '切页', 'action': 'switch_page', 'target': 'page_2'},
          {'icon': 'star', 'tooltip': '收藏', 'action': 'custom', 'target': 'favorite_event'},
        ],
      },
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DataListSlot(config: desc, pageEventBus: bus)),
    ));
    await tester.pump();

    // 点击 navigate 按钮
    await tester.tap(find.byTooltip('详情'));
    await tester.pump();
    expect(events, contains('slot:navigate:/detail'));

    // 点击 switch_page 按钮
    await tester.tap(find.byTooltip('切页'));
    await tester.pump();
    expect(events, contains('slot:switch_page:page_2'));

    // 点击 custom 按钮
    await tester.tap(find.byTooltip('收藏'));
    await tester.pump();
    expect(events, contains('slot:data_action:favorite_event'));
  });

  // ─── 测试 5：空态 — items 为空 ───
  testWidgets('空态 — 无数据时显示空态提示', (tester) async {
    final desc = _desc({
      'title': '空列表',
      'items': <Map<String, dynamic>>[],
      'item': {'titleField': 'name'},
      'emptyState': {
        'icon': 'inbox',
        'message': '暂无课程',
      },
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DataListSlot(config: desc)),
    ));
    await tester.pump();

    expect(find.text('暂无课程'), findsOneWidget);
  });

  // ─── 测试 6：分隔线配置 ───
  testWidgets('分隔线 — 配置 type:none 不渲染分隔线', (tester) async {
    final desc = _desc({
      'items': [
        {'name': 'A'},
        {'name': 'B'},
        {'name': 'C'},
      ],
      'item': {'titleField': 'name'},
      'separator': {'type': 'none'},
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DataListSlot(config: desc)),
    ));
    await tester.pump();

    // type: 'none' → 应该没有 Divider
    expect(find.byType(Divider), findsNothing);
  });
}
