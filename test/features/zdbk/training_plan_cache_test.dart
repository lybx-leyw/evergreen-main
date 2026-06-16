/// 培养方案缓存测试。
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:evergreen_multi_tools/core/storage/database.dart';
import '../../mocks/fake_path_provider.dart';

void main() {
  setUpAll(() {
    PathProviderPlatform.instance = FakePathProviderPlatform();
  });

  group('TrainingPlan 缓存', () {
    test('CacheTtl.trainingPlans 为 24 小时', () {
      expect(CacheTtl.trainingPlans, const Duration(hours: 24));
    });

    test('WebCacheDatabase 读写+时间戳', () async {
      final db = await WebCacheDatabase.getInstance();
      expect(db, isNotNull);
      expect(WebCacheDatabase.instanceOrNull, same(db));

      // getCacheTimestamp 无缓存返回 null
      expect(db.getCacheTimestamp('__nonexistent__'), isNull);

      // 清理
      await db.clearAll();
    });
  });
}
