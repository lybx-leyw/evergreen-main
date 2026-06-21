import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:evergreen_multi_tools/core/connectivity/data_status_manager.dart';
import 'package:evergreen_multi_tools/core/storage/database.dart';
import '../../mocks/fake_path_provider.dart';

void main() {
  setUpAll(() {
    PathProviderPlatform.instance = FakePathProviderPlatform();
  });
  group('DataStatusManager', () {
    late DataStatusManager manager;

    setUp(() {
      manager = DataStatusManager();
      manager.registerDefaults();
    });

    test('registerDefaults 注册全部 13 个数据源', () {
      final names = manager.sources.map((s) => s.name).toSet();
      expect(names.length, 13);
      expect(names, contains('ZDBK 成绩'));
      expect(names, isNot(contains('ZDBK 主修成绩')));
      expect(names, contains('ZDBK 考试'));
      expect(names, contains('ZDBK 课表'));
      expect(names, contains('开课情况'));
      expect(names, contains('培养方案'));
      expect(names, contains('教务通知'));
      expect(names, contains('智云课堂'));
      expect(names, contains('学在浙大 课程'));
      expect(names, contains('学在浙大 考试'));
      expect(names, contains('待办事项'));
      expect(names, contains('PTA 编程题'));
      expect(names, contains('DeepSeek API'));
      expect(names, contains('DeepSeek OCR'));
      // 不应包含实践分数
      expect(names, isNot(contains('实践分数')));
    });

    test('按分类分组正确', () {
      final zdBk = manager.byCategory('ZDBK');
      expect(zdBk.length, greaterThan(1));
      expect(zdBk.every((s) => s.category == 'ZDBK'), isTrue);

      final classroom = manager.byCategory('Classroom');
      expect(classroom.length, 1);
      expect(classroom.first.name, '智云课堂');
    });

    test('分类列表不重复', () {
      final cats = manager.categories;
      expect(cats.toSet().length, cats.length);
    });

    test('source() 按名称查找', () {
      final s = manager.source('ZDBK 成绩');
      expect(s, isNotNull);
      expect(s!.name, 'ZDBK 成绩');
      expect(s.cacheKey, 'zdbk_Transcript');

      final missing = manager.source('不存在的源');
      expect(missing, isNull);
    });

    test('初始状态全部 disconnected，从未更新', () {
      for (final s in manager.sources) {
        expect(s.connected, isFalse);
        expect(s.lastFetchedAt, isNull);
        expect(s.isFresh, isFalse);
        expect(s.freshnessLabel, '从未');
      }
    });

    test('连通后手动设置状态', () {
      final s = manager.source('ZDBK 成绩')!;
      s.connected = true;
      s.lastFetchedAt = DateTime.now();

      expect(s.connected, isTrue);
      expect(s.isFresh, isTrue);
      expect(s.freshnessLabel, '新鲜');
    });

    test('过期数据新鲜度标签', () {
      final s = manager.source('ZDBK 成绩')!;
      s.connected = true;
      s.lastFetchedAt = DateTime.now().subtract(const Duration(hours: 2));

      expect(s.isFresh, isFalse);
      expect(s.freshnessLabel, '过期');
    });

    test('connectedCount / freshCount / totalCount', () {
      // 模拟全部连通+新鲜
      for (final s in manager.sources) {
        s.connected = true;
        s.lastFetchedAt = DateTime.now();
      }
      expect(manager.connectedCount, manager.totalCount);
      expect(manager.freshCount, manager.totalCount);

      // 模拟一个断开+过期
      final first = manager.sources.first;
      first.connected = false;
      first.lastFetchedAt = DateTime.now().subtract(const Duration(days: 2));
      expect(manager.connectedCount, manager.totalCount - 1);
      expect(first.freshnessLabel, '过期');
    });

    test('relativeTime 各类时间描述', () {
      final s = manager.source('ZDBK 成绩')!;
      expect(s.relativeTime, '从未更新');

      s.lastFetchedAt = DateTime.now();
      expect(s.relativeTime, '刚刚');

      s.lastFetchedAt = DateTime.now().subtract(const Duration(minutes: 5));
      expect(s.relativeTime, '5 分钟前');

      s.lastFetchedAt = DateTime.now().subtract(const Duration(hours: 3));
      expect(s.relativeTime, '3 小时前');

      s.lastFetchedAt = DateTime.now().subtract(const Duration(days: 2));
      expect(s.relativeTime, '2 天前');
    });

    test('refreshFreshness 无缓存时保持 null', () async {
      final db = await WebCacheDatabase.getInstance();
      manager.refreshFreshness(db);
      final s = manager.source('ZDBK 成绩')!;
      // 未写入过缓存的数据源，时间戳为 null
      expect(s.lastFetchedAt, isNull);
    });

    test('cacheKey=null 数据源 refreshFreshness 后保持 null', () async {
      final db = await WebCacheDatabase.getInstance();
      // 先设置一个假时间戳，模拟 updateDataStatus 后的状态
      final s = manager.source('学在浙大 课程')!;
      s.lastFetchedAt = DateTime.now().subtract(const Duration(minutes: 10));
      expect(s.cacheKey, isNull);

      // refreshFreshness 不应覆盖 cacheKey=null 源的时间戳
      manager.refreshFreshness(db);
      // 保持了上一次 updateDataStatus 设置的值
      expect(s.lastFetchedAt, isNotNull);
    });

    test('cacheKey=null 数据源初始 lastFetchedAt 为 null', () {
      // 从未 updateDataStatus 的 cacheKey=null 源，初始为 null（不是 now）
      final s = manager.source('待办事项')!;
      expect(s.cacheKey, isNull);
      expect(s.lastFetchedAt, isNull);
      expect(s.freshnessLabel, '从未');
    });
  });
}
