/// 后台静默刷新器 — 监听 autoRefreshTickProvider，
/// 在后台拉取数据并写入缓存，不影响前端 UI。
///
/// 前端永远读缓存，不会因为后台刷新而显示 loading 状态。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../log.dart';
import '../utils/auto_refresh.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/zdbk/services/zdbk_service.dart';
import '../../features/zdbk/providers/zdbk_provider.dart';
import '../../features/courses/services/courses_api_service.dart';
import '../../features/courses/providers/courses_provider.dart';
import '../../features/classroom/services/classroom_crawler.dart';
import '../../features/classroom/providers/classroom_provider.dart';
import '../config/app_config.dart';

/// 后台静默刷新逻辑。
class BackgroundRefresher {
  final Ref _ref;

  BackgroundRefresher(this._ref) {
    _ref.listen<int>(autoRefreshTickProvider, (prev, tick) {
      _onTick();
    });
  }

  void _onTick() {
    Log().debug('BackgroundRefresher: tick');
    // 异步静默刷新，不阻塞 UI
    _silentRefresh();
  }

  Future<void> _silentRefresh() async {
    try {
      final auth = _ref.read(authProvider);
      if (!auth.isLoggedIn || auth.ssoCookie == null) return;

      final service = await _ref.read(zdbkServiceInstanceProvider.future);
      final httpClient = _ref.read(httpClientProvider);

      if (!service.isLoggedIn) {
        await service.login(httpClient, auth.ssoCookie!);
      }

      // 静默拉取 ZDBK 全量数据
      final now = DateTime.now();
      final isAW = now.month >= 9 || now.month <= 2;
      final currentYear = isAW ? now.year : now.year - 1;
      final studentId = AppConfig.zjuUsername ?? '';

      // 课表 + 开课情况：拉取所有能拉到的学年（向前回溯 8 年，覆盖全部可能学籍）
      final semesters = <({int year, int semester})>[];
      for (int y = currentYear + 1; y >= currentYear - 6; y--) {
        semesters.add((year: y, semester: 3));
        semesters.add((year: y, semester: 12));
      }

      final futures = <Future<void>>[
        service.getTranscript(httpClient).then((_) {}),
        service.getMajorGrade(httpClient).then((_) {}),
        service.getExams(httpClient).then((_) {}),
        service.getTrainingPlans(httpClient).then((_) {}),
        service.getNotifications(httpClient, studentId).then((_) {}),
      ];
      // 逐个学期拉取课表和开课情况
      for (final s in semesters) {
        futures.add(service.getTimetable(httpClient, year: s.year, semester: s.semester).then((_) {}));
        futures.add(service.getCourseOfferings(httpClient, year: s.year, semester: s.semester).then((_) {}));
      }
      await Future.wait(futures, eagerError: false);

      // 静默拉取学在浙大数据
      final coursesApi = _ref.read(coursesApiProvider);
      await Future.wait([
        coursesApi.getMyCourses().then((_) {}),
        coursesApi.getAllExams().then((_) {}),
      ], eagerError: false);

      // 静默拉取智云课堂课程列表
      try {
        final classroomCrawler = _ref.read(classroomCrawlerProvider);
        await classroomCrawler.listCourses().then((_) {});
      } catch (_) {}

    } catch (e) {
      Log().debug('BackgroundRefresher: silent refresh error', data: {'error': e.toString()});
    }
  }
}

/// 全局唯一的后台静默刷新器。
final backgroundRefresherProvider = Provider<BackgroundRefresher>((ref) {
  return BackgroundRefresher(ref);
});
