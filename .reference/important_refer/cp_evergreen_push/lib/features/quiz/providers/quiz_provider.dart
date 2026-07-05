import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/result.dart';
import '../../../features/courses/providers/courses_provider.dart';
import '../../../features/courses/services/courses_api_service.dart';

final quizClassroomsProvider =
    FutureProvider.family<Result<List<Map<String, dynamic>>>, int>(
        (ref, courseId) async {
  final api = ref.read(coursesApiProvider);
  return api.getClassrooms(courseId);
});

final quizSubjectsProvider =
    FutureProvider.family<Result<List<Map<String, dynamic>>>, int>(
        (ref, classroomId) async {
  final api = ref.read(coursesApiProvider);
  return api.getQuizSubjects(classroomId);
});
