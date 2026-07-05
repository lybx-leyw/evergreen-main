import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:evergreen_multi_tools/widgets/freshness_badge.dart';

void main() {
  group('FreshnessBadge', () {
    testWidgets('无缓存时显示从未更新', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              title: const Text('test'),
              actions: const [FreshnessBadge(cacheKey: '__nonexistent__')],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('从未更新'), findsOneWidget);
    });

    testWidgets('lastFetchedAt 有值时显示时间', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              title: const Text('test'),
              actions: [
                FreshnessBadge(
                  cacheKey: '',
                  lastFetchedAt: DateTime.now().subtract(const Duration(minutes: 3)),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.access_time), findsOneWidget);
      expect(find.text('3分钟前'), findsOneWidget);
    });

    testWidgets('从未更新时显示对应文本', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              title: const Text('test'),
              actions: [
                FreshnessBadge(
                  cacheKey: '',
                  lastFetchedAt: DateTime.now(),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('刚刚更新'), findsOneWidget);
    });
  });
}
