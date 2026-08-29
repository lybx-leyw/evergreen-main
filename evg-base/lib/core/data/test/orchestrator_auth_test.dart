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

  const domainTypeA = DataType<Map<String, dynamic>>(
    name: 'domain_test_a',
    category: '测试',
    sessionProviderId: 'zju',
    sessionDomain: 'jwxt.zju.edu.cn',
  );

  const domainTypeB = DataType<Map<String, dynamic>>(
    name: 'domain_test_b',
    category: '测试',
    sessionProviderId: 'zju',
    sessionDomain: 'jwxt.zju.edu.cn',
  );

  const otherDomainType = DataType<Map<String, dynamic>>(
    name: 'other_domain_test',
    category: '测试',
    sessionProviderId: 'zju',
    sessionDomain: 'zdbk.zju.edu.cn',
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

  group('登录域分组（sessionDomain 细化登录锁）', () {
    test('同域多数据源并发失效 → 只触发一次重登（按域共享登录锁）', () async {
      final provider = InMemorySessionProvider(
        sessionProviderId: 'zju',
        onExpired: (e) => e is _SessionExpired,
        onRefresh: () async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return true;
        },
      );
      coord.registerSessionProvider(provider.sessionProviderId, provider);
      orch.sessionCoordinator = coord;

      // 两个数据源同域（jwxt.zju.edu.cn），首个拉取都失败且判为会话失效
      var callsA = 0;
      var callsB = 0;
      orch.register(domainTypeA, () async {
        callsA++;
        if (callsA == 1) throw const _SessionExpired();
        return {'a': true};
      });
      orch.register(domainTypeB, () async {
        callsB++;
        if (callsB == 1) throw const _SessionExpired();
        return {'b': true};
      });

      final results = await Future.wait([
        orch.get(domainTypeA),
        orch.get(domainTypeB),
      ]);

      expect(results, [{'a': true}, {'b': true}]);
      expect(provider.refreshCalls, 1); // 同域共享一把登录锁，只重登一次
      expect(orch.status('domain_test_a')!.connected, isTrue);
      expect(orch.status('domain_test_b')!.connected, isTrue);
    });

    test('不同域各自失效 → 各触发一次重登（域间互不挤占）', () async {
      final provider = InMemorySessionProvider(
        sessionProviderId: 'zju',
        onExpired: (e) => e is _SessionExpired,
        onRefresh: () async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return true;
        },
      );
      coord.registerSessionProvider(provider.sessionProviderId, provider);
      orch.sessionCoordinator = coord;

      var callsA = 0;
      var callsO = 0;
      orch.register(domainTypeA, () async {
        callsA++;
        if (callsA == 1) throw const _SessionExpired();
        return {'a': true};
      });
      orch.register(otherDomainType, () async {
        callsO++;
        if (callsO == 1) throw const _SessionExpired();
        return {'o': true};
      });

      final results = await Future.wait([
        orch.get(domainTypeA),
        orch.get(otherDomainType),
      ]);

      expect(results, [{'a': true}, {'o': true}]);
      expect(provider.refreshCalls, 2); // 两个域各自重登
    });

    test('声明 sessionDomain 但未声明 sessionProvider → 不重登，转同域后台重试', () async {
      // 本地实例用短延迟，避免默认 2s 定时器拖慢测试
      final localOrch = DataOrchestrator(
          domainRetryDelay: const Duration(milliseconds: 20));
      final localCoord = SessionCoordinator();
      final provider = InMemorySessionProvider(
        sessionProviderId: 'zju',
        onExpired: (e) => e is _SessionExpired,
      );
      localCoord.registerSessionProvider(provider.sessionProviderId, provider);
      localOrch.sessionCoordinator = localCoord;

      // 只声明域、无 provider：会话路由无从解析——不走重登，登记同域后台重试
      const domainOnlyType = DataType<Map<String, dynamic>>(
        name: 'domain_only_test',
        category: '测试',
        sessionDomain: 'jwxt.zju.edu.cn',
      );
      var calls = 0;
      localOrch.register(domainOnlyType, () async {
        calls++;
        if (calls == 1) throw const _SessionExpired();
        return {'ok': true};
      });

      final data = await localOrch.get(domainOnlyType);

      expect(data, isNull);
      expect(provider.refreshCalls, 0); // 未走会话重登
      expect(
        localOrch.status('domain_only_test')!.lastError,
        startsWith(kDataFetchFailedPrefix),
      );
      expect(calls, 1); // 后台重试尚未发生（不堵塞）

      // 等待后台重试完成
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(calls, 2);
      expect(localOrch.status('domain_only_test')!.connected, isTrue);
    });

    test('未声明 sessionDomain → 回退按 sessionProviderId 分组（历史一致）', () async {
      final provider = InMemorySessionProvider(
        sessionProviderId: 'zju',
        onExpired: (e) => e is _SessionExpired,
      );
      coord.registerSessionProvider(provider.sessionProviderId, provider);
      orch.sessionCoordinator = coord;

      orch.register(authType, () async => throw const _SessionExpired());

      final data = await orch.get(authType);

      expect(data, isNull);
      expect(provider.refreshCalls, 1); // 按 sessionProviderId='zju' 分组重登
      expect(
        orch.status('auth_test')!.lastError,
        startsWith(kDataReloginRetryFailedPrefix),
      );
    });
  });
}
