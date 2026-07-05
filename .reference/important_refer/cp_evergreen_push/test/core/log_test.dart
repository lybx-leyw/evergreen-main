import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/core/log.dart';

void main() {
  test('Log() 单例 — 两次调用返回同一实例', () {
    final a = Log();
    final b = Log();
    expect(identical(a, b), isTrue);
  });

  test('Log.debug() 不抛出异常', () {
    expect(() => Log().debug('test debug message'), returnsNormally);
  });

  test('Log.info() 带 data 参数不抛出异常', () {
    expect(
      () => Log().info('test info', data: {'key': 'value'}),
      returnsNormally,
    );
  });

  test('Log.warn() 带 error 参数不抛出异常', () {
    expect(
      () => Log().warn('test warn', error: Exception('test')),
      returnsNormally,
    );
  });

  test('Log.error() 带 stack 参数不抛出异常', () {
    expect(
      () => Log().error('test error',
          error: Exception('critical'), stack: StackTrace.current),
      returnsNormally,
    );
  });

  test('Log.exportRecent() 返回文本（含最近写入的日志）', () async {
    Log().info('marker message for export test');
    final exported = await Log().exportRecent(lines: 50);
    expect(exported, isNotEmpty);
    expect(exported, contains('marker message'));
  });
}
