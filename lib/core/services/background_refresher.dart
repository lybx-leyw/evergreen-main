/// 后台静默刷新器 — 监听 autoRefreshTickProvider，
/// 在后台拉取数据并写入缓存，不影响前端 UI。
///
/// 前端永远读缓存，不会因为后台刷新而显示 loading 状态。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../log.dart';
import '../storage/database.dart';
import '../utils/auto_refresh.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/zdbk/services/zdbk_service.dart';
import '../../features/zdbk/providers/zdbk_provider.dart';
import '../../features/courses/services/courses_api_service.dart';
import '../../features/courses/providers/courses_provider.dart';
import '../../features/classroom/services/classroom_crawler.dart';
import '../../features/classroom/providers/classroom_provider.dart';
import '../config/app_config.dart';
import '../../features/connectivity/providers/connectivity_provider.dart'
    show dataStatusManagerProvider;

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

      final db = WebCacheDatabase.instanceOrNull;

      // 静默拉取 ZDBK 全量数据 — 仅拉取过期或缺失的
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

      final futures = <Future<void>>[];

      // ZDBK 数据：仅拉取不新鲜的
      if (db?.getFreshCachedWebPage('zdbk_Transcript', CacheTtl.transcript) == null) {
        futures.add(service.getTranscript(httpClient).then((_) {}));
      }
      if (db?.getFreshCachedWebPage('zdbk_exams', CacheTtl.exams) == null) {
        futures.add(service.getExams(httpClient).then((_) {}));
      }
      if (db?.getFreshCachedWebPage('zdbk_trainingPlans', CacheTtl.trainingPlans) == null) {
        futures.add(service.getTrainingPlans(httpClient).then((_) {}));
      }
      if (db?.getFreshCachedWebPage('zdbk_notifications', CacheTtl.notifications) == null) {
        futures.add(service.getNotifications(httpClient, studentId).then((_) {}));
      }

      // 逐个学期拉取课表和开课情况（仅过期/缺失的）
      for (final s in semesters) {
        final ttKey = 'zdbk_Timetable${s.year}_${s.semester}';
        if (db?.getFreshCachedWebPage(ttKey, CacheTtl.timetable) == null) {
          futures.add(service.getTimetable(httpClient, year: s.year, semester: s.semester).then((_) {}));
        }
        final coKey = 'zdbk_courseOfferings_${s.year}_${s.semester}';
        if (db?.getFreshCachedWebPage(coKey, CacheTtl.courseOfferings) == null) {
          futures.add(service.getCourseOfferings(httpClient, year: s.year, semester: s.semester).then((_) {}));
        }
      }
      await Future.wait(futures, eagerError: false);

      // 静默拉取学在浙大数据（方法内部已有缓存优先）
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

      // 同步数据状态面板时间戳
      _ref.invalidate(dataStatusManagerProvider);

    } catch (e) {
      Log().debug('BackgroundRefresher: silent refresh error', data: {'error': e.toString()});
    }
  }
}

/// 全局唯一的后台静默刷新器。
final backgroundRefresherProvider = Provider<BackgroundRefresher>((ref) {
  return BackgroundRefresher(ref);
});
