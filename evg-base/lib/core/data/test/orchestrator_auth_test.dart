/// DataOrchestrator 会话绑定测试——manifest `auth.sessionProvider` 声明后：
/// 拉取失败且错误被判为「会话失效」→ 单点重登 → 重拉一次；未声明/未注册则原路径。
library;

import 'package:test/test.dart';

import '../orchestrator.dart';
import '../type.dart';
import '../session_provider.dart';

class _SessionExpired implements Exception {
  const _SessionExpired();
  @override
  String toString() => 'SessionExpired';
}

void main() {
  late DataOrchestrator orch;
  late SessionCoordinator coord;

  setUp(() {
    orch = DataOrchestrator();
    coord = SessionCoordinator();
  });

  const authType = DataType<Map<String, dynamic>>(
    name: 'auth_test',
    category: '测试',
    sessionProviderId: 'zju',
  );

  const noAuthType = DataType<Map<String, dynamic>>(
    name: 'no_auth_test',
    category: '测试',
  );

  group('会话失效 → 单点重登 → 重拉', () {
    test('重登成功且重拉成功返回数据', () async {
      final provider = InMemorySessionProvider(
        sessionProviderId: 'zju',
        onExpired: (e) => e is _SessionExpired,
        onRefresh: () async => true,
      );
      coord.registerSessionProvider(provider.sessionProviderId, provider);
      orch.sessionCoordinator = coord;

      var calls = 0;
      orch.register(authType, () async {
        calls++;
        if (calls == 1) throw const _SessionExpired();
        return {'ok': true};
      });

      final data = await orch.get(authType);

      expect(data, {'ok': true});
      expect(provider.refreshCalls, 1); // 只触发一次重登
      expect(orch.status('auth_test')!.connected, isTrue);
      expect(orch.status('auth_test')!.lastError, isNull);
    });

    test('重登成功但重拉仍失败 → lastError 注明「已重登仍失败」', () async {
      final provider = InMemorySessionProvider(
        sessionProviderId: 'zju',
        onExpired: (e) => e is _SessionExpired,
        onRefresh: () async => true,
      );
      coord.registerSessionProvider(provider.sessionProviderId, provider);
      orch.sessionCoordinator = coord;

      orch.register(authType, () async => throw const _SessionExpired());

      final data = await orch.get(authType);

      expect(data, isNull);
      expect(provider.refreshCalls, 1);
      expect(orch.status('auth_test')!.connected, isFalse);
      expect(
        orch.status('auth_test')!.lastError,
        startsWith(kDataReloginRetryFailedPrefix),
      );
    });

    test('重登本身失败 → lastError 注明「重登失败」', () async {
      final provider = InMemorySessionProvider(
        sessionProviderId: 'zju',
        onExpired: (e) => e is _SessionExpired,
        onRefresh: () async => false,
      );
      coord.registerSessionProvider(provider.sessionProviderId, provider);
      orch.sessionCoordinator = coord;

      orch.register(authType, () async => throw const _SessionExpired());

      final data = await orch.get(authType);

      expect(data, isNull);
      expect(provider.refreshCalls, 1);
      expect(
        orch.status('auth_test')!.lastError,
        startsWith(kDataReloginFailedPrefix),
      );
    });
  });

  group('零行为变化（未声明 / 未注册 / 非会话错误）', () {
    test('未声明 sessionProviderId → 不重登，走原路径', () async {
      final provider = InMemorySessionProvider(
        sessionProviderId: 'zju',
        onExpired: (e) => e is _SessionExpired,
      );
      coord.registerSessionProvider(provider.sessionProviderId, provider);
      orch.sessionCoordinator = coord;

      orch.register(noAuthType, () async => throw const _SessionExpired());

      final data = await orch.get(noAuthType);

      expect(data, isNull);
      expect(provider.refreshCalls, 0);
      expect(
        orch.status('no_auth_test')!.lastError,
        startsWith(kDataFetchFailedPrefix),
      );
    });

    test('声明 auth 但 provider 未注册 → 不重登', () async {
      orch.sessionCoordinator = coord; // 空注册表

      orch.register(authType, () async => throw const _SessionExpired());

      final data = await orch.get(authType);

      expect(data, isNull);
      expect(
        orch.status('auth_test')!.lastError,
        startsWith(kDataFetchFailedPrefix),
      );
    });

    test('声明 auth 且注册 provider 但错误非会话失效 → 不重登', () async {
      final provider = InMemorySessionProvider(
        sessionProviderId: 'zju',
        onExpired: (e) => false, // 永不判为会话失效
      );
      coord.registerSessionProvider(provider.sessionProviderId, provider);
      orch.sessionCoordinator = coord;

      orch.register(authType, () async => throw StateError('network down'));

      final data = await orch.get(authType);

      expect(data, isNull);
      expect(provider.refreshCalls, 0);
      expect(
        orch.status('auth_test')!.lastError,
        startsWith(kDataFetchFailedPrefix),
      );
    });

    test('未设置 sessionCoordinator → 即使声明 auth 也不重登', () async {
      // orch.sessionCoordinator 保持 null
      orch.register(authType, () async => throw const _SessionExpired());

      final data = await orch.get(authType);

      expect(data, isNull);
      expect(
        orch.status('auth_test')!.lastError,
        startsWith(kDataFetchFailedPrefix),
      );
    });
  });
}
