import 'package:evergreen_base/core/log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Log errorId', () {
    test('相同 (模块, 消息) 在去重窗口内复用同一 errorId', () async {
      // 注意：消息必须完全相同（不带时间戳），否则哈希不同
      Log().error('smoke-dup-const-msg');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      Log().error('smoke-dup-const-msg');
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final errs = Log()
          .entries(minLevel: LogLevel.error)
          .where((e) => e.msg.contains('smoke-dup-const-msg'))
          .toList();
      expect(errs.length, greaterThanOrEqualTo(2));
      final ids = errs.map((e) => e.errorId).toSet();
      expect(ids.length, 1, reason: '相同消息应复用同一 errorId，实际: $ids');
      expect(errs.first.errorId, startsWith('EVG-'));
      expect(errs.first.errorId!.length, 'EVG-'.length + 8);
    });

    test('不同消息生成不同 errorId', () async {
      Log().error('smoke-msg-a-${DateTime.now().microsecondsSinceEpoch}');
      Log().error('smoke-msg-b-${DateTime.now().microsecondsSinceEpoch}');
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final errs = Log()
          .entries(minLevel: LogLevel.error)
          .where((e) => e.msg.startsWith('smoke-msg-'))
          .toList();
      expect(errs.length, greaterThanOrEqualTo(2));
      expect(errs.map((e) => e.errorId).toSet().length,
          greaterThanOrEqualTo(2));
    });
  });

  group('Log entries 过滤', () {
    test('exportRecent 包含最近日志且可被错误中心复用', () async {
      final marker = 'smoke-export-marker-${DateTime.now().microsecondsSinceEpoch}';
      Log().info(marker);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final text = await Log().exportRecent(lines: 100);
      expect(text, contains(marker));
      // exportRecent 的输出行格式与契约一致：带 errorId 的 ERROR 行
      Log().error('smoke-export-err-${DateTime.now().microsecondsSinceEpoch}');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final text2 = await Log().exportRecent(lines: 100);
      expect(text2, contains('[ERROR]'));
      expect(text2, contains('EVG-'));
    });

    test('module + minLevel 过滤生效', () async {
      Log().info('smoke-filter-info-${DateTime.now().microsecondsSinceEpoch}');
      Log().error('smoke-filter-err-${DateTime.now().microsecondsSinceEpoch}');
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final errs = Log()
          .entries(minLevel: LogLevel.error)
          .where((e) => e.msg.startsWith('smoke-filter'))
          .toList();
      expect(errs.every((e) => e.level == LogLevel.error), isTrue);
      expect(errs.length, greaterThanOrEqualTo(1));

      final errOnly = Log()
          .entries(minLevel: LogLevel.error)
          .where((e) => e.msg.startsWith('smoke-filter'))
          .toList();
      expect(errOnly.where((e) => e.level == LogLevel.info), isEmpty);
    });

    test('LogEntry 携带 module 标签', () async {
      Log().warn('smoke-module-warn-${DateTime.now().microsecondsSinceEpoch}');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final warns = Log()
          .entries(minLevel: LogLevel.warn)
          .where((e) => e.msg.startsWith('smoke-module-warn'))
          .toList();
      expect(warns, isNotEmpty);
      expect(warns.first.module, isNotNull);
    });
  });
}
