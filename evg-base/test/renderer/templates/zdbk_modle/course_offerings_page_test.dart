/// 开课情况页崩溃回归测试。
///
/// 复现用户报告：一在搜索框输入就崩溃（Duplicate GlobalKey / 'attached' /
/// 'child == _child' 级联 + Lost connection）。根因是 `SliverList.list` 的孩子
/// 必须是 sliver，而原代码把 Padding/Card/TextField 这类 box 控件直接塞进了
/// `SliverList`，layout 时崩溃；修复后改用 `SliverToBoxAdapter(child: Column(...))`。
///
/// 本测试用假 orchestrator 灌入非空开课数据，渲染后模拟搜索，断言不抛异常且过滤正确。
library;

import 'package:evergreen_base/core/data/orchestrator.dart';
import 'package:evergreen_base/core/data/type.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/providers.dart';
import 'package:evergreen_base/renderer/templates/zju_modle/zdbk/screens/course_offerings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 最小假数据谱仪器：按名称返回预置数据，绕过真实注册/缓存/CLI。
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
}

/// 提供真实 WidgetRef 以构造 CourseOfferingsPage。
class _Harness extends ConsumerWidget {
  const _Harness(this.sources);
  final Map<String, DataSourceDescriptor> sources;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      CourseOfferingsPage(ref: ref, sources: sources);
}

const _sources = {
  'course_offerings': DataSourceDescriptor(
    endpoint: 'orch://zdbk_course_offerings',
  ),
};

Map<String, dynamic> get _offeringsPayload => {
      'zdbk_course_offerings': {
        'items': [
          {
            'kcmc': '数据结构',
            'jsxm': '张三',
            'skdd': '东1-201',
            'sksj': '周一1-2节',
            'xf': '3',
            'kclb': '必修课',
            'kkxy': '计算机学院',
            'zymc': '计算机科学',
          },
          {
            'kcmc': '操作系统',
            'jsxm': '李四',
            'skdd': '东2-301',
            'sksj': '周三3-4节',
            'xf': '4',
            'kclb': '必修课',
            'kkxy': '计算机学院',
            'zymc': '计算机科学',
          },
        ],
      },
    };

void main() {
  testWidgets('开课情况：非空数据 + 搜索不崩溃（SliverList→SliverToBoxAdapter 修复）',
      (tester) async {
    final orch = _FakeOrch(_offeringsPayload);
    await tester.pumpWidget(ProviderScope(
      overrides: [dataOrchestratorProvider.overrideWithValue(orch)],
      child: const MaterialApp(home: Scaffold(body: _Harness(_sources))),
    ));
    await tester.pumpAndSettle();

    // 非空：两门课程卡片都渲染出来（此前 SliverList 内嵌 box 控件会在 layout 时崩溃）。
    expect(find.text('数据结构'), findsOneWidget);
    expect(find.text('操作系统'), findsOneWidget);

    // 模拟在搜索框输入 —— 此前会触发级联崩溃。
    await tester.enterText(find.byType(TextField), '操作系统');
    await tester.pumpAndSettle();
    // 仅剩“操作系统”卡片；“数据结构”卡片已被过滤掉（注意 find.text 也会匹配到
    // 搜索框内的输入文字，故用 widgetWithText(Card, ...) 精确匹配卡片标题）。
    expect(find.widgetWithText(Card, '数据结构'), findsNothing);
    expect(find.widgetWithText(Card, '操作系统'), findsOneWidget);
  });

  testWidgets('开课情况：空数据显示空态', (tester) async {
    final orch = _FakeOrch(const {});
    await tester.pumpWidget(ProviderScope(
      overrides: [dataOrchestratorProvider.overrideWithValue(orch)],
      child: const MaterialApp(home: Scaffold(body: _Harness(_sources))),
    ));
    await tester.pumpAndSettle();
    expect(find.text('暂无课程数据'), findsOneWidget);
  });
}
