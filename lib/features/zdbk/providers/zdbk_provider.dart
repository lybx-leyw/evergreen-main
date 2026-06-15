import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/result.dart';
import '../../../core/errors.dart';
import '../../../core/log.dart';
import '../../../core/storage/database.dart';
import '../../../core/models/grade.dart';
import '../../../core/models/course_offering.dart';
import '../../../core/models/training_plan.dart';
import '../../../core/models/timetable_session.dart';
import '../services/zdbk_service.dart';
import '../../auth/providers/auth_provider.dart';

/// Provider for ZDBK service instance.
final zdbkServiceInstanceProvider = FutureProvider<ZdbkService>((ref) async {
  final db = await WebCacheDatabase.getInstance();
  return ZdbkService(db);
});

/// 缓存上次成功加载的 EverythingResult（供离线降级使用）。
final zdbkEverythingCacheProvider =
    StateProvider<EverythingResult?>((_) => null);

/// Provider for "everything" (grades + exams + GPA).
///
/// 成功时写入缓存，失败时返回缓存数据（如有）。
final zdbkEverythingProvider =
    FutureProvider<Result<EverythingResult>>((ref) async {
  final service = await ref.read(zdbkServiceInstanceProvider.future);
  final auth = ref.watch(authProvider);
  final httpClient = ref.read(httpClientProvider);

  if (!auth.isLoggedIn || auth.ssoCookie == null) {
    return Err(AppError.configMissing('学号和密码')
      ..recoveryHint = '请先在设置中配置学号和密码');
  }

  if (!service.isLoggedIn) {
    await service.login(httpClient, auth.ssoCookie!);
  }

  final result = await service.getEverything(httpClient);
  return result.fold(
    (data) {
      ref.read(zdbkEverythingCacheProvider.notifier).state = data;
      return Ok(data);
    },
    (error) {
      final cached = ref.read(zdbkEverythingCacheProvider);
      if (cached != null) {
        Log().warn('ZDBK fetch failed, using cached data',
            data: {'error': error.userMessage});
        return Ok(cached);
      }
      return Err(error);
    },
  );
});

/// Provider for transcript grades only.
final zdbkTranscriptProvider =
    FutureProvider<Result<List<Grade>>>((ref) async {
  final service = await ref.read(zdbkServiceInstanceProvider.future);
  final auth = ref.watch(authProvider);
  final httpClient = ref.read(httpClientProvider);

  if (!auth.isLoggedIn || auth.ssoCookie == null) {
    return Err(AppError.configMissing('学号和密码')
      ..recoveryHint = '请先在设置中配置学号和密码');
  }

  if (!service.isLoggedIn) {
    await service.login(httpClient, auth.ssoCookie!);
  }

  return service.getTranscript(httpClient);
});

/// Provider for ZDBK exams.
///
/// watch authProvider 确保在登录完成后重新执行。
/// service.getExams 内部通过 _withAutoRelogin 处理登录失效重试。
final zdbkExamsProvider =
    FutureProvider<Result<List<Map<String, dynamic>>>>((ref) async {
  // watch auth 状态：登录变化时重新拉取考试数据
  final auth = ref.watch(authProvider);
  if (!auth.isLoggedIn) {
    return Err(AppError.configMissing('学号和密码')
      ..recoveryHint = '请先登录统一认证');
  }
  if (auth.ssoCookie == null) {
    return Err(AppError.configMissing('SSO Cookie')
      ..recoveryHint = '请先完成统一认证登录');
  }

  final service = await ref.read(zdbkServiceInstanceProvider.future);
  final httpClient = ref.read(httpClientProvider);

  if (!service.isLoggedIn) {
    await service.login(httpClient, auth.ssoCookie!);
  }

  return service.getExams(httpClient);
});

/// Provider for course offerings (开课情况).
final courseOfferingsProvider = FutureProvider.family<
    Result<List<CourseOffering>>,
    ({int year, int semester})>((ref, params) async {
  Log().debug('courseOfferingsProvider',
      data: {'year': params.year, 'semester': params.semester});

  final service = await ref.read(zdbkServiceInstanceProvider.future);
  final auth = ref.watch(authProvider);
  final httpClient = ref.read(httpClientProvider);

  if (!auth.isLoggedIn || auth.ssoCookie == null) {
    return Err(AppError.configMissing('学号和密码')
      ..recoveryHint = '请先在设置中配置学号和密码');
  }

  if (!service.isLoggedIn) {
    Log().debug('ZDBK not logged in, logging in…');
    await service.login(httpClient, auth.ssoCookie!);
  }

  return service.getCourseOfferings(httpClient,
      year: params.year, semester: params.semester);
});

/// Provider for training plans (培养方案), keyed by grade (0 = all).
final trainingPlansProvider = FutureProvider.family<
    Result<List<TrainingPlan>>,
    int>((ref, grade) async {
  Log().debug('trainingPlansProvider', data: {'grade': grade});

  final service = await ref.read(zdbkServiceInstanceProvider.future);
  final auth = ref.watch(authProvider);
  final httpClient = ref.read(httpClientProvider);

  if (!auth.isLoggedIn || auth.ssoCookie == null) {
    return Err(AppError.configMissing('学号和密码')
      ..recoveryHint = '请先在设置中配置学号和密码');
  }

  if (!service.isLoggedIn) {
    Log().debug('ZDBK not logged in, logging in…');
    await service.login(httpClient, auth.ssoCookie!);
  }

  final result = await service.getTrainingPlans(httpClient, grade: grade);
  return result.fold(
    (items) {
      // 诊断：打印第一条的字段名，用于调试 API 字段映射
      if (items.isNotEmpty) {
        Log().debug('TrainingPlan sample keys',
            data: {'keys': items.first.keys.join(', ')});
      }
      final plans = items
          .map((e) => TrainingPlan.fromJson(e))
          .toList();
      return Ok(plans);
    },
    (error) => Err(error),
  );
});

/// 计算当前学年和学期码（与 GetCurrentSemesterTool 逻辑一致）。
({int year, int semester}) _currentSemester() {
  final now = DateTime.now();
  final month = now.month;
  final isAutumnWinter = month >= 9 || month <= 2;
  final year = isAutumnWinter ? now.year : now.year - 1;
  final semester = isAutumnWinter ? 3 : 12;
  return (year: year, semester: semester);
}

/// Provider for ZDBK course timetable — 自动检测当前学期（供 Agent 使用）。
final zdbkTimetableProvider =
    FutureProvider<Result<List<TimetableSession>>>((ref) async {
  final sem = _currentSemester();
  return ref.read(
      zdbkTimetableBySemesterProvider('${sem.year}-${sem.semester}').future);
});

/// Provider for ZDBK course timetable — 指定学年学期（字符串 key 避免 record 比较问题）。
final zdbkTimetableBySemesterProvider =
    FutureProvider.family<Result<List<TimetableSession>>, String>(
    (ref, key) async {
  final parts = key.split('-');
  final year = int.parse(parts[0]);
  final semester = parts.length > 1 ? int.parse(parts[1]) : 12;

  final auth = ref.watch(authProvider);
  if (!auth.isLoggedIn) {
    return Err(AppError.configMissing('学号和密码')
      ..recoveryHint = '请先登录统一认证');
  }

  Log().debug('zdbkTimetableBySemester',
      data: {'year': year, 'semester': semester});

  final service = await ref.read(zdbkServiceInstanceProvider.future);
  final httpClient = ref.read(httpClientProvider);

  return service.getTimetable(httpClient,
      year: year, semester: semester);
});
