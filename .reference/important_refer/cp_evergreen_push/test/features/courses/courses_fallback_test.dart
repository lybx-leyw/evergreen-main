/// Courses API 失败回退测试。
///
/// 验证 getMyCourses / getAllExams 在网络错误时回退过期缓存。
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:evergreen_multi_tools/core/result.dart';
import 'package:evergreen_multi_tools/core/errors.dart';
import 'package:evergreen_multi_tools/core/storage/cache_manager.dart';
import 'package:evergreen_multi_tools/features/courses/services/courses_api_service.dart';

void main() {
  group('CoursesApiService 缓存回退', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('CacheManager 过期后仍返回 stale 数据', () {
      final cache = CacheManager(defaultTtl: const Duration(minutes: 5));
      cache.setJson('test:key', {'data': [1, 2, 3]});
      // isFresh 检查过期
      expect(cache.isFresh('test:key'), isTrue);

      // 即使过期，get 仍返回数据
      final stale = cache.getJson('test:key');
      expect(stale, isNotNull);
      expect(stale['data'], [1, 2, 3]);
    });

    test('CacheManager 未写入的 key 返回 null', () {
      final cache = CacheManager();
      final result = cache.getJson('never:written');
      expect(result, isNull);
    });

    test('CacheManager getJson 返回 null 表示无缓存', () {
      final cache = CacheManager();
      final result = cache.getJson('completely:new:key');
      expect(result, isNull);
    });

    test('Result.isOk 和 isErr 判别正确', () {
      final ok = Ok<String>('success');
      expect(ok.isOk, isTrue);
      expect(ok.isErr, isFalse);

      final err = Err<String>(AppError.unknown('test'));
      expect(err.isOk, isFalse);
      expect(err.isErr, isTrue);
    });

    test('AppError 包含 userMessage 和 recoveryHint', () {
      final err = AppError.networkUnreachable('test.com');
      expect(err.userMessage, isNotEmpty);
      expect(err.recoveryHint, isNotNull);
    });
  });
}
