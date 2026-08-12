/// ZJU Courses API Service — courses.zju.edu.cn（学在浙大）。
///
/// B3（2026-08-12）自参考工程
/// `cp_evergreen_push/lib/features/courses/services/courses_api_service.dart` 改造：
/// - 去掉 CacheManager 缓存层（数据中枢 web_cache JSON + TTL 统一接管）；
/// - 去掉 Result 包装（fetcher 契约：直接返回数据或抛异常，中枢捕获置状态）；
/// - 复用 zju_auth 的带 cookie Dio（[ensureZjuSession]，B3 新增）。
///
/// 本 service 只做「取数 + 解析」，无状态、可注入 mock Dio 单测。
library;

import 'dart:convert';

import 'package:dio/dio.dart';

import 'package:evergreen_base/core/log.dart';

import '../models/course.dart';

/// 课程数据服务。
class CoursesApiService {
  final Dio _dio;

  CoursesApiService(this._dio);

  /// 拉取已选课程列表。
  ///
  /// 返回 [ZjuCourse] 列表；失败抛异常（未登录返回网页 / 网络失败 / 数据格式错）。
  Future<List<ZjuCourse>> getMyCourses() async {
    try {
      final res = await _dio.post(
        'https://courses.zju.edu.cn/api/my-courses',
        options: Options(headers: {'Content-Type': 'application/json'}),
      );
      final data = _safeJsonParse(res, '课程列表');
      final list = (data['courses'] as List<dynamic>? ?? [])
          .map((e) => ZjuCourse.fromJson(e as Map<String, dynamic>))
          .toList();
      Log().info('[zju/courses] getMyCourses 成功', data: {'count': list.length});
      return list;
    } on DioException catch (e) {
      throw StateError(_dioError(e, '课程列表'));
    }
  }

  /// 拉取全部课程考试安排（B3-exams 回退源，抄参考 `getAllExams`）。
  ///
  /// 返回原始 JSON 项列表（renderer 侧 [ZjuExam.fromCourses] 解析）；
  /// 失败抛异常（未登录 / 网络失败 / 数据格式错）。
  Future<List<Map<String, dynamic>>> getAllExams() async {
    try {
      final res = await _dio.get('https://courses.zju.edu.cn/api/exams');
      final data = _safeJsonParse(res, '考试列表');
      final list = (data['exams'] as List<dynamic>? ?? [])
          .map((e) => e as Map<String, dynamic>)
          .toList();
      Log().info('[zju/courses] getAllExams 成功', data: {'count': list.length});
      return list;
    } on DioException catch (e) {
      throw StateError(_dioError(e, '考试列表'));
    }
  }

  // ── Internal ───────────────────────────────────────────────────────

  /// 解析 JSON，若返回的是网页（未登录）抛可读异常。
  Map<String, dynamic> _safeJsonParse(Response res, String label) {
    final text = res.data is String ? res.data as String : jsonEncode(res.data);
    if (text.trim().startsWith('<')) {
      throw StateError('$label 返回了网页而非数据——SSO 会话可能已过期，请重新登录');
    }
    try {
      if (res.data is Map) return res.data as Map<String, dynamic>;
      return jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      throw StateError('$label 返回了无效数据格式');
    }
  }

  /// Dio 异常 → 用户可读中文消息。
  String _dioError(DioException e, String label) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return '$label请求超时（courses.zju.edu.cn）';
    }
    if (e.type == DioExceptionType.connectionError) {
      return '无法连接 courses.zju.edu.cn（可能不在校园网环境）';
    }
    final status = e.response?.statusCode;
    if (status != null) return '$label请求失败（HTTP $status）';
    return '$label请求失败：${e.message ?? e.toString()}';
  }
}
