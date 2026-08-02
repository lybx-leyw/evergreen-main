/// 培养方案页 / 成绩页 的 SliverList->SliverToBoxAdapter 修复回归测试。
///
/// 与 course_offerings 同源拆分的副本，同样曾把 Padding/Card 等 box 控件直接塞进
/// `SliverList.list` 导致 layout 崩溃。本测试用假 orchestrator 灌入非空数据，
/// 渲染对应页面并断言不抛异常（此前会 Duplicate GlobalKey / 'attached' 级联崩溃）。
library;

import 'package:evergreen_base/core/data/orchestrator.dart';
import 'package:evergreen_base/core/data/type.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/providers.dart';
import 'package:evergreen_base/renderer/templates/zju_modle/zdbk/screens/grades_page.dart';
import 'package:evergreen_base/renderer/templates/zju_modle/zdbk/screens/training_plans_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeOrch extends DataOrchestrator {
  _FakeOrch(this._data);
  final Map<String, dynamic> _data;

  @override
  DataType? typeByName(String name) =>
      DataType<dynamic>(name: name, category: '', persistentKey: 'fake-$name');

  @override
  Future<T?> get<T>(DataType<T> type) async => _data[type.name] as T?;

  @override
  Future<T?> refresh<T>(DataType<T> type) async => _data[type.name] as T?;

  @override
  Future<T?> fastRead<T>(DataType<T> type) async => _data[type.name] as T?;
}

DataSourceDescriptor _src(String name) =>
    DataSourceDescriptor(endpoint: 'orch://$name');

void main() {
  testWidgets('培养方案页：非空数据可渲染（SliverList->SliverToBoxAdapter 修复）',
      (tester) async {
    final orch = _FakeOrch({
      'zdbk_training_plans': {
        'items': [
          {
            'zymc': '计算机科学',
            'xymc': '计算机学院',
            'synj': '2023',
            'xz': '4',
            'zdbyxf': '150',
          },
        ],
      },
    });
    final sources = {'training_plans': _src('zdbk_training_plans')};
    await tester.pumpWidget(ProviderScope(
      overrides: [dataOrchestratorProvider.overrideWithValue(orch)],
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(
            builder: (ctx, ref, _) =>
                TrainingPlanPage(ref: ref, sources: sources),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    // 数据解析并渲染出方案名（此前 SliverList 内嵌 box 控件会崩溃）。
    expect(find.text('计算机科学'), findsWidgets);
  });

  testWidgets('成绩页：成绩单 + 二三课堂均渲染（SliverList->SliverToBoxAdapter 修复）',
      (tester) async {
    final orch = _FakeOrch({
      'zdbk_transcript': {
        'items': [
          {'kcmc': '高等数学', 'cj': '90', 'jd': '4.0', 'xf': '5'},
        ],
      },
      'zdbk_major_grade': {
        'items': [
          {'kcmc': '线性代数', 'cj': '88', 'jd': '3.8', 'xf': '4'},
        ],
      },
      'zdbk_practice_scores': {
        'pt2': '2.0',
        'pt3': '3.0',
        'pt4': '4.0',
      },
    });
    final sources = {
      'transcript': _src('zdbk_transcript'),
      'major_grade': _src('zdbk_major_grade'),
      'practice_scores': _src('zdbk_practice_scores'),
    };
    await tester.pumpWidget(ProviderScope(
      overrides: [dataOrchestratorProvider.overrideWithValue(orch)],
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(
            builder: (ctx, ref, _) => GradesPage(ref: ref, sources: sources),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    // 成绩单卡片渲染出课程名（此前 SliverList 内嵌 box 控件会崩溃）。
    // 成绩卡片位于滚动视图下方（off-stage），断言需 skipOffstage。
    expect(find.text('高等数学', skipOffstage: false), findsOneWidget);
    // 主修成绩课程名也渲染。
    expect(find.text('线性代数', skipOffstage: false), findsOneWidget);
    // GPA 汇总卡已渲染（新 Dashboard）。
    expect(find.text('五分制'), findsWidgets);
    // 区块标题带计数，形如 “二 / 三 / 四课堂成绩 (3)”。
    expect(find.textContaining('二 / 三 / 四课堂成绩'), findsOneWidget);
  });

  testWidgets('成绩页：搜索过滤 + 策略切换生效（Dashboard 优化）',
      (tester) async {
    final orch = _FakeOrch({
      'zdbk_transcript': {
        'items': [
          {'kcmc': '高等数学', 'cj': '95', 'jd': '4.5', 'xf': '5',
           'xkkh': '(2023-2024-1)-MATH101-01'},
          {'kcmc': '线性代数', 'cj': '88', 'jd': '3.8', 'xf': '4',
           'xkkh': '(2023-2024-1)-MATH102-01'},
          {'kcmc': '大学物理', 'cj': '70', 'jd': '2.0', 'xf': '3',
           'xkkh': '(2023-2024-2)-PHYS101-01'},
        ],
      },
      'zdbk_major_grade': {'items': []},
      'zdbk_practice_scores': {'pt2': '0', 'pt3': '0', 'pt4': '0'},
    });
    final sources = {
      'transcript': _src('zdbk_transcript'),
      'major_grade': _src('zdbk_major_grade'),
      'practice_scores': _src('zdbk_practice_scores'),
    };
    await tester.pumpWidget(ProviderScope(
      overrides: [dataOrchestratorProvider.overrideWithValue(orch)],
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(
            builder: (ctx, ref, _) => GradesPage(ref: ref, sources: sources),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // 默认显示全部 3 门（成绩卡片位于滚动视图下方，需 skipOffstage）。
    expect(find.text('高等数学', skipOffstage: false), findsOneWidget);
    expect(find.text('大学物理', skipOffstage: false), findsOneWidget);

    // 搜索 “物理” → 仅剩 “大学物理”。
    await tester.enterText(find.byType(TextField), '物理');
    await tester.pumpAndSettle();
    expect(find.text('高等数学', skipOffstage: false), findsNothing);
    expect(find.text('大学物理', skipOffstage: false), findsOneWidget);

    // 清空搜索。
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    expect(find.text('高等数学', skipOffstage: false), findsOneWidget);
  });

  testWidgets('成绩页：绩点升降序切换生效', (tester) async {
    final orch = _FakeOrch({
      'zdbk_transcript': {
        'items': [
          {'kcmc': '高等数学', 'cj': '95', 'jd': '4.5', 'xf': '5',
           'xkkh': '(2023-2024-1)-MATH101-01'},
          {'kcmc': '线性代数', 'cj': '88', 'jd': '3.8', 'xf': '4',
           'xkkh': '(2023-2024-1)-MATH102-01'},
          {'kcmc': '大学物理', 'cj': '70', 'jd': '2.0', 'xf': '3',
           'xkkh': '(2023-2024-2)-PHYS101-01'},
        ],
      },
      'zdbk_major_grade': {'items': []},
      'zdbk_practice_scores': {'pt2': '0', 'pt3': '0', 'pt4': '0'},
    });
    final sources = {
      'transcript': _src('zdbk_transcript'),
      'major_grade': _src('zdbk_major_grade'),
      'practice_scores': _src('zdbk_practice_scores'),
    };
    await tester.pumpWidget(ProviderScope(
      overrides: [dataOrchestratorProvider.overrideWithValue(orch)],
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(
            builder: (ctx, ref, _) => GradesPage(ref: ref, sources: sources),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    double yOf(String t) =>
        tester.getTopLeft(find.text(t, skipOffstage: false)).dy;

    // 默认降序：绩点最高的「高等数学」在最上方。
    expect(yOf('高等数学'), lessThan(yOf('大学物理')));

    // 点击升降序切换（默认 tooltip 为「绩点降序」）。
    await tester.tap(find.byTooltip('绩点降序'));
    await tester.pumpAndSettle();

    // 切换后升序：绩点最低的「大学物理」移到最上方。
    expect(yOf('大学物理'), lessThan(yOf('高等数学')));
  });
}
