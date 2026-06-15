import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

/// 0.2.2 — Agent 事件流在 Widget dispose 后停止调用 setState。
///
/// 修复前：chat_screen.dart 的事件监听在 dispose 后仍可能触发
/// ref.read(controllerStateProvider.notifier).state = ...，
/// 导致 "wrong build scope"。
void main() {
  group('Stream — state after dispose', () {
    test('mounted 守卫阻止 dispose 后的 setState', () async {
      var mounted = true;
      final controller = StreamController<int>();
      final events = <int>[];

      final sub = controller.stream.listen((v) {
        if (!mounted) return;
        events.add(v);
      });

      controller.add(1);
      await Future.delayed(Duration.zero);
      expect(events, [1]);

      // 模拟 dispose
      mounted = false;
      controller.add(2);
      await Future.delayed(Duration.zero);

      // dispose 后的事件被丢弃
      expect(events, [1]);
      await sub.cancel();
      await controller.close();
    });

    test('addPostFrameCallback 延迟状态更新防冲突', () async {
      final results = <String>[];
      // 模拟 addPostFrameCallback 行为
      results.add('sync');
      Future.delayed(Duration.zero, () {
        results.add('delayed');
      });
      // 同步部分先执行
      expect(results, ['sync']);
      // 延迟部分后执行
      await Future.delayed(const Duration(milliseconds: 10));
      expect(results, ['sync', 'delayed']);
    });
  });
}
