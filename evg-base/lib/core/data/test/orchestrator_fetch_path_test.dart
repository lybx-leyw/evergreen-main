/// DataOrchestrator 数据拉取阶段追踪（T2e）测试——`fetchPathOf`/`fetchPaths`
/// 返回数据源最近一次拉取的阶段轨迹，供 renderer 看板动态流程图消费：
/// - 成功路径：queued→cacheLookup→fetching→validating→caching→done（全部 completed、时间戳递增）
/// - 缓存命中路径：queued→cacheLookup→done（无 fetching）
/// - 失败路径：…→failed（isActive=false）
/// - 同域后台重试期间：failed + isActive=true + retryCount 增长，耗尽后收敛
/// - 从未拉取 fetchPathOf 返回 null；unregister 清理；fetchPaths 全量取全
library;

import 'package:test/test.dart';

import '../orchestrator.dart';
import '../type.dart';
import '../cache.dart';

// 使用唯一前缀避免与其它测试文件的缓存 key 冲突
const _pfx = 'fp_';

const noCacheType = DataType<Map<String, dynamic>>(
  name: '${_pfx}no_cache',
  category: '测试',
  persistentKey: null,
);

const diskType = DataType<Map<String, dynamic>>(
  name: '${_pfx}disk',
  category: '测试',
  ttl: Duration(seconds: 2),
  persistentKey: '${_pfx}disk_cache',
);

const failType = DataType<Map<String, dynamic>>(
  name: '${_pfx}fail',
  category: '测试',
);

const emptyType = DataType<Map<String, dynamic>>(
  name: '${_pfx}empty',
  category: '测试',
);

const fallbackType = DataType<Map<String, dynamic>>(
  name: '${_pfx}fallback',
  category: '测试',
  fallback: {'fb': true},
);

const domainType = DataType<Map<String, dynamic>>(
  name: '${_pfx}domain',
  category: '测试',
  sessionDomain: 'jwxt.zju.edu.cn',
);

const typeA = DataType<Map<String, dynamic>>(
  name: '${_pfx}a',
  category: '测试',
);

const typeB = DataType<Map<String, dynamic>>(
  name: '${_pfx}b',
  category: '测试',
);

class _TestError implements Exception {
  const _TestError();
  @override
  String toString() => 'TestError';
}

List<DataFetchPhase> _phases(DataSourceFetchPath p) =>
    p.steps.map((s) => s.phase).toList();

/// 断言轨迹全部步骤已完成、at 时间戳非降（真实时间，按序递增）、
/// isActive/retryCount 与预期一致。
void _expectSettled(DataSourceFetchPath p,
    {required bool active, required int retryCount}) {
  for (final s in p.steps) {
    expect(s.completed, isTrue, reason: '${s.phase} 应已完成');
    expect(s.at, isNotNull, reason: '${s.phase} 应有真实时间戳');
  }
  for (var i = 1; i < p.steps.length; i++) {
    expect(p.steps[i].at!.compareTo(p.steps[i - 1].at!) >= 0, isTrue,
        reason: '时间戳应递增（第 $i 步不早于第 ${i - 1} 步）');
  }
  expect(p.isActive, active);
  expect(p.retryCount, retryCount);
}

void main() {
  setUp(() async {
    final cache = await Cache.getInstance();
    await cache.clear();
  });

  tearDown(() async {
    final cache = await Cache.getInstance();
    await cache.clear();
  });

  group('成功路径', () {
    test('get 完整拉取链：queued→cacheLookup→fetching→validating→caching→done', () async {
      final orch = DataOrchestrator();
      orch.register(noCacheType, () async => {'value': 1});

      final data = await orch.get(noCacheType);
      expect(data, {'value': 1});

      final p = orch.fetchPathOf('${_pfx}no_cache')!;
      expect(_phases(p), [
        DataFetchPhase.queued,
        DataFetchPhase.cacheLookup,
        DataFetchPhase.fetching,
        DataFetchPhase.validating,
        DataFetchPhase.caching,
        DataFetchPhase.done,
      ]);
      _expectSettled(p, active: false, retryCount: 0);
    });

    test('refresh 链无缓存查找：queued→fetching→validating→caching→done', () async {
      final orch = DataOrchestrator();
      orch.register(noCacheType, () async => {'value': 1});

      await orch.refresh(noCacheType);

      final p = orch.fetchPathOf('${_pfx}no_cache')!;
      expect(_phases(p), [
        DataFetchPhase.queued,
        DataFetchPhase.fetching,
        DataFetchPhase.validating,
        DataFetchPhase.caching,
        DataFetchPhase.done,
      ]);
      _expectSettled(p, active: false, retryCount: 0);
    });

    test('fastRead 内存命中：queued→cacheLookup→done（无 fetching）', () async {
      final orch = DataOrchestrator();
      orch.register(noCacheType, () async => {'value': 1});

      await orch.get(noCacheType); // 写入内存缓存
      await orch.fastRead(noCacheType); // 内存命中

      final p = orch.fetchPathOf('${_pfx}no_cache')!;
      expect(_phases(p), [
        DataFetchPhase.queued,
        DataFetchPhase.cacheLookup,
        DataFetchPhase.done,
      ]);
      _expectSettled(p, active: false, retryCount: 0);
    });
  });

  group('缓存命中路径', () {
    test('get 磁盘命中：queued→cacheLookup→done（无 fetching）', () async {
      final orch = DataOrchestrator();
      orch.register(diskType, () async => {'value': 1});

      // 首次拉取（磁盘未命中）→ 写入磁盘缓存
      await orch.get(diskType);
      expect(Cache.instanceOrNull!.read(diskType.name), isNotNull);
      expect(_phases(orch.fetchPathOf('${_pfx}disk')!).last,
          DataFetchPhase.done);

      // 再次 get：磁盘命中 → 轨迹只含 queued→cacheLookup→done
      await orch.get(diskType);
      final p = orch.fetchPathOf('${_pfx}disk')!;
      expect(_phases(p), [
        DataFetchPhase.queued,
        DataFetchPhase.cacheLookup,
        DataFetchPhase.done,
      ]);
      _expectSettled(p, active: false, retryCount: 0);
    });
  });

  group('失败路径', () {
    test('fetcher 抛异常（无重试）：…→failed，isActive=false', () async {
      final orch = DataOrchestrator();
      orch.register(failType, () async => throw const _TestError());

      final data = await orch.get(failType);
      expect(data, isNull);

      final p = orch.fetchPathOf('${_pfx}fail')!;
      expect(_phases(p), [
        DataFetchPhase.queued,
        DataFetchPhase.cacheLookup,
        DataFetchPhase.fetching,
        DataFetchPhase.failed,
      ]);
      _expectSettled(p, active: false, retryCount: 0);
    });

    test('空数据门控：…→failed，isActive=false（不写缓存）', () async {
      final orch = DataOrchestrator();
      orch.register(emptyType, () async => <String, dynamic>{});

      final data = await orch.get(emptyType);
      expect(data, isNull);

      final p = orch.fetchPathOf('${_pfx}empty')!;
      expect(_phases(p), [
        DataFetchPhase.queued,
        DataFetchPhase.cacheLookup,
        DataFetchPhase.fetching,
        DataFetchPhase.validating,
        DataFetchPhase.failed,
      ]);
      _expectSettled(p, active: false, retryCount: 0);
    });

    test('静态兜底成功返回 → 轨迹收敛 done（兜底也算有结果展示）', () async {
      final orch = DataOrchestrator();
      orch.register(fallbackType, () async => throw const _TestError());

      final data = await orch.get(fallbackType);
      expect(data, {'fb': true});

      final p = orch.fetchPathOf('${_pfx}fallback')!;
      expect(_phases(p).last, DataFetchPhase.done);
      _expectSettled(p, active: false, retryCount: 0);
    });
  });

  group('同域后台重试期间', () {
    test('登记后 failed + isActive=true + retryCount 增长，耗尽后收敛 isActive=false', () async {
      final orch = DataOrchestrator(
        domainRetryDelay: const Duration(milliseconds: 30),
        domainRetryMaxAttempts: 2,
      );
      var calls = 0;
      orch.register(domainType, () async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 120));
        throw const _TestError();
      });

      // 初始拉取失败（t≈120ms）：已登记后台重试 → failed + isActive=true + retryCount=1
      final data = await orch.get(domainType);
      expect(data, isNull);
      var p = orch.fetchPathOf('${_pfx}domain')!;
      expect(_phases(p), [
        DataFetchPhase.queued,
        DataFetchPhase.cacheLookup,
        DataFetchPhase.fetching,
        DataFetchPhase.failed,
      ]);
      _expectSettled(p, active: true, retryCount: 1);

      // t≈220ms：第一轮后台重试拉取进行中（t≈150 开始，t≈270 失败），
      // retryCount 尚未增长（仍 1），轨迹含进行中的 fetching 步骤。
      await Future<void>.delayed(const Duration(milliseconds: 100));
      p = orch.fetchPathOf('${_pfx}domain')!;
      expect(p.isActive, isTrue);
      expect(p.retryCount, 1);
      expect(_phases(p).last, DataFetchPhase.fetching); // 重试拉取进行中
      expect(calls, 2);

      // t≈370ms：第一轮重试失败已重新入队（t≈270），第二轮重试进行中
      // （t≈300 开始，t≈420 失败）→ retryCount 增长到 2。
      await Future<void>.delayed(const Duration(milliseconds: 150));
      p = orch.fetchPathOf('${_pfx}domain')!;
      expect(p.isActive, isTrue);
      expect(p.retryCount, 2);
      expect(_phases(p).last, DataFetchPhase.fetching);
      expect(calls, 3);

      // t≈620ms：第二轮重试失败（attempt=2 ≥ maxAttempts=2）→ 耗尽终结，
      // failed + isActive=false，retryCount 累计保留 2（不再增长）。
      await Future<void>.delayed(const Duration(milliseconds: 250));
      p = orch.fetchPathOf('${_pfx}domain')!;
      expect(_phases(p).last, DataFetchPhase.failed);
      _expectSettled(p, active: false, retryCount: 2);
      expect(calls, 3); // 不再重试
    });

    test('重试耗尽（maxAttempts=3 恒失败）：retryCount 累计至 3，isActive=false', () async {
      final orch = DataOrchestrator(
        domainRetryDelay: const Duration(milliseconds: 20),
        domainRetryMaxAttempts: 3,
      );
      orch.register(domainType, () async => throw const _TestError());

      await orch.get(domainType);
      // 初始失败已登记后台重试：failed + isActive=true + retryCount=1
      expect(orch.fetchPathOf('${_pfx}domain')!.isActive, isTrue);
      expect(orch.fetchPathOf('${_pfx}domain')!.retryCount, 1);

      // 默认 3 次后台重试全部失败（初始 1 + 2 次重新入队 = 3）→ 耗尽
      await Future<void>.delayed(const Duration(milliseconds: 250));
      final p = orch.fetchPathOf('${_pfx}domain')!;
      expect(_phases(p).last, DataFetchPhase.failed);
      _expectSettled(p, active: false, retryCount: 3);

      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(orch.fetchPathOf('${_pfx}domain')!.retryCount, 3); // 不再增长
    });

    test('后台重试成功：轨迹收敛 done，isActive=false，retryCount 累计 1', () async {
      final orch = DataOrchestrator(
        domainRetryDelay: const Duration(milliseconds: 30),
        domainRetryMaxAttempts: 3,
      );
      var calls = 0;
      orch.register(domainType, () async {
        calls++;
        if (calls == 1) throw const _TestError();
        return {'ok': true};
      });

      await orch.get(domainType);
      expect(calls, 1);
      expect(orch.fetchPathOf('${_pfx}domain')!.isActive, isTrue);
      expect(orch.fetchPathOf('${_pfx}domain')!.retryCount, 1);

      // 后台重试成功（t≈30ms 起）→ done + isActive=false
      await Future<void>.delayed(const Duration(milliseconds: 150));
      final p = orch.fetchPathOf('${_pfx}domain')!;
      expect(_phases(p).last, DataFetchPhase.done);
      _expectSettled(p, active: false, retryCount: 1);
      expect(calls, 2);
      expect(orch.status('${_pfx}domain')!.connected, isTrue);
    });
  });

  group('从未拉取 / 注销清理 / 全量', () {
    test('从未拉取：fetchPathOf 返回 null，fetchPaths 为空', () {
      final orch = DataOrchestrator();
      orch.register(noCacheType, () async => {'value': 1});

      expect(orch.fetchPathOf('${_pfx}no_cache'), isNull);
      expect(orch.fetchPathOf('never_fetched'), isNull);
      expect(orch.fetchPaths, isEmpty);
    });

    test('unregister 清理轨迹', () async {
      final orch = DataOrchestrator();
      orch.register(noCacheType, () async => {'value': 1});

      await orch.get(noCacheType);
      expect(orch.fetchPathOf('${_pfx}no_cache'), isNotNull);

      orch.unregister(noCacheType);
      expect(orch.fetchPathOf('${_pfx}no_cache'), isNull);
      expect(orch.fetchPaths, isEmpty);
    });

    test('fetchPaths 全量：多源一次取全，快照不受后续拉取影响', () async {
      final orch = DataOrchestrator();
      orch.register(typeA, () async => {'a': 1});
      orch.register(typeB, () async => {'b': 2});

      await Future.wait([orch.get(typeA), orch.get(typeB)]);

      final all = orch.fetchPaths;
      expect(all.keys, containsAll([typeA.name, typeB.name]));
      expect(all.length, 2);
      expect(_phases(all[typeA.name]!).last, DataFetchPhase.done);
      expect(_phases(all[typeB.name]!).last, DataFetchPhase.done);

      // 快照语义：取回后再拉取不影响旧对象；新轨迹为最新状态
      final snap = all[typeA.name]!;
      await orch.refresh(typeA);
      expect(snap.steps.length, 6); // 旧快照仍是首次 get 的 6 步
      expect(orch.fetchPathOf(typeA.name)!.steps.last.phase,
          DataFetchPhase.done);
    });
  });

  group('序列化与不变类', () {
    test('toJson 结构完整（看板动态解析用）', () async {
      final orch = DataOrchestrator();
      orch.register(noCacheType, () async => {'value': 1});
      await orch.get(noCacheType);

      final json = orch.fetchPathOf('${_pfx}no_cache')!.toJson();
      expect(json['isActive'], isFalse);
      expect(json['retryCount'], 0);
      final steps = json['steps'] as List;
      expect(steps.length, 6);
      final s0 = steps[0] as Map<String, dynamic>;
      expect(s0['phase'], 'queued');
      expect(s0['completed'], isTrue);
      expect(s0['at'], isA<String>()); // ISO8601 字符串
    });

    test('DataSourceFetchStep / DataSourceFetchPath 支持 const 构造（不变类）', () {
      const step =
          DataSourceFetchStep(phase: DataFetchPhase.queued, completed: true);
      expect(step.phase, DataFetchPhase.queued);
      expect(step.completed, isTrue);
      expect(step.at, isNull);

      const path = DataSourceFetchPath(steps: [], isActive: false, retryCount: 0);
      expect(path.isActive, isFalse);
      expect(path.retryCount, 0);
      expect(path.steps, isEmpty);
    });
  });
}
