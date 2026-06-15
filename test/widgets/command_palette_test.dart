import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'package:evergreen_multi_tools/widgets/command_palette.dart';

void main() {
  group('CommandPalette', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('搜索过滤', (tester) async {
      final router = GoRouter(routes: [
        GoRoute(path: '/', builder: (_, __) => const SizedBox()),
      ]);

      await tester.pumpWidget(ProviderScope(
        child: MaterialApp.router(routerConfig: router),
      ));

      await CommandPalette.show(tester.element(find.byType(SizedBox)));
      await tester.pump();
      expect(find.byType(TextField), findsOneWidget);
    });
  });
}
