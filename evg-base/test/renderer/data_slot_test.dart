/// M2 P2 组件级注入 widget 测试。
/// - 批次 1：stat-tile / chart / card-list / timeline / kanban / tree
/// - 批次 2：map / calendar / timetable / data-table
///
/// 验证：
/// - 无 dataSource → 静态 config 渲染；
/// - dataSource(endpoint:'orch://<type>') → 经 DataOrchestrator 拉取并合并进对应 config 字段；
/// - 拉取失败（未注册类型）→ 优雅降级为静态 config，不崩。
///
/// 运行：cd evg-base && flutter test test/renderer/data_slot_test.dart
import 'package:evergreen_base/renderer/components/data/card_list_slot.dart';
import 'package:evergreen_base/renderer/components/data/chart_slot.dart';
import 'package:evergreen_base/renderer/components/data/kanban_slot.dart';
import 'package:evergreen_base/renderer/components/data/stat_tile_slot.dart';
import 'package:evergreen_base/renderer/components/data/timeline_slot.dart';
import 'package:evergreen_base/renderer/components/data/tree_slot.dart';
import 'package:evergreen_base/renderer/components/data/map_slot.dart';
import 'package:evergreen_base/renderer/components/data/calendar_slot.dart';
import 'package:evergreen_base/renderer/components/data/timetable_slot.dart';
import 'package:evergreen_base/renderer/components/data/data_table_slot.dart';
import 'package:evergreen_base/renderer/components/shared/widgets/calendar_widget.dart';
import 'package:evergreen_base/renderer/slot/slot_widgets.dart';
import 'package:evergreen_base/core/data/data.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 构造一个带注册类型的假 DataOrchestrator。
DataOrchestrator _fakeOrch(Map<String, dynamic> types) {
  final orch = DataOrchestrator();
  types.forEach((name, data) {
    orch.register(
      DataType<dynamic>(name: name),
      () async => data,
    );
  });
  return orch;
}

/// 包一层 ProviderScope，注入假 orchestrator。
Widget _scope(Widget child, DataOrchestrator orch) => ProviderScope(
      overrides: [dataOrchestratorProvider.overrideWith((ref) => orch)],
      child: MaterialApp(home: Scaffold(body: child)),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('stat-tile 注入', () {
    testWidgets('无 dataSource → 静态 value 渲染', (tester) async {
      final slot = StatTileSlot(
        config: ComponentDescriptor(
          type: 'stat-tile',
          config: {'title': 'T', 'value': '7'},
        ),
      );
      await tester.pumpWidget(_scope(slot, _fakeOrch({})));
      await tester.pumpAndSettle();
      expect(find.text('7'), findsWidgets);
    });

    testWidgets('orch:// 注入 → 合并 value/subtitle', (tester) async {
      final orch = _fakeOrch({
        'statMetric': {'value': '42', 'subtitle': '注入成功'},
      });
      final slot = StatTileSlot(
        config: ComponentDescriptor(
          type: 'stat-tile',
          config: {'title': 'T'},
          dataSource: const DataSourceDescriptor(endpoint: 'orch://statMetric'),
        ),
      );
      await tester.pumpWidget(_scope(slot, orch));
      await tester.pumpAndSettle();
      expect(find.text('42'), findsWidgets);
      expect(find.text('注入成功'), findsWidgets);
    });
  });

  group('自动刷新（refreshInterval）', () {
    testWidgets('到点经 forceRefresh 重新拉取并刷新 UI（非命中缓存）',
        (tester) async {
      int calls = 0;
      final orch = DataOrchestrator();
      orch.register(
        DataType<dynamic>(name: 'statMetric'),
        () async {
          calls++;
          return {
            'value': calls == 1 ? 'v1' : 'REFRESHED',
            'subtitle': 'x',
          };
        },
      );
      final slot = StatTileSlot(
        config: ComponentDescriptor(
          type: 'stat-tile',
          dataSource: const DataSourceDescriptor(
            endpoint: 'orch://statMetric',
            refreshInterval: 2,
          ),
        ),
      );
      await tester.pumpWidget(_scope(slot, orch));
      await tester.pump(const Duration(milliseconds: 500)); // 首次拉取（<2s，不触发刷新）
      expect(find.text('v1'), findsWidgets);

      // 推进到 2s 之后：Timer 触发 → resolveDataSource(forceRefresh:true)
      // → orch.refresh 绕过缓存重抓，UI 应显示新值。
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 500)); // 让刷新 future 完成并重建
      expect(find.text('REFRESHED'), findsWidgets);
      expect(find.text('v1'), findsNothing);
      expect(calls, greaterThan(1)); // 证明发生了二次拉取（否则缓存命中 calls==1）
    });
  });

  group('card-list 注入', () {
    testWidgets('orch:// 注入 → 渲染注入卡片标题', (tester) async {
      final orch = _fakeOrch({
        'cards': [
          {'title': '注入卡片A', 'body': 'b'},
          {'title': '注入卡片B', 'body': 'b'},
        ],
      });
      final slot = CardListSlot(
        config: ComponentDescriptor(
          type: 'card-list',
          dataSource: const DataSourceDescriptor(endpoint: 'orch://cards'),
        ),
      );
      await tester.pumpWidget(_scope(slot, orch));
      await tester.pumpAndSettle();
      expect(find.text('注入卡片A'), findsWidgets);
      expect(find.text('注入卡片B'), findsWidgets);
    });
  });

  group('timeline 注入', () {
    testWidgets('orch:// 注入 → 渲染注入事件', (tester) async {
      final orch = _fakeOrch({
        'events': [
          {'label': '注入事件1', 'time': '09:00'},
          {'label': '注入事件2', 'time': '10:00'},
        ],
      });
      final slot = TimelineSlot(
        config: ComponentDescriptor(
          type: 'timeline',
          dataSource: const DataSourceDescriptor(endpoint: 'orch://events'),
        ),
      );
      await tester.pumpWidget(_scope(slot, orch));
      await tester.pumpAndSettle();
      expect(find.text('注入事件1'), findsWidgets);
      expect(find.text('注入事件2'), findsWidgets);
    });
  });

  group('kanban 注入', () {
    testWidgets('orch:// 注入 → 渲染注入列', (tester) async {
      final orch = _fakeOrch({
        'board': [
          {
            'title': '注入列1',
            'items': [
              {'title': '任务A'}
            ]
          }
        ],
      });
      final slot = KanbanSlot(
        config: ComponentDescriptor(
          type: 'kanban',
          dataSource: const DataSourceDescriptor(endpoint: 'orch://board'),
        ),
      );
      await tester.pumpWidget(_scope(slot, orch));
      await tester.pumpAndSettle();
      expect(find.text('注入列1'), findsWidgets);
      expect(find.text('任务A'), findsWidgets);
    });
  });

  group('tree 注入', () {
    testWidgets('orch:// 注入 → 渲染注入根节点', (tester) async {
      final orch = _fakeOrch({
        'tree': {
          'label': '注入根',
          'children': [
            {'label': '注入子'}
          ]
        },
      });
      final slot = TreeSlot(
        config: ComponentDescriptor(
          type: 'tree',
          dataSource: const DataSourceDescriptor(endpoint: 'orch://tree'),
        ),
      );
      await tester.pumpWidget(_scope(slot, orch));
      await tester.pumpAndSettle();
      expect(find.text('注入根'), findsWidgets);
      expect(find.text('注入子'), findsWidgets);
    });
  });

  group('chart 注入', () {
    testWidgets('orch:// 注入 → 渲染注入维度标签', (tester) async {
      final orch = _fakeOrch({
        'series': [
          {'label': '注入维度', 'value': 9}
        ],
      });
      final slot = ChartSlot(
        config: ComponentDescriptor(
          type: 'chart',
          dataSource: const DataSourceDescriptor(endpoint: 'orch://series'),
        ),
      );
      await tester.pumpWidget(_scope(slot, orch));
      await tester.pumpAndSettle();
      expect(find.text('注入维度'), findsWidgets);
    });
  });

  // ═══════════ 批次 2：map / calendar / timetable / data-table ═══════════

  group('map 注入', () {
    testWidgets('无 dataSource → 静态中心点渲染', (tester) async {
      final slot = MapSlot(
        config: ComponentDescriptor(
          type: 'map',
          config: {
            'center': {'lat': 5.0, 'lng': 6.0},
          },
        ),
      );
      await tester.pumpWidget(_scope(slot, _fakeOrch({})));
      await tester.pumpAndSettle();
      expect(find.textContaining('5.0'), findsWidgets);
    });

    testWidgets('orch:// 注入 → 合并中心点', (tester) async {
      final orch = _fakeOrch({
        'geo': {
          'center': {'lat': 1.0, 'lng': 2.0},
          'markers': true,
        },
      });
      final slot = MapSlot(
        config: ComponentDescriptor(
          type: 'map',
          dataSource: const DataSourceDescriptor(endpoint: 'orch://geo'),
        ),
      );
      await tester.pumpWidget(_scope(slot, orch));
      await tester.pumpAndSettle();
      expect(find.textContaining('1.0'), findsWidgets);
    });
  });

  group('calendar 注入', () {
    testWidgets('orch:// 注入 → CalendarWidget 收到注入事件', (tester) async {
      final orch = _fakeOrch({
        'schedule': {
          'events': [
            {'date': '2026-07-15', 'title': '注入会议'},
            {'date': '2026-07-20', 'title': '注入答辩', 'color': '#FF0000'},
          ],
        },
      });
      final slot = CalendarSlot(
        config: ComponentDescriptor(
          type: 'calendar',
          dataSource: const DataSourceDescriptor(endpoint: 'orch://schedule'),
        ),
      );
      await tester.pumpWidget(_scope(slot, orch));
      await tester.pumpAndSettle();
      final cal = tester.widget<CalendarWidget>(find.byType(CalendarWidget));
      expect(cal.events.length, 2);
      expect(cal.events.first.title, '注入会议');
    });
  });

  group('timetable 注入', () {
    testWidgets('orch:// 注入 → 渲染注入课程名', (tester) async {
      final orch = _fakeOrch({
        'courses': {
          'sessions': [
            {
              'courseName': '注入课',
              'periods': [1, 2],
              'dayOfWeek': 1,
            }
          ],
        },
      });
      final slot = TimetableSlot(
        config: ComponentDescriptor(
          type: 'timetable',
          dataSource: const DataSourceDescriptor(endpoint: 'orch://courses'),
        ),
      );
      await tester.pumpWidget(_scope(slot, orch));
      await tester.pumpAndSettle();
      expect(find.text('注入课'), findsWidgets);
    });
  });

  group('data-table 注入', () {
    testWidgets('orch:// 注入 → 渲染注入行单元格', (tester) async {
      final orch = _fakeOrch({
        'rows': [
          {'name': '注入行'},
        ],
      });
      final slot = DataTableSlot(
        config: ComponentDescriptor(
          type: 'data-table',
          config: {
            'columns': [
              {'title': '名称', 'key': 'name', 'editable': false},
            ],
          },
          dataSource: const DataSourceDescriptor(endpoint: 'orch://rows'),
        ),
      );
      await tester.pumpWidget(_scope(slot, orch));
      await tester.pumpAndSettle();
      expect(find.text('注入行'), findsWidgets);
    });
  });

  // ═══════════ 批次 3：flashcards / quiz（内联 slot_widgets.dart） ═══════════

  group('flashcards 注入', () {
    testWidgets('orch:// 注入 → 渲染注入词卡释义', (tester) async {
      final orch = _fakeOrch({
        'vocab': [
          {'word': 'injectWord', 'meaning': '注入释义卡'},
        ],
      });
      final slot = FlashcardsSlot(
        slotKey: 'fc1',
        moduleId: 'm',
        config: ComponentDescriptor(
          type: 'flashcards',
          dataSource: const DataSourceDescriptor(endpoint: 'orch://vocab'),
        ),
      );
      await tester.pumpWidget(_scope(slot, orch));
      await tester.pumpAndSettle();
      // 卡片正面显示释义，背面显示单词；注入后释义应出现在 Widget 树。
      expect(find.text('注入释义卡'), findsWidgets);
    });

    testWidgets('无 dataSource → 回退本地文件加载（空词库占位）', (tester) async {
      final slot = FlashcardsSlot(
        slotKey: 'fc2',
        moduleId: 'm',
        config: ComponentDescriptor(
          type: 'flashcards',
          config: {'wordList': 'nonexistent.json'},
        ),
      );
      await tester.pumpWidget(_scope(slot, _fakeOrch({})));
      await tester.pumpAndSettle();
      // 文件不存在 → 词库为空 → 显示加载占位，不崩。
      expect(find.text('加载词库中...'), findsWidgets);
    });
  });

  group('quiz 注入', () {
    testWidgets('orch:// 注入 → 渲染注入词数（开始视图）', (tester) async {
      final orch = _fakeOrch({
        'quizData': [
          {'word': 'injectQ', 'meaning': '注入测验题'},
        ],
      });
      final slot = QuizSlot(
        slotKey: 'qz1',
        moduleId: 'm',
        config: ComponentDescriptor(
          type: 'quiz',
          dataSource: const DataSourceDescriptor(endpoint: 'orch://quizData'),
        ),
      );
      await tester.pumpWidget(_scope(slot, orch));
      await tester.pumpAndSettle();
      // 词库非空且未开始 → 显示开始视图标题。
      expect(find.text('综合测验'), findsWidgets);
    });

    testWidgets('无 dataSource → 回退本地文件加载（空态不崩）', (tester) async {
      final slot = QuizSlot(
        slotKey: 'qz2',
        moduleId: 'm',
        config: ComponentDescriptor(
          type: 'quiz',
          config: {'wordList': 'nonexistent.json'},
        ),
      );
      await tester.pumpWidget(_scope(slot, _fakeOrch({})));
      await tester.pumpAndSettle();
      expect(find.textContaining('词库为空'), findsWidgets);
    });
  });

  group('优雅降级', () {
    testWidgets('未注册类型 → 回退静态 config，不崩', (tester) async {
      final slot = StatTileSlot(
        config: ComponentDescriptor(
          type: 'stat-tile',
          config: {'title': 'T', 'value': 'STATIC'},
          dataSource:
              const DataSourceDescriptor(endpoint: 'orch://notRegistered'),
        ),
      );
      await tester.pumpWidget(_scope(slot, _fakeOrch({})));
      await tester.pumpAndSettle();
      expect(find.text('STATIC'), findsWidgets);
    });
  });
}
