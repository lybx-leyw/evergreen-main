import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:evergreen_multi_tools/core/result.dart';
import 'package:evergreen_multi_tools/core/models/training_plan.dart';
import 'package:evergreen_multi_tools/features/zdbk/screens/training_plan_screen.dart';
import 'package:evergreen_multi_tools/features/zdbk/providers/zdbk_provider.dart';
import 'package:evergreen_multi_tools/features/zdbk/services/zdbk_service.dart';

Widget _wrap(Widget child, {List<TrainingPlan>? plans}) {
  return ProviderScope(
    overrides: [
      trainingPlansProvider(0).overrideWith(
        (ref) async => Ok(plans ?? <TrainingPlan>[]),
      ),
    ],
    child: MaterialApp(home: child),
  );
}

/// 包装 TrainingPlanScreen，允许控制 zdbkServiceInstanceProvider 的行为。
/// [serviceFuture] 决定 downloadPlanPdf 调用时 `await service.downloadPlanPdf(...)` 的结果。
Widget _wrapWithServiceFuture({
  List<TrainingPlan>? plans,
  required Future<ZdbkService> Function() serviceFuture,
}) {
  return ProviderScope(
    overrides: [
      trainingPlansProvider(0).overrideWith(
        (ref) async => Ok(plans ?? <TrainingPlan>[]),
      ),
      zdbkServiceInstanceProvider.overrideWith(
        (ref) => serviceFuture(),
      ),
    ],
    child: const MaterialApp(home: TrainingPlanScreen()),
  );
}

/// 构造测试用的培养方案模型。
TrainingPlan _makePlan({
  String planNo = 'PYFA-2024-001',
  String planName = '计算机科学与技术培养方案',
  String major = '计算机科学与技术',
  String college = '计算机学院',
  String grade = '2024',
  String level = '本科',
  double minCredits = 160.0,
  String? remarks,
}) {
  return TrainingPlan(
    planNo: planNo,
    planName: planName,
    major: major,
    college: college,
    grade: grade,
    level: level,
    minCredits: minCredits,
    remarks: remarks,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('无缓存时显示空状态和刷新按钮', (tester) async {
    await tester.pumpWidget(_wrap(const TrainingPlanScreen()));
    await tester.pumpAndSettle();

    expect(find.text('暂无培养方案数据'), findsOneWidget);
    expect(find.text('点击刷新'), findsOneWidget);
    // 有两个刷新图标：AppBar 和空状态按钮
    expect(find.byIcon(Icons.refresh), findsNWidgets(2));
  });

  testWidgets('AppBar 标题正确', (tester) async {
    await tester.pumpWidget(_wrap(const TrainingPlanScreen()));
    await tester.pumpAndSettle();

    expect(find.text('培养方案'), findsOneWidget);
  });

  testWidgets('方案卡片显示方案名称和查看按钮', (tester) async {
    final plan = _makePlan();
    await tester.pumpWidget(_wrap(
      const TrainingPlanScreen(),
      plans: [plan],
    ));
    await tester.pumpAndSettle();

    // 方案名称可见
    expect(find.text(plan.planName), findsOneWidget);
    // 查看按钮（open_in_new 图标）
    expect(find.byIcon(Icons.open_in_new), findsOneWidget);
    // 专业、学院、年级、学位信息
    expect(find.text(plan.major!), findsOneWidget);
    expect(find.text(plan.college!), findsOneWidget);
    expect(find.text('${plan.grade}级'), findsOneWidget);
    expect(find.text(plan.level!), findsOneWidget);
  });

  testWidgets('方案无 planNo 时不显示查看按钮', (tester) async {
    final plan = _makePlan(planNo: '');
    await tester.pumpWidget(_wrap(
      const TrainingPlanScreen(),
      plans: [plan],
    ));
    await tester.pumpAndSettle();

    // 方案名称仍可见
    expect(find.text(plan.planName), findsOneWidget);
    // 但不应该有查看按钮
    expect(find.byIcon(Icons.open_in_new), findsNothing);
  });

  testWidgets('多个方案正常渲染', (tester) async {
    final plans = [
      _makePlan(planNo: 'PYFA-001', planName: '方案A'),
      _makePlan(planNo: 'PYFA-002', planName: '方案B'),
      _makePlan(planNo: '', planName: '方案C(无文档)'),
    ];
    await tester.pumpWidget(_wrap(
      const TrainingPlanScreen(),
      plans: plans,
    ));
    await tester.pumpAndSettle();

    expect(find.text('方案A'), findsOneWidget);
    expect(find.text('方案B'), findsOneWidget);
    expect(find.text('方案C(无文档)'), findsOneWidget);
    // 方案A 和 B 有查看按钮，方案C 没有 → 共 2 个
    expect(find.byIcon(Icons.open_in_new), findsNWidgets(2));
  });

  group('下载流程', () {
    late TrainingPlan plan;

    setUp(() {
      plan = _makePlan();
    });

    testWidgets('下载失败显示 snackbar 且 loading 关闭（_fail + addPostFrameCallback）', (tester) async {
      await tester.pumpWidget(_wrapWithServiceFuture(
        plans: [plan],
        // service 获取时抛错 → 进入 _downloadAndOpenPlan 的 catch 块
        serviceFuture: () => Future<ZdbkService>.error(
          Exception('模拟网络错误'),
        ),
      ));
      await tester.pumpAndSettle();

      // 点击查看按钮
      await tester.tap(find.byIcon(Icons.open_in_new));
      await tester.pump(); // showDialog + try 块启动
      await tester.pump(const Duration(milliseconds: 100)); // await 恢复 + addPostFrameCallback 注册

      // 下一个帧执行 addPostFrameCallback → pop()
      await tester.pump();

      // loading 对话框应已关闭
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // 错误 snackbar 应显示
      expect(find.byType(SnackBar), findsOneWidget);
    });
  });
}
