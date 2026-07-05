/// Agent 缓存优先数据源测试。
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:evergreen_multi_tools/features/agent/providers/agent_provider.dart';
import 'package:evergreen_multi_tools/core/storage/database.dart';
import 'package:evergreen_multi_tools/core/storage/cache_manager.dart';

/// 辅助 Provider：在 Riverpod 上下文中创建 FlutterZjuDataSource。
final _testDsProvider = Provider<FlutterZjuDataSource>((ref) {
  return FlutterZjuDataSource(ref, null, CacheManager());
});

void main() {
  group('Agent 缓存优先读取', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    FlutterZjuDataSource ds() => container.read(_testDsProvider);

    test('getCourses 无缓存返回空列表', () async {
      final courses = await ds().getCourses();
      expect(courses, isEmpty);
    });

    test('getExams 无缓存返回空列表', () async {
      final exams = await ds().getExams();
      expect(exams, isEmpty);
    });

    test('getScores 无缓存返回 null', () async {
      final scores = await ds().getScores();
      expect(scores, isNull);
    });

    test('getTimetable 无缓存返回空列表', () async {
      final timetable = await ds().getTimetable();
      expect(timetable, isEmpty);
    });

    test('getNotifications 无缓存返回空列表', () async {
      final notifications = await ds().getNotifications();
      expect(notifications, isEmpty);
    });

    test('getCourseOfferings 无缓存返回空列表', () async {
      final offerings = await ds().getCourseOfferings();
      expect(offerings, isEmpty);
    });

    test('getTrainingPlans 无缓存返回空 Ok', () async {
      final result = await ds().getTrainingPlans(0);
      expect(result.isOk, isTrue);
    });

    test('getClassroomCourses 无 Provider 数据返回空列表', () async {
      final courses = await ds().getClassroomCourses();
      expect(courses, isEmpty);
    });

    test('getEcardBalance 无 Provider 数据返回 null', () async {
      final balance = await ds().getEcardBalance();
      expect(balance, isNull);
    });
  });
}
