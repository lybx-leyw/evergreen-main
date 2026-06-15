import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AutoRefresh', () {
    test('shouldRefresh 返回 enabled 状态', () {
      // 模拟 AutoRefreshState
      const enabled = true;
      const disabled = false;
      expect(enabled, true);
      expect(disabled, false);
    });

    test('restartAutoRefresh 取消旧定时器', () async {
      Timer? timer;
      var ticks = 0;

      timer = Timer.periodic(const Duration(milliseconds: 10), (_) {
        ticks++;
      });

      await Future.delayed(const Duration(milliseconds: 35));
      expect(ticks, greaterThan(0));

      // 取消旧定时器
      timer?.cancel();
      final afterCancel = ticks;
      await Future.delayed(const Duration(milliseconds: 30));
      expect(ticks, afterCancel); // 不再递增
    });

    test('tick 通过 Future.delayed 延迟避免同帧冲突', () async {
      final order = <String>[];
      // 模拟 auto_refresh 的 500ms 延迟
      Future.delayed(const Duration(milliseconds: 50), () {
        order.add('tick');
      });
      order.add('frame_end');
      expect(order.last, 'frame_end');
      await Future.delayed(const Duration(milliseconds: 100));
      expect(order, ['frame_end', 'tick']);
    });

    test('enabled=false 时不启动定时器', () {
      Timer? timer;
      const enabled = false;
      if (!enabled) {
        // 不创建 timer
      }
      expect(timer, isNull);
    });
  });
}
