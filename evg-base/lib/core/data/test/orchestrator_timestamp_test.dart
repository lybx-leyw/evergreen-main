/// DataOrchestrator 时间标签真实性测试（契约②）——前端展示的一定是最新真实的
/// 拉取时间点：
/// - `get` 磁盘命中写内存时使用**磁盘 cachedAt**（内存与磁盘时间标签同步）；
/// - `fastRead` 返回内存条目的 cachedAt（status.lastFetchedAt 同步）；
/// - `refresh` 成功后写入时间为拉取完成时刻；
/// - 磁盘缓存时间标签更新后，内存必须重新拉缓存——内存条目永远用最后一次真实
///   写入磁盘的时间（契约②「缓存更新时间标签后，内存必须重新拉缓存」）。
library;

import 'dart:convert';

import 'package:test/test.dart';

import '../orchestrator.dart';
import '../type.dart';
import '../cache.dart';

const _pfx = 'orch_ts_';

const tsType = DataType<Map<String, dynamic>>(
  name: '${_pfx}test',
  category: '测试',
  ttl: Duration(seconds: 2),
  persistentKey: '${_pfx}test_cache',
);

Future<Map<String, dynamic>> _fetcher() async =>
    {'value': DateTime.now().microsecondsSinceEpoch};

void main() {
  late DataOrchestrator orch;
  late Cache cache;

  setUp(() async {
    cache = await Cache.getInstance();
    await cache.clear();
    orch = DataOrchestrator();
  });

  tearDown(() async {
    orch.stopAutoRefresh();
    await cache.clear();
  });

  group('时间标签真实性（契约②）', () {
    test('get 磁盘命中写内存用磁盘 cachedAt；fastRead/status.lastFetchedAt 与磁盘一致', () async {
      // 先写缓存再建新 orchestrator（模拟重启后首次 get 的磁盘命中路径）
      final orch1 = DataOrchestrator();
      orch1.register(tsType, _fetcher);
      await orch1.refresh(tsType); // 写入磁盘缓存，cachedAt = 本次写入时间
      final diskCachedAt = cache.read(tsType.name)!.$2;
      expect(diskCachedAt.isAfter(DateTime(2026)), isTrue);

      // 新 orchestrator 无内存缓存：get 磁盘命中 → 写内存用磁盘 cachedAt（同一对象）
      final orch2 = DataOrchestrator();
      orch2.register(tsType, _fetcher);
      final data = await orch2.get(tsType);
      expect(data, isNotNull);
      expect(orch2.status(tsType.name)!.lastFetchedAt, diskCachedAt);

      // fastRead 返回内存 cachedAt（与磁盘时间标签一致，不刷新为“现在”）
      final quick = await orch2.fastRead(tsType);
      expect(quick, isNotNull);
      expect(orch2.status(tsType.name)!.lastFetchedAt, diskCachedAt);
    });

    test('refresh 成功后 lastFetchedAt 为拉取完成时刻（而非拉取开始/陈旧时间）', () async {
      // fetcher 带真实耗时（40ms > 粗时钟粒度 ~15.6ms），确保「拉取完成时刻」
      // 与「拉取开始」在墙钟上严格可分（避免同一时钟 tick 内的假相等）。
      orch.register(tsType, () async {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        return {'value': 1};
      });
      final before = DateTime.now();
      await orch.refresh(tsType);
      final after = DateTime.now();

      final t = orch.status(tsType.name)!.lastFetchedAt!;
      expect(t.isAfter(before), isTrue, reason: '时间戳应晚于拉取开始');
      // 完成时刻之后还有落盘/状态簿记，after 可能落在同一粗时钟 tick——用
      // 「不晚于拉取完成」的宽容断言（!t.isAfter(after) ⇔ t <= after）。
      expect(!t.isAfter(after), isTrue, reason: '时间戳不应晚于拉取完成');
    });

    test('磁盘时间标签更新后，get 重新拉缓存（内存与磁盘同步，fastRead 亦同步）', () async {
      orch.register(tsType, _fetcher);
      await orch.refresh(tsType); // t1 写入磁盘 + 内存
      final t1 = cache.read(tsType.name)!.$2;

      // 外部（另一实例/直接 Cache 写）更新缓存内容与时间标签
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await cache.write(tsType.name, jsonEncode({'value': 2}));
      final t2 = cache.read(tsType.name)!.$2;
      expect(t2.isAfter(t1), isTrue);

      // 再次 get：磁盘命中 → 内存条目改用磁盘 cachedAt（t2），而非旧内存 t1
      final data = await orch.get(tsType);
      expect(data, {'value': 2});
      expect(orch.status(tsType.name)!.lastFetchedAt, t2);

      // fastRead 亦返回新时间标签（内存条目已随磁盘同步）
      await orch.fastRead(tsType);
      expect(orch.status(tsType.name)!.lastFetchedAt, t2);
    });
  });
}
