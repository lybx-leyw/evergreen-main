/// DataOrchestrator 同域后台重试测试（主题 A2）——声明了 `sessionDomain` 但
/// 对应域 provider 不可用（未注册/未声明）时，拉取失败不立即放弃：
/// 立即返回失败（不堵塞调用方/启动期并行拉取），等待 `domainRetryDelay` 后
/// 在后台**串行**重试一次；未声明 sessionDomain 零行为变化。
library;

import 'package:test/test.dart';

import '../orchestrator.dart';
import '../type.dart';
import '../session_provider.dart';

class _FlakyError implements Exception {
  const _FlakyError();
  @override
  String toString() => 'FlakyError';
}

void main() {
  const domainType = DataType<Map<String, dynamic>>(
    name: 'domain_retry',
    category: '测试',
    sessionProviderId: 'zju',
    sessionDomain: 'jwxt.zju.edu.cn',
  );

  const noDomainType = DataType<Map<String, dynamic>>(
    name: 'no_domain_retry',
    category: '测试',
  );

  group('同域后台重试（无对应域 provider）', () {
    test('失败立即返回（不堵塞），延迟后后台串行重试成功', () async {
      final orch = DataOrchestrator(domainRetryDelay: const Duration(milliseconds: 30));

      var calls = 0;
      orch.register(domainType, () async {
        calls++;
        if (calls == 1) throw const _FlakyError();
        return {'ok': true};
      });

      // 首次拉取失败：立即返回 null，不等待重试（不堵塞）
      final data = await orch.get(domainType);
      expect(data, isNull);
      expect(orch.status('domain_retry')!.connected, isFalse);
      expect(calls, 1); // 重试尚未发生

      // 等待后台重试完成后，数据可用
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(calls, 2);
      expect(orch.status('domain_retry')!.connected, isTrue);
      expect(orch.status('domain_retry')!.lastError, isNull);
    });

    test('同域多源失败 → 后台**串行**重试（无并发）', () async {
      final orch = DataOrchestrator(domainRetryDelay: const Duration(milliseconds: 20));

      const typeA = DataType<Map<String, dynamic>>(
        name: 'retry_a',
        category: '测试',
        sessionDomain: 'jwxt.zju.edu.cn',
      );
      const typeB = DataType<Map<String, dynamic>>(
        name: 'retry_b',
        category: '测试',
        sessionDomain: 'jwxt.zju.edu.cn',
      );

      var active = 0;
      var maxActive = 0;
      var callsA = 0;
      var callsB = 0;
      Future<Map<String, dynamic>> flaky(String name) async {
        final entry = name == 'a' ? ++callsA : ++callsB;
        active++;
        if (active > maxActive) maxActive = active;
        await Future<void>.delayed(const Duration(milliseconds: 40));
        active--;
        if (entry == 1) throw const _FlakyError();
        return {name: true};
      }

      orch.register(typeA, () => flaky('a'));
      orch.register(typeB, () => flaky('b'));

      final results = await Future.wait([orch.get(typeA), orch.get(typeB)]);
      expect(results, [null, null]);
      expect(maxActive, 2); // 首次并行拉取本身可并发（启动期并行）

      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(callsA, 2);
      expect(callsB, 2);
      // 重试阶段必须串行：首轮并发结束后 active 已归零，重试逐个执行
      expect(orch.status('retry_a')!.connected, isTrue);
      expect(orch.status('retry_b')!.connected, isTrue);
    });

    test('重试仍失败 → 默认重试 3 次后停止（防无限循环按上限）', () async {
      final orch = DataOrchestrator(domainRetryDelay: const Duration(milliseconds: 20));

      var calls = 0;
      orch.register(domainType, () async {
        calls++;
        throw const _FlakyError();
      });

      await orch.get(domainType);
      expect(calls, 1);

      // 默认 maxAttempts=3：初始 1 次 + 后台串行重试 3 次（每次失败间隔
      // domainRetryDelay 重新入队）→ 共 4 次调用后停止。
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(calls, 4);
      expect(orch.status('domain_retry')!.connected, isFalse);

      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(calls, 4); // 不再增长
    });

    test('重试仍失败 → maxAttempts 可配置：设 2 则重试 2 次后停止', () async {
      final orch = DataOrchestrator(
        domainRetryDelay: const Duration(milliseconds: 20),
        domainRetryMaxAttempts: 2,
      );

      var calls = 0;
      orch.register(domainType, () async {
        calls++;
        throw const _FlakyError();
      });

      await orch.get(domainType);
      expect(calls, 1);

      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(calls, 3); // 初始 1 + 重试 2
      expect(orch.status('domain_retry')!.connected, isFalse);

      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(calls, 3); // 不再增长
    });

    test('重试仍失败 → maxAttempts 设 1 兼容旧「只重试一次」语义', () async {
      final orch = DataOrchestrator(
        domainRetryDelay: const Duration(milliseconds: 20),
        domainRetryMaxAttempts: 1,
      );

      var calls = 0;
      orch.register(domainType, () async {
        calls++;
        throw const _FlakyError();
      });

      await orch.get(domainType);
      expect(calls, 1);

      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(calls, 2); // 初始 1 + 重试 1，到此为止
      expect(orch.status('domain_retry')!.connected, isFalse);

      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(calls, 2); // 不再增长
    });

    test('重试仍失败 → maxAttempts 设 0 完全禁用后台重试', () async {
      final orch = DataOrchestrator(
        domainRetryDelay: const Duration(milliseconds: 20),
        domainRetryMaxAttempts: 0,
      );

      var calls = 0;
      orch.register(domainType, () async {
        calls++;
        throw const _FlakyError();
      });

      await orch.get(domainType);
      expect(calls, 1);

      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(calls, 1); // 无任何后台重试
    });
  });

  group('零行为变化 / 不介入场景', () {
    test('未声明 sessionDomain → 失败不后台重试', () async {
      final orch = DataOrchestrator(domainRetryDelay: const Duration(milliseconds: 20));

      var calls = 0;
      orch.register(noDomainType, () async {
        calls++;
        throw const _FlakyError();
      });

      await orch.get(noDomainType);
      expect(calls, 1);

      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(calls, 1); // 无后台重试
    });

    test('声明 sessionDomain 且对应 provider 可用 → 走会话重登，不后台重试', () async {
      final orch = DataOrchestrator(domainRetryDelay: const Duration(milliseconds: 20));
      final coord = SessionCoordinator();
      final provider = InMemorySessionProvider(
        sessionProviderId: 'zju',
        onExpired: (e) => e is _FlakyError,
        onRefresh: () async => true,
      );
      coord.registerSessionProvider(provider.sessionProviderId, provider);
      orch.sessionCoordinator = coord;

      var calls = 0;
      orch.register(domainType, () async {
        calls++;
        if (calls == 1) throw const _FlakyError();
        return {'ok': true};
      });

      final data = await orch.get(domainType);
      expect(data, {'ok': true});
      expect(calls, 2); // 失败 → 重登 → 重拉，即完成（无需等后台延迟）
      expect(provider.refreshCalls, 1);
    });

    test('声明 sessionDomain 但 coordinator 未设置 → 失败立即返回并后台重试', () async {
      final orch = DataOrchestrator(domainRetryDelay: const Duration(milliseconds: 30));

      var calls = 0;
      orch.register(domainType, () async {
        calls++;
        if (calls == 1) throw const _FlakyError();
        return {'ok': true};
      });

      final data = await orch.get(domainType);
      expect(data, isNull);
      expect(calls, 1);

      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(calls, 2);
      expect(orch.status('domain_retry')!.connected, isTrue);
    });
  });

  group('调度可观测性快照（契约③ 看板支撑）', () {
    test('初始失败入队 → 重试期间 isRetrying=true + lastBackgroundRefreshAt → 结束后还原', () async {
      final orch = DataOrchestrator(
        domainRetryDelay: const Duration(milliseconds: 30),
        domainRetryMaxAttempts: 1, // 单轮重试，时序确定
      );

      var calls = 0;
      orch.register(domainType, () async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 120));
        throw const _FlakyError();
      });

      await orch.get(domainType);
      // 初始失败：已登记待重试，尚未开始重试
      final idle = orch.schedulingSnapshot;
      expect(idle.isRetrying, isFalse);
      expect(idle.pendingRetryNames, contains('domain_retry'));
      expect(idle.lastBackgroundRefreshAt, isNull);

      // 等 Timer 触发（30ms），重试 fetch 进行中（120ms）→ isRetrying=true
      await Future<void>.delayed(const Duration(milliseconds: 80));
      final during = orch.schedulingSnapshot;
      expect(during.isRetrying, isTrue);
      expect(during.lastBackgroundRefreshAt, isNotNull);
      expect(during.domainRetryMaxAttempts, 1);
      expect(during.domainRetryDelay.inMilliseconds, 30);

      // 重试失败且已达上限 → 放弃；快照还原（最近一次时间仍记录）
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final after = orch.schedulingSnapshot;
      expect(after.isRetrying, isFalse);
      expect(after.pendingRetryNames, isEmpty);
      expect(after.lastBackgroundRefreshAt, isNotNull);
      expect(calls, 2); // 初始 1 + 重试 1
    });

    test('重试失败未达上限 → 重新入队，pendingRetryNames 再次可见该 name', () async {
      final orch = DataOrchestrator(
        domainRetryDelay: const Duration(milliseconds: 100),
        domainRetryMaxAttempts: 2,
      );

      var calls = 0;
      orch.register(domainType, () async {
        calls++;
        throw const _FlakyError();
      });

      await orch.get(domainType);
      expect(orch.schedulingSnapshot.pendingRetryNames, contains('domain_retry'));

      // t≈100ms 第一轮重试（瞬间失败）→ 重新入队 → 下一轮 t≈200ms
      await Future<void>.delayed(const Duration(milliseconds: 150));
      final s = orch.schedulingSnapshot;
      expect(s.isRetrying, isFalse); // 两轮之间无重试在执行
      expect(s.pendingRetryNames, contains('domain_retry')); // 未达上限，仍待重试
      expect(s.lastBackgroundRefreshAt, isNotNull);
      expect(calls, 2);

      // t≈200ms 第二轮重试失败 → 达上限放弃
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(calls, 3); // 初始 1 + 2 次重试
      expect(orch.schedulingSnapshot.pendingRetryNames, isEmpty);
      expect(orch.schedulingSnapshot.isRetrying, isFalse);
    });
  });
}
