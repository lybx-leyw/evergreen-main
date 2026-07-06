/// 原子组件 widgetTest——widgets/ 核心组件的渲染测试。
///
/// 使用 testWidgets + MaterialApp + Scaffold 包裹，mock 描述符和数据。
/// 验证重点：存在性 (findsOneWidget) + 数据正确性（字段断言）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/renderer/widgets/models.dart';
import 'package:evergreen_base/renderer/widgets/dashboard_card.dart';
import 'package:evergreen_base/renderer/widgets/empty_state.dart';
import 'package:evergreen_base/renderer/widgets/error_card.dart';
import 'package:evergreen_base/renderer/widgets/evergreen_progress.dart';
import 'package:evergreen_base/renderer/widgets/loading_indicator.dart';
import 'package:evergreen_base/renderer/widgets/confirm_dialog.dart';
import 'package:evergreen_base/renderer/widgets/ability_tag.dart';
import 'package:evergreen_base/renderer/widgets/notification_card.dart';

// ═══════ DashboardCard ═══════

void main() {
  group('DashboardCard', () {
    testWidgets('renders title and value', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DashboardCard(
              title: '活跃用户',
              value: '1,234',
              trend: 'up',
              subtitle: '+12% vs 上周',
            ),
          ),
        ),
      );

      expect(find.text('活跃用户'), findsOneWidget);
      expect(find.text('1,234'), findsOneWidget);
      expect(find.text('+12% vs 上周'), findsOneWidget);
      // trend icon should be present
      expect(find.byIcon(Icons.trending_up), findsOneWidget);
    });

    testWidgets('renders with down trend', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DashboardCard(
              title: '错误率',
              value: '0.12%',
              trend: 'down',
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.trending_down), findsOneWidget);
    });

    testWidgets('renders with neutral trend', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DashboardCard(
              title: '状态',
              value: '正常',
              trend: 'neutral',
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.trending_flat), findsOneWidget);
    });

    testWidgets('renders without trend', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DashboardCard(title: '总计', value: '500'),
          ),
        ),
      );

      expect(find.byIcon(Icons.trending_up), findsNothing);
      expect(find.byIcon(Icons.trending_down), findsNothing);
      expect(find.byIcon(Icons.trending_flat), findsNothing);
    });

    testWidgets('handles null value gracefully', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DashboardCard(title: '未知', value: null),
          ),
        ),
      );

      expect(find.text('--'), findsOneWidget);
    });
  });

  // ═══════ EmptyState ═══════

  group('EmptyState', () {
    testWidgets('renders with icon and title', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EmptyState(
              icon: Icons.inbox_outlined,
              title: '暂无数据',
            ),
          ),
        ),
      );

      expect(find.text('暂无数据'), findsOneWidget);
      expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
    });

    testWidgets('renders subtitle when provided', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EmptyState(
              title: '空',
              subtitle: '这里还没有内容',
            ),
          ),
        ),
      );

      expect(find.text('这里还没有内容'), findsOneWidget);
    });

    testWidgets('does not render subtitle when not provided', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EmptyState(title: '空'),
          ),
        ),
      );

      // subtitle text should not exist
      expect(
        find.descendant(
          of: find.byType(EmptyState),
          matching: find.byWidgetPredicate(
            (w) => w is Text && w.data != null && w.data!.contains('subtitle'),
          ),
        ),
        findsNothing,
      );
    });
  });

  // ═══════ ErrorCard ═══════

  group('ErrorCard', () {
    testWidgets('renders error message', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ErrorCard(message: '网络连接失败'),
          ),
        ),
      );

      expect(find.text('网络连接失败'), findsOneWidget);
    });

    testWidgets('renders detail and hint when provided', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ErrorCard(
              message: '加载失败',
              detail: '服务器返回 500',
              hint: '请检查网络连接',
            ),
          ),
        ),
      );

      expect(find.text('服务器返回 500'), findsOneWidget);
      expect(find.text('请检查网络连接'), findsOneWidget);
    });

    testWidgets('shows retry button when onRetry is provided', (tester) async {
      var retryCalled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ErrorCard(
              message: '错误',
              onRetry: () => retryCalled = true,
            ),
          ),
        ),
      );

      expect(find.text('重试'), findsOneWidget);
      await tester.tap(find.text('重试'));
      expect(retryCalled, isTrue);
    });

    testWidgets('does not show retry button when onRetry is null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ErrorCard(message: '错误'),
          ),
        ),
      );

      expect(find.text('重试'), findsNothing);
    });
  });

  // ═══════ EvergreenProgress ═══════

  group('EvergreenProgress', () {
    testWidgets('renders with label', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EvergreenProgress(value: 0.5, label: '加载中...'),
          ),
        ),
      );

      expect(find.text('加载中...'), findsOneWidget);
    });

    testWidgets('renders in indeterminate mode without value', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EvergreenProgress(),
          ),
        ),
      );

      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });
  });

  // ═══════ LoadingIndicator ═══════

  group('LoadingIndicator', () {
    testWidgets('renders with message', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LoadingIndicator(message: '正在加载...'),
          ),
        ),
      );

      expect(find.text('正在加载...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('renders compact mode', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LoadingIndicator.compact(hint: '查询中...'),
          ),
        ),
      );

      expect(find.text('查询中...'), findsOneWidget);
    });
  });

  // ═══════ ConfirmDialog ═══════

  group('ConfirmDialog', () {
    testWidgets('shows dialog with title and message', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  ConfirmDialog.show(
                    context,
                    title: '确认删除',
                    message: '确定要删除吗？',
                  );
                },
                child: const Text('触发'),
              ),
            ),
          ),
        ),
      );

      // 点击触发按钮
      await tester.tap(find.text('触发'));
      await tester.pumpAndSettle();

      // 弹窗应该显示
      expect(find.text('确认删除'), findsOneWidget);
      expect(find.text('确定要删除吗？'), findsOneWidget);
      expect(find.text('确认'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);
    });

    testWidgets('dismisses on cancel', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  ConfirmDialog.show(context);
                },
                child: const Text('触发'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('触发'));
      await tester.pumpAndSettle();

      // 点击取消
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      // 弹窗应该消失
      expect(find.text('确认操作'), findsNothing);
    });
  });

  // ═══════ AbilityTag ═══════

  group('AbilityTag', () {
    testWidgets('renders with display name', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AbilityTag(dim: AbilityDim.agent),
          ),
        ),
      );

      expect(find.text('智能体'), findsOneWidget);
    });

    testWidgets('renders all six dimensions', (tester) async {
      const dims = [
        AbilityDim.agent,
        AbilityDim.ui,
        AbilityDim.data,
        AbilityDim.theme,
        AbilityDim.settings,
        AbilityDim.skill,
      ];
      const labels = ['智能体', '界面', '数据', '主题', '设置', '技能'];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Wrap(
              children: dims
                  .map((d) => AbilityTag(dim: d))
                  .toList(),
            ),
          ),
        ),
      );

      for (final label in labels) {
        expect(find.text(label), findsOneWidget);
      }
    });

    testWidgets('renders compact mode without text', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AbilityTag(dim: AbilityDim.agent, compact: true),
          ),
        ),
      );

      // compact mode shows only icon, no text
      expect(find.text('智能体'), findsNothing);
    });
  });

  // ═══════ NotificationCard ═══════

  group('NotificationCard', () {
    testWidgets('renders notification title and message', (tester) async {
      final notification = AppNotification(
        title: '插件更新',
        message: '词汇导师 v1.3.0 已发布',
        type: NotificationType.update,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NotificationCard(notification: notification),
          ),
        ),
      );

      expect(find.text('插件更新'), findsOneWidget);
      expect(find.text('词汇导师 v1.3.0 已发布'), findsOneWidget);
    });

    testWidgets('renders different notification types', (tester) async {
      final types = [
        (NotificationType.info, '信息'),
        (NotificationType.success, '成功'),
        (NotificationType.warning, '警告'),
        (NotificationType.error, '错误'),
        (NotificationType.update, '更新'),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: types
                  .map((t) => NotificationCard(
                        notification: AppNotification(
                          title: t.$2,
                          message: 'test',
                          type: t.$1,
                        ),
                      ))
                  .toList(),
            ),
          ),
        ),
      );

      for (final t in types) {
        expect(find.text(t.$2), findsOneWidget);
      }
    });
  });
}
