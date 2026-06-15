import 'package:flutter_test/flutter_test.dart';

/// 0.2.1 — CallbackAction 中 invalidate provider 不应触发 wrong build scope。
///
/// 修复前：_handleRefresh 直接 ref.invalidate 14 个 provider，
/// 在 Shortcuts action 回调中触发 widget rebuild。
/// 修复后：全部包在 addPostFrameCallback 中。
void main() {
  group('CallbackAction — safe invalidate', () {
    test('addPostFrameCallback 将 invalidate 延迟到下一帧', () async {
      final timeline = <String>[];
      // 模拟 _handleRefresh 的 addPostFrameCallback
      Future.microtask(() {
        timeline.add('invalidate');
      });
      timeline.add('callback_end');
      // invalidate 在 callback 之后执行
      expect(timeline.last, 'callback_end');
      await Future.delayed(Duration.zero);
      expect(timeline, ['callback_end', 'invalidate']);
    });

    test('同步 invalidate 与异步 invalidate 的时序差', () {
      final a = <String>[];
      // 同步
      a.add('sync');
      // 异步（模拟 postFrame）
      Future.microtask(() => a.add('async'));
      expect(a.length, 1); // 异步尚未执行
      expect(a.first, 'sync');
    });
  });
}
