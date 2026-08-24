/// PluginReview 审核与评分聚合测试（M5-2 · 纯逻辑）。
import 'package:test/test.dart';

import '../plugin_review.dart';

void main() {
  group('PluginReview.fromJson', () {
    test('正常解析', () {
      final r = PluginReview.fromJson({
        'author': 'u1',
        'stars': 4,
        'comment': '好用',
        'source': 'user',
      });
      expect(r.author, 'u1');
      expect(r.stars, 4);
      expect(r.comment, '好用');
    });

    test('stars 越界 → FormatException', () {
      expect(
        () => PluginReview.fromJson({'author': 'u', 'stars': 0}),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => PluginReview.fromJson({'author': 'u', 'stars': 6}),
        throwsA(isA<FormatException>()),
      );
    });

    test('缺 author → FormatException', () {
      expect(
        () => PluginReview.fromJson({'stars': 3}),
        throwsA(isA<FormatException>()),
      );
    });

    test('缺 stars → FormatException', () {
      expect(
        () => PluginReview.fromJson({'author': 'u'}),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('aggregateReviews', () {
    test('空集合 → ReviewAggregate.empty', () {
      final a = aggregateReviews([]);
      expect(a, ReviewAggregate.empty);
      expect(a.average, isNull);
      expect(a.count, 0);
      expect(a.roundedStars, isNull);
    });

    test('平均分与直方图', () {
      final reviews = [
        PluginReview(author: 'a', stars: 5),
        PluginReview(author: 'b', stars: 3),
        PluginReview(author: 'c', stars: 4),
      ];
      final a = aggregateReviews(reviews);
      expect(a.count, 3);
      expect(a.average, closeTo(4.0, 0.001));
      expect(a.histogram, [0, 0, 1, 1, 1]);
      expect(a.roundedStars, 4);
    });

    test('全 1 星 → rounded=1', () {
      final a = aggregateReviews([
        PluginReview(author: 'a', stars: 1),
        PluginReview(author: 'b', stars: 1),
      ]);
      expect(a.roundedStars, 1);
      expect(a.histogram, [2, 0, 0, 0, 0]);
    });
  });

  group('ReviewRecord.fromJson', () {
    test('approved 记录带聚合', () {
      final r = ReviewRecord.fromJson({
        'pluginId': 'p1',
        'status': 'approved',
        'reason': 'bot-clean',
        'aggregate': {
          'average': 4.5,
          'histogram': [0, 0, 0, 1, 1],
          'count': 2
        },
      });
      expect(r.isExposable, isTrue);
      expect(r.aggregate?.average, 4.5);
    });

    test('缺 pluginId → FormatException', () {
      expect(
        () => ReviewRecord.fromJson({'status': 'approved'}),
        throwsA(isA<FormatException>()),
      );
    });

    test('非法 status → FormatException', () {
      expect(
        () => ReviewRecord.fromJson({'pluginId': 'p', 'status': 'maybe'}),
        throwsA(isA<FormatException>()),
      );
    });

    test('pending/rejected 默认不可暴露', () {
      final pending = ReviewRecord.fromJson(
          {'pluginId': 'p', 'status': 'pending', 'reason': 'new'});
      final rejected = ReviewRecord.fromJson(
          {'pluginId': 'p', 'status': 'rejected', 'reason': 'blocklist'});
      expect(pending.isExposable, isFalse);
      expect(rejected.isExposable, isFalse);
    });
  });

  group('ReviewQueue', () {
    test('仅 approved 进入可暴露白名单', () {
      final q = ReviewQueue();
      q.ingest([
        {'pluginId': 'a', 'status': 'approved', 'reason': 'manual'},
        {'pluginId': 'b', 'status': 'pending', 'reason': 'new'},
        {'pluginId': 'c', 'status': 'rejected', 'reason': 'blocklist'},
      ]);
      final exp = q.exposable();
      expect(exp, hasLength(1));
      expect(exp.first.pluginId, 'a');
    });

    test('重复 id 以最后一条为准', () {
      final q = ReviewQueue();
      q.submit(ReviewRecord.fromJson(
          {'pluginId': 'a', 'status': 'pending', 'reason': 'new'}));
      q.submit(ReviewRecord.fromJson(
          {'pluginId': 'a', 'status': 'approved', 'reason': 'manual'}));
      expect(q.all, hasLength(1));
      expect(q.all.first.isExposable, isTrue);
    });

    test('minStars 门槛过滤', () {
      final q = ReviewQueue();
      q.ingest([
        {
          'pluginId': 'low',
          'status': 'approved',
          'reason': 'm',
          'aggregate': {'average': 2.0, 'histogram': [2, 0, 0, 0, 0], 'count': 2}
        },
        {
          'pluginId': 'high',
          'status': 'approved',
          'reason': 'm',
          'aggregate': {'average': 4.5, 'histogram': [0, 0, 0, 1, 1], 'count': 2}
        },
      ]);
      final exp = q.exposable(minStars: 4.0);
      expect(exp, hasLength(1));
      expect(exp.first.pluginId, 'high');
    });

    test('allows 快速查询', () {
      final q = ReviewQueue();
      q.ingest([
        {'pluginId': 'a', 'status': 'approved', 'reason': 'm'},
      ]);
      expect(q.allows('a'), isTrue);
      expect(q.allows('b'), isFalse);
    });

    test('ingest 非法单条 → 透传 FormatException', () {
      final q = ReviewQueue();
      expect(
        () => q.ingest([
          {'pluginId': 'ok', 'status': 'approved', 'reason': 'm'},
          {'pluginId': 'bad', 'status': 'weird'},
        ]),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('M5-7 ReviewQueue.fromJsonSource', () {
    test('数组形态加载', () {
      final q = ReviewQueue.fromJsonSource('''
        [
          {"pluginId":"a","status":"approved","reason":"m"},
          {"pluginId":"b","status":"pending","reason":"new"}
        ]
      ''');
      expect(q.exposable().map((r) => r.pluginId), ['a']);
    });

    test('records 对象形态加载', () {
      final q = ReviewQueue.fromJsonSource('''
        {"records":[{"pluginId":"x","status":"approved","reason":"m"}]}
      ''');
      expect(q.allows('x'), isTrue);
      expect(q.allows('y'), isFalse);
    });

    test('非法形态 → FormatException', () {
      expect(
        () => ReviewQueue.fromJsonSource('{"foo":1}'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('M5-12 ReviewStore', () {
    test('submitFor 聚合 + 内存累计', () async {
      final store = ReviewStore();
      final a = await store.submitFor(
          'p1', PluginReview(author: 'u1', stars: 5));
      final b = await store.submitFor(
          'p1', PluginReview(author: 'u2', stars: 3));
      expect(a.count, 1);
      expect(b.count, 2);
      expect(b.average, closeTo(4.0, 0.001));
      expect(store.aggregateOf('p1').count, 2);
      expect(store.aggregateOf('p2'), ReviewAggregate.empty);
    });

    test('sink 收到最新评价列表', () async {
      List<Map<String, dynamic>>? captured;
      final store = ReviewStore(
        sink: (id, list) async {
          captured = list;
          expect(id, 'p1');
        },
      );
      await store.submitFor('p1', PluginReview(author: 'u', stars: 4));
      expect(captured, isNotNull);
      expect(captured!.length, 1);
      expect(captured!.first['stars'], 4);
    });

    test('allAggregates 批量导出', () async {
      final store = ReviewStore();
      await store.submitFor('a', PluginReview(author: 'u', stars: 5));
      await store.submitFor('b', PluginReview(author: 'u', stars: 2));
      final all = store.allAggregates();
      expect(all.keys, containsAll(['a', 'b']));
      expect(all['a']!.average, 5.0);
    });
  });
}
