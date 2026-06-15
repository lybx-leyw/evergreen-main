import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/result.dart';
import '../../courses/services/courses_api_service.dart';
import '../../courses/providers/courses_provider.dart';

/// Provider for course-specific scores (homework, exams) from courses.zju.edu.cn.
final courseScoresProvider =
    FutureProvider.family<Result<ScoresData>, int>((ref, courseId) async {
  final api = ref.read(coursesApiProvider);
  return api.getScoresAll(courseId);
});
