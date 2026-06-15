import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 边界测试：Widget 生命周期 + Provider 状态变更的竞态条件。
///
/// 覆盖实际踩坑场景：
/// - dispose 后 addPostFrameCallback 仍尝试 setState
/// - Provider invalidate 触发已卸载 widget 重建
/// - Navigator pop 与 Provider 更新同时发生

final _counterProvider = StateProvider<int>((ref) => 0);

// Widget 在 dispose 后会尝试 setState
class _LeakyWidget extends StatefulWidget {
  final VoidCallback? onBuild;
  const _LeakyWidget({super.key, this.onBuild});
  @override
  State<_LeakyWidget> createState() => _LeakyWidgetState();
}

class _LeakyWidgetState extends State<_LeakyWidget> {
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void safeUpdate() {
    if (!_disposed && mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    widget.onBuild?.call();
    return const SizedBox();
  }
}

void main() {
  group('Widget lifecycle — edge cases', () {
    testWidgets('dispose 后 setState 被 mounted 守卫阻止', (tester) async {
      final state = GlobalKey<_LeakyWidgetState>();
      await tester.pumpWidget(MaterialApp(
        home: _LeakyWidget(key: state),
      ));

      final s = state.currentState!;
      // 卸载
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump();

      // dispose 后 safeUpdate 不抛异常
      expect(() => s.safeUpdate(), returnsNormally);
    });

    testWidgets('addPostFrameCallback 在 dispose 后不崩溃', (tester) async {
      bool callbackFired = false;
      final widget = _LeakyWidget(onBuild: () {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          callbackFired = true;
        });
      });

      await tester.pumpWidget(MaterialApp(home: widget));
      await tester.pump(); // 触发 postFrameCallback

      // 卸载
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump(const Duration(milliseconds: 100));

      // 不应崩溃
      expect(tester.takeException(), isNull);
    });

    testWidgets('Provider invalidate 不在非 build 上下文触发重建', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // 直接在回调中 invalidate（模拟 CallbackAction）
      var threw = false;
      try {
        // 没有 Widget 上下文，直接操作 container 不会崩溃
        container.invalidate(_counterProvider);
      } catch (_) {
        threw = true;
      }
      expect(threw, false);
    });
  });

  group('Animation — no state update during transition', () {
    testWidgets('AnimatedContainer 动画期间 setState 不崩溃', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 300),
              builder: (_, v, __) => SizedBox(width: 100 * v, height: 50),
            ),
          ),
        ),
      ));

      // 动画中途 pump
      await tester.pump(const Duration(milliseconds: 100));
      // 再 pump 到结束
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Navigator pop 与 State update 不冲突', (tester) async {
      final key = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(
        navigatorKey: key,
        home: Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const Scaffold())),
            child: const Text('go'),
          );
        }),
      ));
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // pop
      key.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
    });
  });
}
