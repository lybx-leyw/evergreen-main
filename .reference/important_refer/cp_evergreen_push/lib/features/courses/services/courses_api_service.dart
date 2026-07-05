import 'dart:convert';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/result.dart';
import '../../../core/errors.dart';
import '../../../core/log.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/storage/cache_manager.dart';
import '../models/course.dart';

/// ZJU Courses API Service — wrapper around courses.zju.edu.cn.
///
/// All public methods return [Result<T>] for unified error handling.
class CoursesApiService {
  final Dio _dio;
  final CacheManager _cache;

  CoursesApiService(this._dio, this._cache);

  /// Fetch the list of enrolled courses.
  Future<Result<List<Course>>> getMyCourses() async {
    const cacheKey = 'courses:list';

    if (_cache.isFresh(cacheKey)) {
      final cached = _cache.getJson(cacheKey);
      if (cached is List) {
        return Ok(cached
            .map((e) => Course.fromJson(e as Map<String, dynamic>))
            .toList());
      }
    }

    try {
      final res = await _dio.post(
        'https://courses.zju.edu.cn/api/my-courses',
        options: Options(headers: {'Content-Type': 'application/json'}),
      );
      final data = _safeJsonParse(res, '课程列表');
      final courses = (data['courses'] as List<dynamic>? ?? [])
          .map((e) => Course.fromJson(e as Map<String, dynamic>))
          .toList();
      _cache.setJson(cacheKey, courses.map((c) => c.toJson()).toList());
      return Ok(courses);
    } on Exception catch (e, stack) {
      // 网络失败时回退过期缓存（离线降级）
      final stale = _cache.getJson(cacheKey);
      if (stale is List) {
        Log().info('Courses API: using stale cache for $cacheKey',
            data: {'error': e.toString().substring(0, min(e.toString().length, 100))});
        try {
          return Ok(stale
              .map((c) => Course.fromJson(c as Map<String, dynamic>))
              .toList());
        } catch (_) {}
      }
      return Err(_mapError(e, stack, 'courses.zju.edu.cn'));
    }
  }

  /// Fetch detailed data for a single course.
  Future<Result<CourseFullData>> getCourseFullData(int courseId) async {
    final cacheKey = 'courses:full_data:$courseId';

    // 缓存优先
    if (_cache.isFresh(cacheKey)) {
      final cached = _cache.getJson(cacheKey);
      if (cached is Map) {
        final typed = cached.cast<String, dynamic>();
        return Ok(CourseFullData(
          courseId: courseId,
          activities: (typed['activities'] as List<dynamic>? ?? [])
              .map((e) => e as Map<String, dynamic>)
              .toList(),
        ));
      }
    }

    try {
      final res = await _dio.get(
        'https://courses.zju.edu.cn/api/courses/$courseId/activities',
      );
      final data = _safeJsonParse(res, '课程详情');
      final activities = (data['activities'] as List<dynamic>? ?? [])
          .map((e) => e as Map<String, dynamic>)
          .toList();
      _cache.setJson(cacheKey, {'activities': activities},
          ttl: const Duration(minutes: 5));
      return Ok(CourseFullData(courseId: courseId, activities: activities));
    } on Exception catch (e, stack) {
      // 过期缓存兜底
      final stale = _cache.getJson(cacheKey);
      if (stale is Map) {
        final typed = stale.cast<String, dynamic>();
        return Ok(CourseFullData(
          courseId: courseId,
          activities: (typed['activities'] as List<dynamic>? ?? [])
              .map((e) => e as Map<String, dynamic>)
              .toList(),
        ));
      }
      return Err(_mapError(e, stack, 'courses.zju.edu.cn'));
    }
  }

  /// Fetch exam list across all courses.
  Future<Result<List<Map<String, dynamic>>>> getAllExams() async {
    const cacheKey = 'courses:exams';
    if (_cache.isFresh(cacheKey)) {
      final cached = _cache.getJson(cacheKey);
      if (cached is List) {
        return Ok(cached.cast<Map<String, dynamic>>());
      }
    }

    try {
      final res = await _dio.get('https://courses.zju.edu.cn/api/exams');
      final data = _safeJsonParse(res, '考试列表');
      final exams = (data['exams'] as List<dynamic>? ?? [])
          .map((e) => e as Map<String, dynamic>)
          .toList();
      _cache.setJson(cacheKey, exams, ttl: const Duration(minutes: 10));
      return Ok(exams);
    } on Exception catch (e, stack) {
      // 网络失败时回退过期缓存（离线降级）
      final stale = _cache.getJson(cacheKey);
      if (stale is List) {
        Log().info('Courses API: using stale cache for $cacheKey',
            data: {'error': e.toString().substring(0, min(e.toString().length, 100))});
        return Ok(stale.cast<Map<String, dynamic>>());
      }
      return Err(_mapError(e, stack, 'courses.zju.edu.cn'));
    }
  }

  /// Fetch todo items from courses.zju.edu.cn.
  Future<Result<List<Map<String, dynamic>>>> getTodos() async {
    const cacheKey = 'courses:todos';

    // 缓存优先
    if (_cache.isFresh(cacheKey)) {
      final cached = _cache.getJson(cacheKey);
      if (cached is List) {
        return Ok(cached.cast<Map<String, dynamic>>());
      }
    }

    try {
      final res = await _dio.get('https://courses.zju.edu.cn/api/todos');
      final data = _safeJsonParse(res, '待办列表');
      final todos = (data['todos'] as List<dynamic>? ?? [])
          .map((e) => e as Map<String, dynamic>)
          .toList();
      _cache.setJson(cacheKey, todos, ttl: const Duration(minutes: 5));
      return Ok(todos);
    } catch (_) {
      // 过期缓存兜底
      final stale = _cache.getJson(cacheKey);
      if (stale is List) return Ok(stale.cast<Map<String, dynamic>>());
      return Ok(<Map<String, dynamic>>[]);
    }
  }

  /// Fetch scores for a course.
  Future<Result<ScoresData>> getScoresAll(int courseId) async {
    final cacheKey = 'courses:scores:$courseId';

    // 缓存优先
    if (_cache.isFresh(cacheKey)) {
      final cached = _cache.getJson(cacheKey);
      if (cached is Map) {
        final typed = cached.cast<String, dynamic>();
        return Ok(ScoresData(
          activityReads: typed['activityReads'] as Map<String, dynamic>? ?? {},
          homeworkActivities: typed['homeworkActivities'] as Map<String, dynamic>? ?? {},
          examScores: typed['examScores'] as Map<String, dynamic>? ?? {},
          exams: typed['exams'] as Map<String, dynamic>? ?? {},
        ));
      }
    }

    try {
      final results = await Future.wait([
        _dio
            .get(
                'https://courses.zju.edu.cn/api/courses/$courseId/activities-read-for-user')
            .then((r) => _safeJsonParse(r, '活动阅读')),
        _dio
            .get(
                'https://courses.zju.edu.cn/api/courses/$courseId/homework-scores')
            .then((r) => _safeJsonParse(r, '作业成绩')),
        _dio
            .get(
                'https://courses.zju.edu.cn/api/courses/$courseId/exam-scores')
            .then((r) => _safeJsonParse(r, '考试成绩')),
        _dio
            .get(
                'https://courses.zju.edu.cn/api/courses/$courseId/exams')
            .then((r) => _safeJsonParse(r, '考试安排')),
      ]);
      final data = ScoresData(
        activityReads: results[0],
        homeworkActivities: results[1],
        examScores: results[2],
        exams: results[3],
      );
      _cache.setJson(cacheKey, {
        'activityReads': data.activityReads,
        'homeworkActivities': data.homeworkActivities,
        'examScores': data.examScores,
        'exams': data.exams,
      }, ttl: const Duration(minutes: 5));
      return Ok(data);
    } on Exception catch (e, stack) {
      final stale = _cache.getJson(cacheKey);
      if (stale is Map) {
        final typed = stale.cast<String, dynamic>();
        return Ok(ScoresData(
          activityReads: typed['activityReads'] as Map<String, dynamic>? ?? {},
          homeworkActivities: typed['homeworkActivities'] as Map<String, dynamic>? ?? {},
          examScores: typed['examScores'] as Map<String, dynamic>? ?? {},
          exams: typed['exams'] as Map<String, dynamic>? ?? {},
        ));
      }
      return Err(_mapError(e, stack, 'courses.zju.edu.cn'));
    }
  }

  /// Get classroom list for a course.
  Future<Result<List<Map<String, dynamic>>>> getClassrooms(
      int courseId) async {
    final cacheKey = 'courses:classrooms:$courseId';
    if (_cache.isFresh(cacheKey)) {
      final cached = _cache.getJson(cacheKey);
      if (cached is List) return Ok(cached.cast<Map<String, dynamic>>());
    }
    try {
      final res = await _dio.get(
        'https://courses.zju.edu.cn/api/classrooms',
        queryParameters: {'courseId': courseId},
      );
      final data = _safeJsonParse(res, '课堂列表');
      final list = (data['classrooms'] as List<dynamic>? ?? [])
          .map((e) => e as Map<String, dynamic>)
          .toList();
      _cache.setJson(cacheKey, list, ttl: const Duration(minutes: 5));
      return Ok(list);
    } on Exception catch (e, stack) {
      final stale = _cache.getJson(cacheKey);
      if (stale is List) return Ok(stale.cast<Map<String, dynamic>>());
      return Err(_mapError(e, stack, 'courses.zju.edu.cn'));
    }
  }

  /// Get quiz subjects for a classroom.
  Future<Result<List<Map<String, dynamic>>>> getQuizSubjects(
      int classroomId) async {
    final cacheKey = 'courses:quiz_subjects:$classroomId';
    if (_cache.isFresh(cacheKey)) {
      final cached = _cache.getJson(cacheKey);
      if (cached is List) return Ok(cached.cast<Map<String, dynamic>>());
    }
    try {
      final res = await _dio.get(
        'https://courses.zju.edu.cn/api/classrooms/$classroomId/activities',
      );
      final data = _safeJsonParse(res, '答题列表');
      final list = (data['activities'] as List<dynamic>? ?? [])
          .map((e) => e as Map<String, dynamic>)
          .toList();
      _cache.setJson(cacheKey, list, ttl: const Duration(minutes: 5));
      return Ok(list);
    } on Exception catch (e, stack) {
      final stale = _cache.getJson(cacheKey);
      if (stale is List) return Ok(stale.cast<Map<String, dynamic>>());
      return Err(_mapError(e, stack, 'courses.zju.edu.cn'));
    }
  }

  // ── Internal ───────────────────────────────────────────────────────

  Map<String, dynamic> _safeJsonParse(Response res, String label) {
    final text = res.data is String ? res.data as String : jsonEncode(res.data);
    if (text.trim().startsWith('<')) {
      throw Exception('$label 返回了网页而非数据（可能未登录或不在校园网环境）');
    }
    try {
      if (res.data is Map) return res.data as Map<String, dynamic>;
      return jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('$label 返回了无效数据格式');
    }
  }

  AppError _mapError(Object e, StackTrace? stack, String url) {
    if (e is DioException) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        return AppError.timeout(10, url);
      }
      if (e.type == DioExceptionType.connectionError) {
        return AppError.networkUnreachable(url);
      }
      final status = e.response?.statusCode;
      if (status != null) return AppError.httpStatus(status, url);
    }
    final msg = e.toString();
    if (msg.contains('未登录') || msg.contains('网页而非数据')) {
      return AppError.authFailed('courses.zju.edu.cn 未登录');
    }
    if (msg.contains('无效数据格式')) {
      return AppError.dataIntegrity(
          'courses.zju.edu.cn', 'response', 'JSON', msg);
    }
    Log().error('Courses API error', error: e, stack: stack);
    return AppError.unknown(e);
  }
}

class CourseFullData {
  final int courseId;
  final List<Map<String, dynamic>> activities;
  const CourseFullData({required this.courseId, required this.activities});
}

class ScoresData {
  final Map<String, dynamic> activityReads;
  final Map<String, dynamic> homeworkActivities;
  final Map<String, dynamic> examScores;
  final Map<String, dynamic> exams;
  const ScoresData({
    required this.activityReads,
    required this.homeworkActivities,
    required this.examScores,
    required this.exams,
  });
}

final coursesApiProvider = Provider<CoursesApiService>((ref) {
  final dio = ref.read(dioClientProvider);
  final cache = CacheManager();
  return CoursesApiService(dio, cache);
});
