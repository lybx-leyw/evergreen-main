import 'package:evergreen_base/core/errors.dart';
import 'package:evergreen_base/core/log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppError errorId', () {
    test('errorId 格式为 EVG-<模块>-<8位hex> 且稳定复用', () {
      final e1 = AppError.unknown(StateError('boom'));
      final e2 = AppError.unknown(StateError('boom'));
      expect(e1.errorId, matches(RegExp(r'^EVG-[A-Z]{3}-[0-9a-f]{8}$')));
      expect(e1.errorId, e2.errorId, reason: '相同错误应生成相同 errorId');
      expect(e1.moduleCode, 'SVC');
    });

    test('不同模块前缀映射', () {
      expect(AppError.configMissing('x').moduleCode, 'CONF');
      expect(AppError.parseJson('{}', 'f').moduleCode, 'DATA');
      expect(AppError.cacheMiss('k').moduleCode, 'DATA');
      expect(AppError.renderError('W', 'f', 'r').moduleCode, 'REND');
      expect(AppError.mediaFailed('video', 'u').moduleCode, 'REND');
      expect(AppError.fileError('p', 'read').moduleCode, 'SVC');
      expect(AppError.networkUnreachable('u').moduleCode, 'SVC');
    });

    test('toLogLine 包含模块/类型/调试消息/位置', () {
      final e = AppError.parseJson('{"a":1}', 'b');
      final line = e.toLogLine();
      expect(line, contains('[DATA]'));
      expect(line, contains('ParseError'));
      expect(line, contains('Failed to parse JSON field: b'));
      expect(line, contains('@'));
      expect(line, contains('.dart'));
      expect(line, contains('hint:'));
    });
  });

  group('AppError → Log errorId 链路', () {
    test('Log.error 优先使用 AppError.errorId', () async {
      final err = AppError.networkUnreachable('https://x');
      Log().error('链路测试', error: err);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final errs = Log()
          .entries(minLevel: LogLevel.error)
          .where((e) => e.msg == '链路测试')
          .toList();
      expect(errs, isNotEmpty);
      expect(errs.first.errorId, err.errorId);
      expect(errs.first.errorId, startsWith('EVG-SVC-'));
    });
  });
}
