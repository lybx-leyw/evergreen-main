import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:evergreen_multi_tools/core/result.dart';
import 'package:evergreen_multi_tools/core/errors.dart';
import 'package:evergreen_multi_tools/core/models/training_plan.dart';
import 'package:evergreen_multi_tools/features/zdbk/providers/zdbk_provider.dart';
import 'package:evergreen_multi_tools/features/zdbk/screens/training_plan_screen.dart';

Widget _wrap(Widget child) => MaterialApp(home: child);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('数据加载成功 → 显示列表', (tester) async {
    final mockProvider =
        FutureProvider.family<Result<List<TrainingPlan>>, int>((ref, grade) async {
      return Ok([
        TrainingPlan(
          planNo: '2025-001',
          planName: '计算机科学与技术培养方案',
          major: '计算机科学与技术',
          grade: '2025',
          college: '计算机科学与技术学院',
          level: '本科',
          duration: '4',
          minCredits: 160,
          earnedCredits: 85,
          status: '1',
        ),
        TrainingPlan(
          planNo: '2025-002',
          planName: '数学与应用数学培养方案',
          major: '数学与应用数学',
          grade: '2025',
          college: '数学科学学院',
          level: '本科',
          duration: '4',
          minCredits: 150,
          earnedCredits: 70,
          status: '1',
        ),
      ]);
    });

    await tester.pumpWidget(_wrap(
      ProviderScope(
        overrides: [
          trainingPlansProvider.overrideWithProvider(mockProvider),
        ],
        child: const TrainingPlanScreen(),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('2 个方案'), findsOneWidget);
    expect(find.textContaining('计算机科学与技术培养方案'), findsOneWidget);
    expect(find.textContaining('数学与应用数学培养方案'), findsOneWidget);
  });

  testWidgets('空数据 → 显示空状态', (tester) async {
    final emptyProvider =
        FutureProvider.family<Result<List<TrainingPlan>>, int>((ref, grade) async {
      return Ok(<TrainingPlan>[]);
    });

    await tester.pumpWidget(_wrap(
      ProviderScope(
        overrides: [
          trainingPlansProvider.overrideWithProvider(emptyProvider),
        ],
        child: const TrainingPlanScreen(),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('0 个方案'), findsOneWidget);
  });

  testWidgets('错误 → 显示错误卡片', (tester) async {
    final errorProvider =
        FutureProvider.family<Result<List<TrainingPlan>>, int>((ref, grade) async {
      return Err(AppError.configMissing('测试错误')
        ..recoveryHint = '请先配置');
    });

    await tester.pumpWidget(_wrap(
      ProviderScope(
        overrides: [
          trainingPlansProvider.overrideWithProvider(errorProvider),
        ],
        child: const TrainingPlanScreen(),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('缺少必要配置'), findsOneWidget);
    expect(find.textContaining('请先配置'), findsOneWidget);
  });
}
