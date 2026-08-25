/// DataOrchestrator 流式能力 + 变更事件流桥测试。
///
/// 覆盖：registerStream / streamOf / streamByName / 状态映射（onData/onError/onDone）
/// / 与 pull register 并存 / dataChangeEvents 广播流桥（不双写）。

import 'dart:async';

import 'package:test/test.dart';

// 精确 import 纯数据层文件（同 orchestrator_test.dart 说明）。
import '../orchestrator.dart';
import '../type.dart';
import '../cache.dart';
import '../data_diff.dart';

// ═══════════════════════════════════════════════════════════════════════════
// 测试辅助
// ═══════════════════════════════════════════════════════════════════════════

const _pfx = 'stream_test_';

const streamType = DataType<int>(
  name: '${_pfx}stream',
  category: '流式',
  displayName: '流式数据',
);

const pullType = DataType<Map<String, dynamic>>(
  name: '${_pfx}pull',
  category: '测试',
  displayName: '测试数据',
  persistentKey: '${_pfx}pull_cache',
);

int _fetchCount = 0;

Future<Map<String, dynamic>> _fetcher() async {
  _fetchCount++;
  return {'value': _fetchCount};
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
  // 流式注册与访问
  // ═══════════════════════════════════════════════════════════════════════

  group('流式注册与访问', () {
    test('registerStream 注册后进入注册表（status/typeByName/isRegistered）', () {
      orch.registerStream(streamType, () => Stream.fromIterable([1]));
      expect(orch.isRegistered(streamType), isTrue);
      expect(orch.typeByName(streamType.name), isNotNull);
      final s = orch.status(streamType.name);
      expect(s, isNotNull);
      expect(s!.name, streamType.name);
      expect(s.category, '流式');
      expect(s.connected, isFalse); // 尚未有流事件
      expect(s.completed, isFalse);
      expect(orch.registeredTypes, contains(streamType.name));
    });

    test('streamOf 返回非 null；streamByName 同', () {
      orch.registerStream(streamType, () => Stream.fromIterable([1]));
      expect(orch.streamOf(streamType), isNotNull);
      expect(orch.streamByName(streamType.name), isNotNull);
    });

    test('未注册流式类型 streamOf/streamByName 返回 null', () {
      expect(orch.streamOf(streamType), isNull);
      expect(orch.streamByName('不存在的流'), isNull);
    });

    test('register（pull）与 registerStream 并存（同名互不覆盖）', () async {
      orch.register(pullType, () async => {'v': 1});
      orch.registerStream(pullType, () => Stream.fromIterable([{'s': 1}]));

      // pull 仍可用
      final data = await orch.get(pullType);
      expect(data!['v'], 1);

      // 流式也可用
      final s = orch.streamOf(pullType)!;
      expect(await s.toList(), [
        {'s': 1}
      ]);
    });

    test('注销后流式注册一并清除', () {
      orch.registerStream(streamType, () => Stream.fromIterable([1]));
      orch.unregister(streamType);
      expect(orch.isRegistered(streamType), isFalse);
      expect(orch.status(streamType.name), isNull);
      expect(orch.streamByName(streamType.name), isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 状态映射（onData / onError / onDone）
  // ═══════════════════════════════════════════════════════════════════════

  group('流事件 → 状态映射', () {
    test('onData → connected=true（并刷新 lastFetchedAt）', () async {
      orch.registerStream(streamType, () => Stream.fromIterable([1, 2, 3]));
      final values = await orch.streamOf(streamType)!.toList();
      expect(values, [1, 2, 3]);
      final s = orch.status(streamType.name)!;
      expect(s.connected, isTrue);
      expect(s.lastFetchedAt, isNotNull);
      expect(s.completed, isTrue); // 有限流结束后 onDone 也标记完成
    });

    test('onError → connected=false + lastError', () async {
      orch.registerStream(streamType, () => Stream<int>.error(Exception('boom')));
      Object? caught;
      try {
        await orch.streamOf(streamType)!.drain();
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<Exception>());
      final s = orch.status(streamType.name)!;
      expect(s.connected, isFalse);
      expect(s.lastError, contains('boom'));
    });

    test('onDone → completed=true 且不注销（类型仍在注册表）', () async {
      orch.registerStream(streamType, () => Stream.fromIterable([1]));
      await orch.streamOf(streamType)!.drain();
      final s = orch.status(streamType.name)!;
      expect(s.completed, isTrue);
      // 不注销
      expect(orch.status(streamType.name), isNotNull);
      expect(orch.isRegistered(streamType), isTrue);
      expect(orch.streamOf(streamType), isNotNull);
    });

    test('每次 streamOf 经流工厂取新流（计数验证）', () async {
      var factories = 0;
      orch.registerStream(streamType, () {
        factories++;
        return Stream.fromIterable([factories]);
      });
      expect(await orch.streamOf(streamType)!.toList(), [1]);
      expect(await orch.streamOf(streamType)!.toList(), [2]);
      expect(factories, 2);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 变更事件流桥（dataChangeEvents）
  // ═══════════════════════════════════════════════════════════════════════

  group('dataChangeEvents 广播流桥', () {
    test('diff 通知转发到广播流（首次无基线不发）', () async {
      final events = <DataChangeEvent>[];
      final sub = orch.dataChangeEvents.listen(events.add);

      orch.register(pullType, _fetcher);
      await orch.refresh(pullType, notifyOnChange: true); // 首次：无基线
      expect(events, isEmpty);

      orch.register(pullType, () async => {'value': 99});
      await orch.refresh(pullType, notifyOnChange: true); // 1 → 99
      expect(events, hasLength(1));
      expect(events.single.sourceName, pullType.name);
      expect(events.single.diff.hasChanges, isTrue);

      await sub.cancel();
    });

    test('addDataChangeListener 与 dataChangeEvents 共享同一通知源（不双写/不二次计算）',
        () async {
      final callbacks = <DataChangeEvent>[];
      final streamEvents = <DataChangeEvent>[];
      orch.addDataChangeListener(callbacks.add);
      final sub = orch.dataChangeEvents.listen(streamEvents.add);

      orch.register(pullType, _fetcher);
      await orch.refresh(pullType, notifyOnChange: true);
      orch.register(pullType, () async => {'value': 7});
      await orch.refresh(pullType, notifyOnChange: true);

      expect(callbacks, hasLength(1));
      expect(streamEvents, hasLength(1));
      // 同一事件对象被同时转发给回调和流（内部转发，非两份独立计算）
      expect(identical(callbacks.single, streamEvents.single), isTrue);

      await sub.cancel();
    });

    test('无变化不发事件（广播流同样静默）', () async {
      final events = <DataChangeEvent>[];
      final sub = orch.dataChangeEvents.listen(events.add);

      orch.register(pullType, () async => {'value': 1});
      await orch.refresh(pullType, notifyOnChange: true);
      await orch.refresh(pullType, notifyOnChange: true); // 相同数据
      expect(events, isEmpty);

      await sub.cancel();
    });
  });
}
