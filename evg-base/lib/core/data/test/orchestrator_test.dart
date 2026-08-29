/// DataOrchestrator + DataSourceStatus 测试。
///
/// 覆盖：注册/获取/刷新/过期/状态/连通性/异常/批量/自动刷新。

import 'package:test/test.dart';
// 注意：这里精确 import 纯数据层文件，而非 barrel `data.dart`——
// `data.dart` 会 export `data_http_server.dart` / `plugin/data_source_loader.dart`，
// 它们依赖根包（evg-base）的 core 结构（greenix_path / plugin_runner 等），
// 在 data 子包独立 `dart test` 时跨包 import 解析不到，导致编译失败。
import '../orchestrator.dart';
import '../type.dart';
import '../exceptions.dart';
import '../cache.dart';
import '../data_diff.dart';

// ═══════════════════════════════════════════════════════════════════════════
// 测试辅助
// ═══════════════════════════════════════════════════════════════════════════

// 使用唯一前缀避免并行测试时的缓存冲突
const _pfx = 'orch_test_';

const testType = DataType<Map<String, dynamic>>(
  name: '${_pfx}test',
  category: '测试',
  displayName: '测试数据',
  ttl: Duration(seconds: 2),
  persistentKey: '${_pfx}test_cache',
);

const noCacheType = DataType<List<String>>(
  name: '${_pfx}no_cache',
  category: '测试',
  persistentKey: null, // 不持久化
);

int _fetchCount = 0;

Future<Map<String, dynamic>> _fetcher() async {
  _fetchCount++;
  return {'value': _fetchCount, 'ts': DateTime.now().toIso8601String()};
}

void main() {
  late DataOrchestrator orch;

  setUp(() async {
    _fetchCount = 0;
    final cache = await Cache.getInstance();
    await cache.clear();
    orch = DataOrchestrator();
  });

  tearDown(() async {
    orch.stopAutoRefresh();
    final cache = await Cache.getInstance();
    await cache.clear();
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 注册
  // ═══════════════════════════════════════════════════════════════════════

  group('注册', () {
    test('注册后 isRegistered 返回 true', () {
      orch.register(testType, _fetcher);
      expect(orch.isRegistered(testType), isTrue);
    });

    test('未注册时 isRegistered 返回 false', () {
      expect(orch.isRegistered(testType), isFalse);
    });

    test('重复注册同一 name 覆盖旧 fetcher', () {
      orch.register(testType, _fetcher);
      orch.register(testType, () async => {'overridden': true});
      expect(orch.isRegistered(testType), isTrue);
      expect(orch.totalCount, 1);
    });

    test('注册后创建 DataSourceStatus', () {
      orch.register(testType, _fetcher);
      final s = orch.status(testType.name);
      expect(s, isNotNull);
      expect(s!.name, testType.name);
      expect(s.category, '测试');
      expect(s.connected, isFalse);
      expect(s.isFresh, isFalse);
    });

    test('registerAll 批量注册', () {
      const t1 = DataType<dynamic>(name: 't1', category: 'c');
      const t2 = DataType<dynamic>(name: 't2', category: 'c');
      orch.registerAll({
        t1: () async => 'a',
        t2: () async => 'b',
      });
      expect(orch.isRegistered(t1), isTrue);
      expect(orch.isRegistered(t2), isTrue);
      expect(orch.totalCount, 2);
    });

    test('注销后 isRegistered 返回 false', () {
      orch.register(testType, _fetcher);
      orch.unregister(testType);
      expect(orch.isRegistered(testType), isFalse);
      expect(orch.status(testType.name), isNull);
    });

    test('注销未注册类型不抛异常', () {
      orch.unregister(testType);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 获取
  // ═══════════════════════════════════════════════════════════════════════

  group('获取', () {
    test('首次 get 调用 fetcher 返回数据', () async {
      orch.register(testType, _fetcher);
      final data = await orch.get(testType);
      expect(data, isNotNull);
      expect(data!['value'], 1);
    });

    test('有 persistentKey 时 get 走缓存不调 fetcher', () async {
      orch.register(testType, _fetcher);
      final first = await orch.refresh(testType); // 写入缓存
      expect(first, isNotNull);

      // 缓存命中：get 返回相同数据，不重新调用 fetcher
      // （通过验证数据一致性来间接验证缓存命中）
      final cached = await orch.get(testType);
      expect(cached, isNotNull);
      expect(cached!['value'], first!['value']); // 数据一致 = 缓存命中
    });

    test('无 persistentKey 时每次 get 都调 fetcher', () async {
      orch.register(noCacheType, () async {
        _fetchCount++;
        return ['v$_fetchCount'];
      });
      await orch.get(noCacheType);
      expect(_fetchCount, 1);
      await orch.get(noCacheType);
      expect(_fetchCount, 2);
    });

    test('get 未注册类型抛出 DataTypeNotRegisteredException', () {
      expect(
        () => orch.get(testType),
        throwsA(isA<DataTypeNotRegisteredException>()),
      );
    });

    test('fetcher 返回 null 时 get 返回 null', () async {
      orch.register(testType, () async => null as dynamic);
      final data = await orch.get(testType);
      expect(data, isNull);
    });

    test('fetcher 抛异常时 get 返回 null', () async {
      orch.register(testType, () async => throw Exception('网络错误'));
      final data = await orch.get(testType);
      expect(data, isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 刷新
  // ═══════════════════════════════════════════════════════════════════════

  group('刷新', () {
    test('refresh 忽略缓存强制调 fetcher', () async {
      orch.register(testType, _fetcher);
      await orch.refresh(testType); // call 1
      final data = await orch.refresh(testType); // call 2
      expect(data!['value'], 2);
    });

    test('refresh 合法数据覆写缓存', () async {
      orch.register(testType, _fetcher);
      await orch.refresh(testType);
      _fetchCount = 0;
      final data = await orch.get(testType);
      expect(data!['value'], 1);
      expect(_fetchCount, 0);
    });

    test('refresh 返回 null 不覆写缓存', () async {
      orch.register(testType, _fetcher);
      await orch.refresh(testType); // 写入缓存

      // 覆盖为返回 null 的 fetcher
      const nullType = DataType<Map<String, dynamic>>(
        name: '${_pfx}test', // same name as testType
        category: '测试',
        persistentKey: '${_pfx}test_cache',
      );
      orch.register(nullType, () async => null as dynamic);
      final data = await orch.refresh(nullType);
      expect(data, isNull);

      // 旧缓存仍可读 (因为 persistentKey 相同)
    });

    test('invalidate 清除缓存', () async {
      orch.register(testType, _fetcher);
      await orch.refresh(testType);
      await orch.invalidate(testType);
      _fetchCount = 0;
      final data = await orch.get(testType);
      expect(_fetchCount, 1); // 缓存被清，重新拉取
      expect(data!['value'], 1);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 空数据门控：拉取结果为空 → 不覆写缓存（磁盘 + 内存），旧数据保留
  // ═══════════════════════════════════════════════════════════════════════

  group('空数据门控', () {
    test('拉取返回空 Map 不覆写缓存，旧缓存仍可读', () async {
      orch.register(testType, _fetcher);
      await orch.refresh(testType); // 写入非空缓存

      // 覆盖为返回空 Map 的 fetcher（同名同 persistentKey）
      const emptyType = DataType<Map<String, dynamic>>(
        name: '${_pfx}test',
        category: '测试',
        persistentKey: '${_pfx}test_cache',
      );
      orch.register(emptyType, () async => <String, dynamic>{});
      final data = await orch.refresh(emptyType);
      expect(data, isNull); // 空数据被拒

      // 旧缓存仍在：get 返回旧数据且不重新调 fetcher
      _fetchCount = 0;
      final cached = await orch.get(testType);
      expect(cached, isNotNull);
      expect(cached!['value'], 1);
      expect(_fetchCount, 0);
    });

    test('拉取返回空 List 不覆写缓存', () async {
      // 注：用 DataType<dynamic> 规避 _decode 对 List<dynamic>→List<T> 的
      // 既有转换限制（orchestrator.dart _decode 注释），门控本身与 T 无关。
      const listType = DataType<dynamic>(
        name: '${_pfx}list',
        category: '测试',
        persistentKey: '${_pfx}list_cache',
      );
      orch.register(listType, () async => ['a']);
      await orch.refresh(listType);

      orch.register(listType, () async => <String>[]);
      final data = await orch.refresh(listType);
      expect(data, isNull);

      final cached = await orch.get(listType);
      expect(cached, ['a']);
    });

    test('拉取返回空白字符串不覆写缓存', () async {
      const strType = DataType<String>(
        name: '${_pfx}str',
        category: '测试',
        persistentKey: '${_pfx}str_cache',
      );
      orch.register(strType, () async => 'hello');
      await orch.refresh(strType);

      orch.register(strType, () async => '   ');
      final data = await orch.refresh(strType);
      expect(data, isNull);

      final cached = await orch.get(strType);
      expect(cached, 'hello');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 变更通知：后台刷新（notifyOnChange: true）覆写缓存且内容变化时发事件
  // ═══════════════════════════════════════════════════════════════════════

  group('变更通知', () {
    late List<DataChangeEvent> events;

    setUp(() {
      events = [];
      orch.addDataChangeListener(events.add);
    });

    test('首次拉取无基线不发事件；内容变化发事件', () async {
      orch.register(testType, _fetcher);
      await orch.refresh(testType, notifyOnChange: true); // 首次：无旧缓存
      expect(events, isEmpty);

      orch.register(testType, () async => {'value': 99});
      await orch.refresh(testType, notifyOnChange: true); // value 1→99
      expect(events, hasLength(1));
      final e = events.single;
      expect(e.sourceName, testType.name);
      expect(e.displayName, '测试数据');
      expect(e.diff.hasChanges, isTrue);
    });

    test('内容未变不发出事件（含仅易变字段变化）', () async {
      orch.register(testType, () async => {'value': 1});
      await orch.refresh(testType, notifyOnChange: true);
      await orch.refresh(testType, notifyOnChange: true); // 数据相同
      expect(events, isEmpty);

      // 仅 ts 变化 → 不算变更
      orch.register(testType, () async => {'value': 1, 'ts': 'x2'});
      await orch.refresh(testType, notifyOnChange: true);
      expect(events, isEmpty);
    });

    test('默认 notifyOnChange: false 不发事件（用户主动刷新不打扰）', () async {
      orch.register(testType, _fetcher);
      await orch.refresh(testType); // 写入 value=1
      orch.register(testType, () async => {'value': 99});
      await orch.refresh(testType); // 有变化但不通知
      expect(events, isEmpty);
    });

    test('空数据不覆写缓存也不发事件', () async {
      orch.register(testType, _fetcher);
      await orch.refresh(testType, notifyOnChange: true);
      orch.register(testType, () async => <String, dynamic>{});
      await orch.refresh(testType, notifyOnChange: true);
      expect(events, isEmpty);
      // 旧缓存仍在
      final cached = await orch.get(testType);
      expect(cached!['value'], 1);
    });

    test('refreshAllStale 默认发事件（后台循环路径）', () async {
      orch.register(testType, _fetcher);
      await orch.refresh(testType, notifyOnChange: false); // 写入缓存 value=1
      // 标记过期（TTL 2s，直接改时间戳到 10 分钟前）
      orch.status(testType.name)!.debugLastFetchedAt =
          DateTime.now().subtract(const Duration(minutes: 10));

      orch.register(testType, () async => {'value': 100});
      await orch.refreshAllStale(types: [testType]); // 默认 notifyOnChange
      expect(events, hasLength(1));
      expect(events.single.diff.hasChanges, isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 批量刷新
  // ═══════════════════════════════════════════════════════════════════════

  group('refreshAllStale', () {
    test('刷新所有过期数据', () async {
      const fastType = DataType<Map<String, dynamic>>(
        name: 'fast',
        category: '测试',
        ttl: Duration(milliseconds: 1),
        persistentKey: 'fast',
      );
      orch.register(fastType, _fetcher);

      await orch.refresh(fastType);
      await Future.delayed(const Duration(milliseconds: 10));
      _fetchCount = 0;
      await orch.refreshAllStale();
      // 过期数据被刷新
      expect(_fetchCount, greaterThanOrEqualTo(1));
    });

    test('指定 types 过滤刷新范围', () async {
      const t1 = DataType<dynamic>(name: 'r1', category: 'c',
          ttl: Duration(milliseconds: 1), persistentKey: 'r1');
      const t2 = DataType<dynamic>(name: 'r2', category: 'c',
          ttl: Duration(milliseconds: 1), persistentKey: 'r2');

      var c1 = 0, c2 = 0;
      orch.register(t1, () async => 'v${++c1}');
      orch.register(t2, () async => 'v${++c2}');

      await orch.refresh(t1);
      await orch.refresh(t2);
      await Future.delayed(const Duration(milliseconds: 10));

      c1 = 0; c2 = 0;
      await orch.refreshAllStale(types: [t1]);
      // 仅 t1 被刷新
      expect(c1, 1);
      expect(c2, 0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 状态
  // ═══════════════════════════════════════════════════════════════════════

  group('状态', () {
    test('allStatuses 返回所有注册数据源状态', () {
      const t1 = DataType<dynamic>(name: 's1', category: 'A', displayName: '甲');
      const t2 = DataType<dynamic>(name: 's2', category: 'B', displayName: '乙');
      orch.register(t1, () async => 'x');
      orch.register(t2, () async => 'y');

      final list = orch.allStatuses;
      expect(list.length, 2);
      // 按分类排序
      expect(list[0].category, 'A');
      expect(list[1].category, 'B');
    });

    test('categories 返回去重分类列表', () {
      const t1 = DataType<dynamic>(name: 'x1', category: '教务');
      const t2 = DataType<dynamic>(name: 'x2', category: '教务');
      const t3 = DataType<dynamic>(name: 'x3', category: '资讯');
      orch.register(t1, () async => '');
      orch.register(t2, () async => '');
      orch.register(t3, () async => '');

      final cats = orch.categories;
      expect(cats.length, 2);
      expect(cats, contains('教务'));
      expect(cats, contains('资讯'));
    });

    test('statusByCategory 按分类过滤', () {
      const t1 = DataType<dynamic>(name: 'f1', category: '教务');
      const t2 = DataType<dynamic>(name: 'f2', category: '资讯');
      orch.register(t1, () async => '');
      orch.register(t2, () async => '');

      expect(orch.statusByCategory('教务').length, 1);
      expect(orch.statusByCategory('资讯').length, 1);
      expect(orch.statusByCategory('不存在').length, 0);
    });

    test('get 成功后更新状态', () async {
      orch.register(testType, _fetcher);
      await orch.get(testType);

      final s = orch.status(testType.name)!;
      expect(s.connected, isTrue);
      expect(s.lastFetchedAt, isNotNull);
      expect(s.isFresh, isTrue);
      expect(s.freshnessLabel, '新鲜');
    });

    test('get 失败后 connected 为 false', () async {
      orch.register(testType, () async => throw Exception('boom'));
      await orch.get(testType);

      final s = orch.status(testType.name)!;
      expect(s.connected, isFalse);
      expect(s.lastError, isNotNull);
    });

    test('connectedCount / freshCount / totalCount 计数正确', () async {
      const t1 = DataType<Map<String, dynamic>>(
          name: 'cnt1', category: 'c', persistentKey: 'cnt1',
          ttl: Duration(seconds: 2));
      const t2 = DataType<Map<String, dynamic>>(
          name: 'cnt2', category: 'c', persistentKey: 'cnt2',
          ttl: Duration(seconds: 2));

      orch.register(t1, _fetcher);
      orch.register(t2, () async => throw 'fail');

      await orch.refresh(t1);
      await orch.get(t2);

      expect(orch.totalCount, 2);
      expect(orch.connectedCount, 1);
      expect(orch.freshCount, 1);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // DataSourceStatus
  // ═══════════════════════════════════════════════════════════════════════

  group('DataSourceStatus', () {
    test('从未拉取时 freshnessLabel 为 "从未"', () {
      final s = DataSourceStatus(
        name: 'new', category: 'c', displayName: 'd', ttl: Duration(minutes: 5));
      expect(s.freshnessLabel, '从未');
      expect(s.isFresh, isFalse);
      expect(s.relativeTime, '从未更新');
    });

    test('新鲜数据 freshnessLabel 为 "新鲜"', () {
      final s = DataSourceStatus(
        name: 'f', category: 'c', displayName: 'd', ttl: Duration(hours: 1));
      s.debugLastFetchedAt = DateTime.now();
      expect(s.freshnessLabel, '新鲜');
      expect(s.isFresh, isTrue);
    });

    test('过期数据 freshnessLabel 为 "过期"', () {
      final s = DataSourceStatus(
        name: 'e', category: 'c', displayName: 'd', ttl: Duration(seconds: 1));
      s.debugLastFetchedAt = DateTime.now().subtract(const Duration(minutes: 1));
      expect(s.freshnessLabel, '过期');
      expect(s.isFresh, isFalse);
    });

    test('relativeTime 人性化显示', () {
      final s = DataSourceStatus(
        name: 'r', category: 'c', displayName: 'd', ttl: Duration(hours: 1));

      s.debugLastFetchedAt = DateTime.now();
      expect(s.relativeTime, '刚刚');

      s.debugLastFetchedAt = DateTime.now().subtract(const Duration(minutes: 3));
      expect(s.relativeTime, contains('分钟前'));

      s.debugLastFetchedAt = DateTime.now().subtract(const Duration(hours: 2));
      expect(s.relativeTime, contains('小时前'));

      s.debugLastFetchedAt = DateTime.now().subtract(const Duration(days: 3));
      expect(s.relativeTime, contains('天前'));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 连通性
  // ═══════════════════════════════════════════════════════════════════════

  group('连通性', () {
    test('testConnectivity 成功后 connected 为 true', () async {
      orch.register(testType, _fetcher);
      await orch.testConnectivity(testType.name);
      expect(orch.status(testType.name)!.connected, isTrue);
    });

    test('testConnectivity 失败后 connected 为 false', () async {
      orch.register(testType, () async => throw 'offline');
      await orch.testConnectivity(testType.name);
      expect(orch.status(testType.name)!.connected, isFalse);
    });

    test('testAllConnectivity 返回全源结果', () async {
      orch.register(testType, _fetcher);
      const t2 = DataType<dynamic>(name: 'fail_source', category: 'c');
      orch.register(t2, () async => throw 'offline');

      final results = await orch.testAllConnectivity();
      expect(results[testType.name], isTrue);
      expect(results['fail_source'], isFalse);
      expect(results.length, 2);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 自动刷新
  // ═══════════════════════════════════════════════════════════════════════

  group('自动刷新', () {
    test('startAutoRefresh 启动定时器', () {
      orch.register(testType, _fetcher);
      orch.startAutoRefresh(interval: const Duration(minutes: 10));
    });

    test('stopAutoRefresh 停止定时器', () {
      orch.register(testType, _fetcher);
      orch.startAutoRefresh();
      orch.stopAutoRefresh();
    });

    test('未注册类型 stopAutoRefresh 不抛异常', () {
      orch.stopAutoRefresh();
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 时钟对齐自动刷新（T2d 追加）：首 tick 对齐下一刻度、不立即执行；nextRefreshAt
  // ═══════════════════════════════════════════════════════════════════════

  group('时钟对齐自动刷新（T2d 追加）', () {
    test('时钟对齐计算（纯函数）：5m → :05、1h → 整点、30s 秒刻度、边界跳下一刻度', () {
      // 08:03:20：5m 刻度 → 08:05:00（1m40s 后）
      final t1 = DateTime(2026, 8, 29, 8, 3, 20);
      expect(
        DataOrchestrator.durationToNextClockBoundary(
            t1, const Duration(minutes: 5)),
        const Duration(minutes: 1, seconds: 40),
      );
      // 08:03:20：1h 刻度 → 09:00:00（56m40s 后）
      expect(
        DataOrchestrator.durationToNextClockBoundary(
            t1, const Duration(hours: 1)),
        const Duration(minutes: 56, seconds: 40),
      );
      // 08:03:20：30s 刻度 → 08:03:30（10s 后）
      expect(
        DataOrchestrator.durationToNextClockBoundary(
            t1, const Duration(seconds: 30)),
        const Duration(seconds: 10),
      );
      // 恰在边界 08:05:00 → 跳到下一刻度（完整 5m），首 tick 永不立即执行
      final t2 = DateTime(2026, 8, 29, 8, 5);
      expect(
        DataOrchestrator.durationToNextClockBoundary(
            t2, const Duration(minutes: 5)),
        const Duration(minutes: 5),
      );
      // interval <= 0 → 立即
      expect(
        DataOrchestrator.durationToNextClockBoundary(t1, Duration.zero),
        Duration.zero,
      );
    });

    test('首 tick 不对齐立即执行：启动后未立即刷新，约一个刻度后触发并周期延续', () async {
      var fetches = 0;
      const tickType = DataType<Map<String, dynamic>>(
        name: '${_pfx}align',
        category: '测试',
        ttl: Duration(milliseconds: 1), // 恒过期 → 每个 tick 都会刷新
        persistentKey: '${_pfx}align_cache',
      );
      orch.register(tickType, () async {
        fetches++;
        return {'v': fetches};
      });

      orch.startAutoRefresh(interval: const Duration(milliseconds: 100));
      // 立即断言：尚未触发（首 tick 需先对齐到下一刻度，不立即执行）
      expect(fetches, 0);

      // 约一个刻度（首 tick 延迟 ≤100ms）后首个 tick 已触发
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(fetches, greaterThanOrEqualTo(1));

      // periodic 延续：再过约一个刻度再次刷新（相位锁定，不停止）
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(fetches, greaterThanOrEqualTo(2));
    });

    test('nextRefreshAt：启动后非 null 且晚于当前时间；停止后为 null', () async {
      expect(orch.schedulingSnapshot.nextRefreshAt, isNull); // 未启动

      orch.startAutoRefresh(interval: const Duration(minutes: 5));
      final before = DateTime.now();
      final snap = orch.schedulingSnapshot;
      expect(snap.nextRefreshAt, isNotNull);
      expect(snap.nextRefreshAt!.isAfter(before), isTrue);

      orch.stopAutoRefresh();
      expect(orch.schedulingSnapshot.nextRefreshAt, isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // refreshStatusFromDisk
  // ═══════════════════════════════════════════════════════════════════════

  group('refreshStatusFromDisk', () {
    test('从缓存恢复时间戳', () async {
      orch.register(testType, _fetcher);
      await orch.refresh(testType); // 写入缓存

      // 模拟重启：新 orch 读缓存恢复 lastFetchedAt
      final orch2 = DataOrchestrator();
      orch2.register(testType, _fetcher);
      orch2.refreshStatusFromDisk();

      final s = orch2.status(testType.name)!;
      expect(s.lastFetchedAt, isNotNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 空 vs 不可达区分（T4）：源可达但语义空 vs 源不可达/异常，lastError 文案区分
  // ═══════════════════════════════════════════════════════════════════════

  group('空 vs 不可达区分', () {
    test('fetcher 正常返回空 Map → lastError 标「源可达但数据为空」', () async {
      orch.register(testType, () async => <String, dynamic>{});
      await orch.get(testType);

      final s = orch.status(testType.name)!;
      expect(s.connected, isFalse);
      expect(s.lastError, kDataEmptyReachableError);
    });

    test('fetcher 正常返回 null → lastError 标「源可达但数据为空」', () async {
      orch.register(testType, () async => null);
      await orch.get(testType);

      expect(orch.status(testType.name)!.lastError, kDataEmptyReachableError);
    });

    test('fetcher 抛异常（源不可达）→ lastError 标「拉取失败: ...」', () async {
      orch.register(testType, () async => throw Exception('boom'));
      await orch.get(testType);

      final s = orch.status(testType.name)!;
      expect(s.connected, isFalse);
      expect(s.lastError, startsWith(kDataFetchFailedPrefix));
      expect(s.lastError, isNot(kDataEmptyReachableError));
    });

    test('包装了空列表的非空 Map 属可达，正常入缓存不被门控', () async {
      orch.register(testType, () async => {'items': <dynamic>[]});
      final data = await orch.get(testType);

      expect(data, isNotNull);
      expect(data, {'items': <dynamic>[]});
      expect(orch.status(testType.name)!.connected, isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 静态兜底（T4 第三级降级）：拉取失败且无旧缓存 → 返回 fallback + lastError
  // ═══════════════════════════════════════════════════════════════════════

  group('静态兜底', () {
    const fallbackType = DataType<Map<String, dynamic>>(
      name: '${_pfx}fb',
      category: '测试',
      persistentKey: null,
      fallback: {'items': <dynamic>[], 'fromFallback': true},
    );

    test('拉取失败且无旧缓存 → 返回兜底并标记「使用静态兜底」', () async {
      orch.register(fallbackType, () async => throw Exception('down'));
      final data = await orch.get(fallbackType);

      expect(data, isNotNull);
      expect(data!['fromFallback'], isTrue);
      final s = orch.status(fallbackType.name)!;
      expect(s.connected, isFalse);
      expect(s.lastError, startsWith(kDataStaticFallbackPrefix));
    });

    test('拉取返回空且无旧缓存 → 返回兜底', () async {
      orch.register(fallbackType, () async => <String, dynamic>{});
      final data = await orch.get(fallbackType);

      expect(data!['fromFallback'], isTrue);
      expect(orch.status(fallbackType.name)!.lastError,
          startsWith(kDataStaticFallbackPrefix));
    });

    test('有旧缓存时拉取失败 → 保留旧缓存，不使用兜底', () async {
      // 带 persistentKey 的类型：先写入旧缓存，再让 fetcher 失败
      const cachedType = DataType<Map<String, dynamic>>(
        name: '${_pfx}fb_cached',
        category: '测试',
        persistentKey: '${_pfx}fb_cached',
        fallback: {'fromFallback': true},
      );
      orch.register(cachedType, () async => {'value': 1});
      await orch.refresh(cachedType); // 写入旧缓存

      orch.register(cachedType, () async => throw Exception('down'));
      final data = await orch.refresh(cachedType); // 强制刷新失败

      expect(data, isNull); // 无兜底返回，旧缓存保留
      expect(orch.status(cachedType.name)!.lastError,
          startsWith(kDataFetchFailedPrefix));

      // get 走缓存命中，仍返回旧缓存
      final cached = await orch.get(cachedType);
      expect(cached!['value'], 1);
    });

    test('未声明 fallback 的类型行为与历史一致（拉取失败返回 null）', () async {
      orch.register(testType, () async => throw Exception('down'));
      final data = await orch.get(testType);
      expect(data, isNull);
      expect(orch.status(testType.name)!.lastError,
          startsWith(kDataFetchFailedPrefix));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 契约⑤：有真实缓存时永不报错、失败仅警告（T2d）
  // ═══════════════════════════════════════════════════════════════════════

  group('契约⑤：有真实缓存永不报错、失败仅警告', () {
    test('拉取失败但存在旧缓存（磁盘）→ lastError 用警告级文案，get 仍返回缓存数据', () async {
      const cachedType = DataType<Map<String, dynamic>>(
        name: '${_pfx}warn_cached',
        category: '测试',
        persistentKey: '${_pfx}warn_cached',
      );
      orch.register(cachedType, () async => {'value': 1});
      await orch.refresh(cachedType); // 写入真实旧缓存

      orch.register(cachedType, () async => throw Exception('down'));
      final data = await orch.refresh(cachedType); // 强制刷新失败

      expect(data, isNull);
      final s = orch.status(cachedType.name)!;
      expect(s.connected, isFalse);
      expect(s.lastError, startsWith(kDataFetchFailedWithCachePrefix));
      // 非硬错误文案：不出现「拉取失败:」直接标记（区分无缓存路径）
      expect(s.lastError, isNot(startsWith('$kDataFetchFailedPrefix:')));

      // 有真实缓存 → 永不报错：get 仍返回缓存数据（不重新拉取）
      final cached = await orch.get(cachedType);
      expect(cached, {'value': 1});
    });

    test('仅内存缓存（persistentKey 为 null）时拉取失败 → 警告级文案，缓存可读回', () async {
      const memType = DataType<Map<String, dynamic>>(
        name: '${_pfx}warn_mem',
        category: '测试',
        persistentKey: null, // 不落盘，refresh 只写内存
      );
      orch.register(memType, () async => {'value': 1});
      await orch.refresh(memType); // 内存缓存

      orch.register(memType, () async => throw Exception('down'));
      final data = await orch.get(memType); // 无磁盘缓存 → 拉取 → 失败
      expect(data, isNull);
      final s = orch.status(memType.name)!;
      expect(s.connected, isFalse);
      expect(s.lastError, startsWith(kDataFetchFailedWithCachePrefix));

      // readCachedByName 可读回内存缓存（HTTP 端点拉取失败回退缓存数据用）
      final cached = orch.readCachedByName(memType.name);
      expect(cached, isNotNull);
      expect(cached!.$1, {'value': 1});
    });

    test('无缓存且失败 → 保持硬失败文案（真实失败语义，仅此才报错）', () async {
      const freshType = DataType<Map<String, dynamic>>(
        name: '${_pfx}warn_none',
        category: '测试',
        persistentKey: '${_pfx}warn_none',
      );
      orch.register(freshType, () async => throw Exception('down'));
      await orch.get(freshType);

      final s = orch.status(freshType.name)!;
      expect(s.connected, isFalse);
      expect(s.lastError, startsWith(kDataFetchFailedPrefix));
      expect(s.lastError, isNot(startsWith(kDataFetchFailedWithCachePrefix)));
      expect(orch.readCachedByName(freshType.name), isNull);
    });

    test('readCachedByName 读取真实缓存（磁盘优先），cachedAt 与磁盘一致', () async {
      const rType = DataType<Map<String, dynamic>>(
        name: '${_pfx}readc',
        category: '测试',
        persistentKey: '${_pfx}readc',
      );
      orch.register(rType, () async => {'v': 1});
      await orch.refresh(rType);

      final cached = orch.readCachedByName(rType.name);
      expect(cached, isNotNull);
      expect(cached!.$1, {'v': 1});
      expect(cached.$2, Cache.instanceOrNull!.read(rType.name)!.$2);
    });
  });
}
