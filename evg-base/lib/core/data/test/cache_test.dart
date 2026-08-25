/// Cache 持久化缓存测试。
///
/// 覆盖：读写、覆盖、删除、清空、批量写入、不存在 key。

import 'dart:convert';

import 'package:test/test.dart';
import '../cache.dart';

// 使用唯一前缀避免并行测试时的缓存冲突
const _k = 'ct_';

void main() {
  late Cache cache;

  setUp(() async {
    cache = await Cache.getInstance();
    await cache.clear();
  });

  tearDown(() async {
    await cache.clear();
  });

  group('Cache 基本读写', () {
    test('写入后读取返回相同数据', () async {
      await cache.write('${_k}1', 'hello');
      final result = cache.read('${_k}1');
      expect(result, isNotNull);
      expect(result!.$1, 'hello');
    });

    test('读不存在的 key 返回 null', () {
      final result = cache.read('${_k}no_such');
      expect(result, isNull);
    });

    test('覆盖写入返回最新数据', () async {
      await cache.write('${_k}2', 'old');
      await cache.write('${_k}2', 'new');
      final result = cache.read('${_k}2');
      expect(result!.$1, 'new');
    });

    test('写入时间戳不为空', () async {
      await cache.write('${_k}3', 'data');
      final result = cache.read('${_k}3');
      expect(result!.$2, isA<DateTime>());
      expect(result.$2.isAfter(DateTime(2026)), isTrue);
    });
  });

  group('Cache 删除', () {
    test('删除后读取返回 null', () async {
      await cache.write('${_k}4', 'data');
      await cache.evict('${_k}4');
      expect(cache.read('${_k}4'), isNull);
    });

    test('删除不存在的 key 不抛异常', () async {
      await cache.evict('${_k}no_such');
    });

    test('清空后所有数据不可读', () async {
      await cache.write('${_k}5', 'a');
      await cache.write('${_k}6', 'b');
      await cache.clear();
      expect(cache.read('${_k}5'), isNull);
      expect(cache.read('${_k}6'), isNull);
    });
  });

  group('Cache 编码', () {
    test('支持非 ASCII 字符', () async {
      const text = '中文测试 🎉';
      await cache.write('${_k}7', text);
      expect(cache.read('${_k}7')!.$1, text);
    });

    test('支持 JSON 字符串', () async {
      final json = jsonEncode({'a': 1, 'b': [2, 3]});
      await cache.write('${_k}8', json);
      final raw = cache.read('${_k}8')!.$1;
      expect(jsonDecode(raw), {'a': 1, 'b': [2, 3]});
    });

    test('支持空字符串', () async {
      await cache.write('${_k}9', '');
      expect(cache.read('${_k}9')!.$1, '');
    });
  });

  group('Cache 批量', () {
    test('批量写入不同 key 不丢数据', () async {
      for (var i = 0; i < 10; i++) {
        await cache.write('${_k}c$i', 'v$i');
      }
      for (var i = 0; i < 10; i++) {
        final result = cache.read('${_k}c$i');
        expect(result, isNotNull, reason: 'key ${_k}c$i 不应为 null');
        expect(result!.$1, 'v$i');
      }
    });

    test('顺序覆写同一 key 最终一致', () async {
      for (var i = 0; i < 10; i++) {
        await cache.write('${_k}shared', 'v$i');
      }
      final result = cache.read('${_k}shared');
      expect(result, isNotNull);
    });
  });

  group('Cache 并发写（互斥队列）', () {
    test('并发写同一 key 串行落盘，最终为最后写入', () async {
      // 同步依次入队（Future.wait 先求值各 write），互斥队列 FIFO → 最后写入胜出
      final results = await Future.wait([
        cache.write('${_k}cc_same', 'v1'),
        cache.write('${_k}cc_same', 'v2'),
        cache.write('${_k}cc_same', 'v3'),
      ]);
      expect(results, everyElement(isTrue));
      final result = cache.read('${_k}cc_same');
      expect(result, isNotNull);
      expect(result!.$1, 'v3');
    });

    test('并发写不同 key 全部成功且各自可读（无交叉覆写）', () async {
      final results = await Future.wait([
        cache.write('${_k}cc_a', 'a'),
        cache.write('${_k}cc_b', 'b'),
        cache.write('${_k}cc_c', 'c'),
        cache.write('${_k}cc_d', 'd'),
      ]);
      expect(results, everyElement(isTrue));
      expect(cache.read('${_k}cc_a')!.$1, 'a');
      expect(cache.read('${_k}cc_b')!.$1, 'b');
      expect(cache.read('${_k}cc_c')!.$1, 'c');
      expect(cache.read('${_k}cc_d')!.$1, 'd');
    });

    test('并发写与删除混排不抛异常且最终一致', () async {
      await cache.write('${_k}cc_mix', 'keep');
      await Future.wait([
        cache.write('${_k}cc_mix', 'x'),
        cache.write('${_k}cc_mix', 'y'),
        cache.evict('${_k}cc_none'),
      ]);
      // 删除的是不存在的 key，不影响已写 key
      expect(cache.read('${_k}cc_mix'), isNotNull);
    });
  });
}
