/// ZJU 开课情况工具——获取当前学期的课程安排。
library;

import '../../../core/agent/tool.dart';
import '../../../core/models/course_offering.dart';

/// 开课情况数据源接口（由 Flutter 层实现）。
abstract class CourseOfferingDataSource {
  Future<List<CourseOffering>> getCourseOfferings({int year = 2024, int semester = 12});
}

class ZjuCourseOfferingsTool extends Tool {
  final CourseOfferingDataSource _dataSource;

  ZjuCourseOfferingsTool(this._dataSource);

  @override
  String get name => 'get_course_offerings';

  @override
  String get description => '获取当前学期的开课情况，包括课程名称、授课教师、上课时间、地点、学分等信息。';

  @override
  Map<String, dynamic> get schema => {
        'type': 'object',
        'properties': {
          'year': {
            'type': 'integer',
            'description': '学年，如 2024 代表 2024-2025 学年',
          },
          'semester': {
            'type': 'integer',
            'description': '学期：3=秋冬学期, 12=春夏学期',
          },
        },
        'required': [],
      };

  @override
  Future<String> execute(Map<String, dynamic> args) async {
    try {
      final year = args['year'] as int? ?? 2024;
      final semester = args['semester'] as int? ?? 12;
      final offerings = await _dataSource.getCourseOfferings(
        year: year,
        semester: semester,
      );

      if (offerings.isEmpty) return '当前学期没有开课数据。';

      final buf = StringBuffer();
      buf.writeln('📚 开课情况（${year}-${year + 1}学年 学期$semester）');
      buf.writeln('共 ${offerings.length} 门课程：');
      buf.writeln();

      // 按课程类型分组
      final byType = <String, List<CourseOffering>>{};
      for (final o in offerings) {
        final type = o.courseType ?? '其他';
        byType.putIfAbsent(type, () => []).add(o);
      }

      for (final entry in byType.entries) {
        buf.writeln('【${entry.key}】共 ${entry.value.length} 门');
        for (final o in entry.value) {
          buf.writeln('- ${o.courseName}');
          if (o.teacher != null) buf.writeln('  教师: ${o.teacher}');
          if (o.schedule != null && o.schedule!.isNotEmpty) {
            buf.writeln('  时间: ${o.schedule}');
          }
          if (o.location != null) buf.writeln('  地点: ${o.location}');
          if (o.credits > 0) buf.writeln('  学分: ${o.credits}');
        }
        buf.writeln();
      }

      return buf.toString().trim();
    } catch (e) {
      return '[查询失败: $e]';
    }
  }

  @override
  bool get readOnly => true;
}
