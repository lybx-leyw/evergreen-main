/// SessionProvider + SessionCoordinator 测试——登录锁（Future 共享）/ 单点重登 / 注册表。
library;

import 'package:test/test.dart';

import '../session_provider.dart';

void main() {
  group('注册表', () {
    test('registerSessionProvider / sessionProviderById / hasProvider', () {
      final coord = SessionCoordinator();
      final p = InMemorySessionProvider(sessionProviderId: 'zju');
      expect(coord.hasProvider('zju'), isFalse);
      coord.registerSessionProvider(p.sessionProviderId, p);
      expect(coord.hasProvider('zju'), isTrue);
      expect(coord.sessionProviderById('zju'), same(p));
    });

    test('registerSessionProvider(String id, provider) 覆盖同名', () {
      final coord = SessionCoordinator();
      final p1 = InMemorySessionProvider(sessionProviderId: 'a');
      final p2 = InMemorySessionProvider(sessionProviderId: 'b');
      coord.registerSessionProvider('x', p1);
      coord.registerSessionProvider('x', p2);
      expect(coord.sessionProviderById('x'), same(p2));
    });

    test('unregisterSessionProvider 后查找返回 null', () {
      final coord = SessionCoordinator();
      coord.registerSessionProvider(
          'z', InMemorySessionProvider(sessionProviderId: 'z'));
      coord.unregisterSessionProvider('z');
      expect(coord.sessionProviderById('z'), isNull);
    });

    test('未注册 provider 的 ensureSession 返回 false', () async {
      final coord = SessionCoordinator();
      expect(await coord.ensureSession('nope'), isFalse);
      expect(await coord.refreshSession('nope'), isFalse);
    });
  });

  group('登录锁（Future 共享）', () {
    test('并发 ensureSession 只触发一次真实登录', () async {
      final coord = SessionCoordinator();
      final p = InMemorySessionProvider(
        sessionProviderId: 'zju',
        onEnsure: () async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return true;
        },
      );
      coord.registerSessionProvider(p.sessionProviderId, p);

      final results = await Future.wait([
        coord.ensureSession('zju'),
        coord.ensureSession('zju'),
        coord.ensureSession('zju'),
      ]);

      expect(results, everyElement(isTrue));
      expect(p.ensureCalls, 1);
    });

    test('in-flight 完成后，再次 ensureSession 触发新登录', () async {
      final coord = SessionCoordinator();
      final p = InMemorySessionProvider(sessionProviderId: 'zju');
      coord.registerSessionProvider(p.sessionProviderId, p);

      await coord.ensureSession('zju');
      await coord.ensureSession('zju');

      expect(p.ensureCalls, 2);
    });

    test('provider 抛异常收敛为 false，不污染共享 Future', () async {
      final coord = SessionCoordinator();
      final p = InMemorySessionProvider(
        sessionProviderId: 'zju',
        onEnsure: () async => throw StateError('boom'),
      );
      coord.registerSessionProvider(p.sessionProviderId, p);

      expect(await coord.ensureSession('zju'), isFalse);
      // 异常被收敛，下一次仍可正常触发
      expect(await coord.ensureSession('zju'), isFalse);
      expect(p.ensureCalls, 2);
    });
  });

  group('单点重登', () {
    test('并发 refreshSession 只触发一次重登', () async {
      final coord = SessionCoordinator();
      final p = InMemorySessionProvider(
        sessionProviderId: 'zju',
        onRefresh: () async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return true;
        },
      );
      coord.registerSessionProvider(p.sessionProviderId, p);

      final results = await Future.wait([
        coord.refreshSession('zju'),
        coord.refreshSession('zju'),
        coord.refreshSession('zju'),
      ]);

      expect(results, everyElement(isTrue));
      expect(p.refreshCalls, 1);
    });

    test('重登完成后再次 refreshSession 触发新重登', () async {
      final coord = SessionCoordinator();
      final p = InMemorySessionProvider(sessionProviderId: 'zju');
      coord.registerSessionProvider(p.sessionProviderId, p);

      await coord.refreshSession('zju');
      await coord.refreshSession('zju');

      expect(p.refreshCalls, 2);
    });
  });

  group('isSessionExpired 透传', () {
    test('按 error 判定会话失效', () {
      final p = InMemorySessionProvider(
        sessionProviderId: 'zju',
        onExpired: (e) => e is _SessionExpired,
      );
      expect(p.isSessionExpired(const _SessionExpired()), isTrue);
      expect(p.isSessionExpired(StateError('network')), isFalse);
    });
  });
}

class _SessionExpired implements Exception {
  const _SessionExpired();
  @override
  String toString() => 'SessionExpired';
}
