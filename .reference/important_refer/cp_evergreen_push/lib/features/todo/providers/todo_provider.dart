import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/result.dart';
import '../../../core/log.dart';
import '../../../core/config/app_config.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/storage/database.dart';
import '../../../features/courses/models/course.dart';
import '../../../features/courses/services/courses_api_service.dart';
import '../../../features/courses/providers/courses_provider.dart';
import '../../pintia/services/pintia_service.dart';
import '../services/todo_service.dart';

/// PTA 状态——已连接 / 需要登录 / 未配置。
final ptaStatusProvider = FutureProvider<String>((ref) async {
  final session = AppConfig.ptaSession;
  final jar = ref.read(cookieJarProvider);
  final dio = ref.read(dioClientProvider);
  final service = PintiaService(dio, jar);

  // 尝试从配置注入 session
  if (session != null && session.isNotEmpty) {
    await service.setSessionCookie(session);
  }

  final cached = await service.getCachedSession();
  if (cached != null && await service.hasValidSession()) {
    return '已连接';
  }
  return session != null && session.isNotEmpty ? '需要登录' : '未配置';
});

/// PTA Service Provider——使用配置中的 PTASession（需手动设置）。
final pintiaServiceProvider = FutureProvider<PintiaService?>((ref) async {
  final session = AppConfig.ptaSession;
  final dio = ref.read(dioClientProvider);
  final jar = ref.read(cookieJarProvider);
  final service = PintiaService(dio, jar);

  // 从配置注入 cookie
  if (session != null && session.isNotEmpty) {
    await service.setSessionCookie(session);
  }

  // 检查 session 是否有效
  final cached = await service.getCachedSession();
  if (cached != null) {
    final valid = await service.hasValidSession();
    if (valid) {
      Log().info('PTA reuse cached session');
      return service;
    }
  }

  // session 无效，返回 service（用户需在设置中更新 PTASession）
  Log().warn('PTA session invalid, waiting for user to update in settings');
  return service;
});

/// Provider for todo items (Courses + PTA merged, concurrent).
final todoListProvider = FutureProvider<List<TodoItem>>((ref) async {
  const cacheKey = 'todo_list';
  const ttl = Duration(minutes: 5);

  // 缓存优先
  try {
    final db = WebCacheDatabase.instanceOrNull;
    if (db != null) {
      final fresh = db.getFreshCachedWebPage(cacheKey, ttl);
      if (fresh != null) {
        final cached = db.getCachedList(cacheKey);
        if (cached.isNotEmpty) {
          return cached
              .cast<Map<String, dynamic>>()
              .map((e) => TodoItem.fromJson(e))
              .toList();
        }
      }
    }
  } catch (_) { /* 缓存读取失败 → 走网络 */ }

  final todos = <TodoItem>[];
  final api = ref.read(coursesApiProvider);

  // ── Courses (并发，从 courses.zju.edu.cn 拉取活动/作业) ──
  final coursesResult = await api.getMyCourses();
  final courses = coursesResult.fold((c) => c, (_) => <Course>[]);

  // 并发拉取所有课程的 activities
  final courseFutures = courses.map((c) => api.getCourseFullData(c.id));
  final courseResults = await Future.wait(courseFutures);

  for (final result in courseResults) {
    result.fold((fullData) {
      for (final activity in fullData.activities) {
        final type = activity['type']?.toString() ?? '';
        if (type == 'homework' || type == 'exam' || type == 'interactive') {
          todos.add(TodoItem(
            id: activity['id']?.toString() ?? '',
            title: activity['title']?.toString() ?? '',
            courseName: courses
                    .firstWhere((c) => c.id == fullData.courseId,
                        orElse: () => Course(
                            id: fullData.courseId,
                            name: '',
                            teacherName: null))
                    .name,
            type: type,
            deadline: activity['deadline']?.toString() ??
                activity['end_time']?.toString(),
            isSubmitted: activity['is_submitted'] == true ||
                activity['submission_status'] == 'submitted',
            source: 'courses',
          ));
        }
      }
    }, (_) => null);
  }

  // ── PTA ──
  final pta = await ref.read(pintiaServiceProvider.future);
  if (pta != null) {
    try {
      final psResult = await pta.getProblemSets();
      final problemSets = psResult.fold((p) => p, (_) => <Map<String, dynamic>>[]);

      for (final ps in problemSets) {
        final name = ps['name']?.toString() ?? 'PTA 题集';
        final deadline = ps['endAt']?.toString() ??
            ps['deadline']?.toString() ??
            ps['end_at']?.toString();

        todos.add(TodoItem(
          id: 'pintia-${ps['id'] ?? ''}',
          title: name,
          courseName: 'PTA',
          type: 'exam',
          deadline: deadline,
          isSubmitted: false,
          source: 'pintia',
        ));
      }
    } catch (e) {
      Log().warn('PTA problem sets fetch failed', error: e);
    }
  }

  // 排序
  todos.sort((a, b) {
    final aDate = a.deadlineDate;
    final bDate = b.deadlineDate;
    if (aDate == null && bDate == null) return 0;
    if (aDate == null) return 1;
    if (bDate == null) return -1;
    return aDate.compareTo(bDate);
  });

  // 写入缓存
  if (todos.isNotEmpty) {
    try {
      final db = await WebCacheDatabase.getInstance();
      await db.setCachedWebPage(
          cacheKey, jsonEncode(todos.map((t) => t.toJson()).toList()));
    } catch (_) {}
  }

  return todos;
});
