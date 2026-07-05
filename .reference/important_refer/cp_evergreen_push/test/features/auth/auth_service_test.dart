import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/features/auth/services/auth_service.dart';

void main() {
  group('ServiceResult', () {
    test('success 标记正确', () {
      final r = ServiceResult.success();
      expect(r.ok, isTrue);
      expect(r.error, isNull);
    });

    test('failure 携带错误消息', () {
      final r = ServiceResult.failure('timeout');
      expect(r.ok, isFalse);
      expect(r.error, 'timeout');
    });

    test('failure 空错误消息', () {
      final r = ServiceResult.failure('');
      expect(r.ok, isFalse);
      expect(r.error, '');
    });
  });

  group('AuthResult', () {
    test('allOk — 全部成功', () {
      final r = AuthResult(results: {
        'ZDBK': ServiceResult.success(),
        'Courses': ServiceResult.success(),
        'Classroom': ServiceResult.success(),
      });
      expect(r.allOk, isTrue);
    });

    test('allOk — 一个失败', () {
      final r = AuthResult(results: {
        'ZDBK': ServiceResult.success(),
        'Courses': ServiceResult.failure('timeout'),
        'Classroom': ServiceResult.success(),
      });
      expect(r.allOk, isFalse);
    });

    test('allOk — 全部失败', () {
      final r = AuthResult(results: {
        'Courses': ServiceResult.failure('dns'),
        'Classroom': ServiceResult.failure('refused'),
      });
      expect(r.allOk, isFalse);
    });

    test('allOk — 空结果', () {
      final r = AuthResult(results: {});
      expect(r.allOk, isTrue); // vacuous truth
    });

    test('results 不可变（外部修改不影响内部）', () {
      final original = {'A': ServiceResult.success()};
      final r = AuthResult(results: original);
      original['B'] = ServiceResult.failure('x');
      expect(r.results.length, 1);
    });
  });

  group('AuthProgress', () {
    test('inProgress 状态', () {
      final p = AuthProgress(
        service: 'Courses',
        step: '正在登录...',
        status: AuthStatus.inProgress,
      );
      expect(p.service, 'Courses');
      expect(p.step, '正在登录...');
      expect(p.status, AuthStatus.inProgress);
      expect(p.error, isNull);
    });

    test('success 状态', () {
      final p = AuthProgress(
        service: 'ZDBK',
        step: '登录成功',
        status: AuthStatus.success,
      );
      expect(p.status, AuthStatus.success);
    });

    test('failed 状态带错误', () {
      final p = AuthProgress(
        service: 'Classroom',
        step: '登录失败',
        status: AuthStatus.failed,
        error: 'Connection refused',
      );
      expect(p.status, AuthStatus.failed);
      expect(p.error, 'Connection refused');
    });

    test('三个服务的完整登录序列', () {
      final events = [
        AuthProgress(
            service: 'ZDBK',
            step: '正在登录...',
            status: AuthStatus.inProgress),
        AuthProgress(
            service: 'ZDBK',
            step: '登录成功',
            status: AuthStatus.success),
        AuthProgress(
            service: 'Courses',
            step: '正在登录...',
            status: AuthStatus.inProgress),
        AuthProgress(
            service: 'Courses',
            step: '登录成功',
            status: AuthStatus.success),
        AuthProgress(
            service: 'Classroom',
            step: '正在登录...',
            status: AuthStatus.inProgress),
        AuthProgress(
            service: 'Classroom',
            step: '登录失败',
            status: AuthStatus.failed,
            error: 'OAuth2 timeout'),
      ];

      final inProgressCount =
          events.where((e) => e.status == AuthStatus.inProgress).length;
      final successCount =
          events.where((e) => e.status == AuthStatus.success).length;
      final failedCount =
          events.where((e) => e.status == AuthStatus.failed).length;

      expect(inProgressCount, 3);
      expect(successCount, 2);
      expect(failedCount, 1);
    });

    test('进度事件不可变', () {
      final p = AuthProgress(
        service: 'A', step: 's', status: AuthStatus.inProgress);
      expect(p.service, 'A');
      // No setters — compile-time guarantee
    });
  });
}
