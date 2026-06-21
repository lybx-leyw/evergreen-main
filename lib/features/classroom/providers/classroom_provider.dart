import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/result.dart';
import '../../../core/network/dio_client.dart';
import '../../auth/providers/auth_provider.dart';
import '../services/classroom_crawler.dart';
import '../models/classroom_video.dart';
import '../models/course_content.dart';

final classroomCrawlerProvider = Provider<ClassroomCrawler>((ref) {
  final dio = ref.read(dioClientProvider);
  return ClassroomCrawler(dio);
});

final classroomCoursesProvider =
    FutureProvider<Result<List<ClassroomCourse>>>((ref) async {
  // watch auth 状态：登录完成后自动重新加载课程
  ref.watch(authProvider);
  final crawler = ref.read(classroomCrawlerProvider);
  return crawler.listCourses();
});

final classroomVideosProvider =
    FutureProvider.family.autoDispose<Result<List<ClassroomVideo>>, int>(
        (ref, courseId) async {
  final crawler = ref.read(classroomCrawlerProvider);
  return crawler.listVideos(courseId);
});

final courseContentProvider =
    FutureProvider.family.autoDispose<Result<CourseContent>, ({int courseId, int subId})>(
        (ref, params) async {
  final crawler = ref.read(classroomCrawlerProvider);
  return crawler.fetchCourseContent(params.courseId, params.subId);
});
