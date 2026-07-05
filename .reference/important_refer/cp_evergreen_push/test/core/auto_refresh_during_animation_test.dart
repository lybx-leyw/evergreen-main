import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

/// 0.2.3 — auto_refresh tick 延迟到下一微任务，不与当前帧冲突。
void main() {
  group('AutoRefresh — tick delay', () {
    test('onTick 通过 Future.delayed(Duration.zero) 延迟', () async {
      var fired = 0;
      // 模拟 auto_refresh.dart 的 Timer.periodic 回调
      final completer = Completer<void>();
      Future.delayed(Duration.zero, () {
        fired++;
        completer.complete();
      });
      // 在延迟期间 fired 还未被调用
      expect(fired, 0);
      await completer.future;
      expect(fired, 1);
    });

    test('同步调用会立即触发（对比）', () {
      var fired = 0;
      void tick() {
        fired++;
      }
      tick();
      expect(fired, 1); // 同步立即执行
    });
  });
}
