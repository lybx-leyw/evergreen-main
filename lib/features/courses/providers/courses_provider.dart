import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/result.dart';
import '../../../core/errors.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../models/course.dart';
import '../services/courses_api_service.dart';

/// Provider for the list of enrolled courses.
///
/// 数据源：courses.zju.edu.cn（学在浙大）。
/// 注意：学在浙大无法准确判断课程是否已结束，
/// 仪表盘课程卡片不显示完成状态。
final coursesListProvider =
    FutureProvider<Result<List<Course>>>((ref) async {
  final auth = ref.watch(authProvider);
  if (!auth.isLoggedIn) {
    return Err(AppError.configMissing('学号和密码')
      ..recoveryHint = '请先登录统一认证');
  }
  final api = ref.read(coursesApiProvider);
  return api.getMyCourses();
});

/// Provider for full course data (activities).
final courseFullDataProvider =
    FutureProvider.family.autoDispose<Result<CourseFullData>, int>((ref, courseId) async {
  final api = ref.read(coursesApiProvider);
  return api.getCourseFullData(courseId);
});

/// Provider for all exams from courses.zju.edu.cn.
final coursesExamsProvider =
    FutureProvider<Result<List<Map<String, dynamic>>>>((ref) async {
  final api = ref.read(coursesApiProvider);
  return api.getAllExams();
});

/// Selected course ID — shared between courses, downloads, and scores screens.
final selectedCourseIdProvider = StateProvider<int?>((ref) => null);
