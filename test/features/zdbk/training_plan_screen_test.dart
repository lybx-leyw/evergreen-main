import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:evergreen_multi_tools/features/zdbk/screens/training_plan_screen.dart';

Widget _wrap(Widget child) => ProviderScope(child: MaterialApp(home: child));

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
}
