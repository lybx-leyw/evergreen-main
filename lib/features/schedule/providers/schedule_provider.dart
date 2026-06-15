import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/result.dart';
import '../../../core/utils/date_utils.dart';
import '../../../features/courses/providers/courses_provider.dart';
import '../../../features/courses/models/course.dart';
import '../services/ical_exporter.dart';

/// Provider that generates iCal content from enrolled courses.
final icalExportProvider = FutureProvider<String>((ref) async {
  final result = await ref.read(coursesListProvider.future);
  final courses = result.fold((list) => list, (_) => <Course>[]);

  final schedules = courses.map((c) => CourseSchedule(
    id: c.id.toString(),
    name: c.name,
    instructor: c.teacherName ?? '',
    className: c.className ?? '',
    location: c.teachingPlace ?? c.className ?? '',
    rawSchedule: c.className,
  )).toList();

  final exporter = ICalExporter();
  final semesterStart = DateUtils.getSemesterStart();
  return exporter.generate(schedules, semesterStart);
});

/// Export iCal content to a file and return the file path.
final icalExportFileProvider = FutureProvider<String?>((ref) async {
  final icsContent = await ref.read(icalExportProvider.future);

  final dir = await getTemporaryDirectory();
  final filePath = '${dir.path}${Platform.pathSeparator}zju-schedule.ics';
  final file = File(filePath);
  await file.writeAsString(icsContent);

  return filePath;
});
