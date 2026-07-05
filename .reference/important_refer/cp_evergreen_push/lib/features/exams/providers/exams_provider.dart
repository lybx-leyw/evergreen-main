import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/log.dart';
import '../../../core/models/exam.dart';
import '../../../features/zdbk/providers/zdbk_provider.dart';
import '../../../features/courses/providers/courses_provider.dart';

/// Provider for upcoming exams.
///
/// 数据源：ZDBK（教务网）为第一来源，courses.zju.edu.cn 为回退。
/// 按考试时间升序排列，无时间字段的排在末尾。
final examsListProvider = FutureProvider<List<Exam>>((ref) async {
  final exams = <Exam>[];

  // 1. ZDBK（教务网）
  final zdbkResult = await ref.watch(zdbkExamsProvider.future);
  zdbkResult.fold(
    (zdbkExams) {
      exams.addAll(zdbkExams.map((e) => Exam.fromZdbk(e)));
      Log().debug('Exams ZDBK loaded', data: {'count': zdbkExams.length});
    },
    (err) => Log().warn('Exams ZDBK unavailable',
        data: {'error': err.userMessage, 'fallback': 'courses'}),
  );

  // 2. 学在浙大回退
  if (exams.isEmpty) {
    final coursesResult = await ref.watch(coursesExamsProvider.future);
    coursesResult.fold(
      (coursesExams) {
        exams.addAll(coursesExams.map((e) => Exam.fromCourses(e)));
        Log().debug('Exams courses loaded', data: {'count': coursesExams.length});
      },
      (err) => Log().warn('Exams all sources unavailable',
          data: {'error': err.userMessage}),
    );
  }

  // 按考试时间升序，无时间排末尾
  exams.sort((a, b) {
    if (a.startTime == null && b.startTime == null) return 0;
    if (a.startTime == null) return 1;
    if (b.startTime == null) return -1;
    return a.startTime!.compareTo(b.startTime!);
  });

  Log().info('Exams total', data: {'count': exams.length});
  return exams;
});
