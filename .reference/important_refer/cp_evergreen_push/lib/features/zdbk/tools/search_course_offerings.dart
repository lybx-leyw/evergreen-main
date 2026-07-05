/// Agent 工具：搜索开课课程（RAG）。
/// 让 AI 能根据关键词搜索当前学期的开课情况。
library;

import '../../../core/agent/tool.dart';
import '../../../core/models/course_offering.dart';

/// 开课搜索数据源接口。
abstract class CourseOfferingSearchDataSource {
  Future<List<CourseOffering>> searchCourseOfferings({
    required String query,
    int year = 2025,
    int semester = 12,
  });
}

/// 搜索开课课程工具。
class SearchCourseOfferingsTool extends Tool {
  final CourseOfferingSearchDataSource _dataSource;

  SearchCourseOfferingsTool(this._dataSource);

  @override
  String get name => 'search_course_offerings';

  @override
  String get description =>
      '搜索当前学期的开课课程。当你需要查找某门课程的信息（课程名称、授课教师、上课时间地点、学分等）时使用。'
      '支持按课程名称、教师姓名搜索。';

  @override
  Map<String, dynamic> get schema => {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': '搜索关键词，可以是课程名称或教师姓名',
          },
        },
        'required': ['query'],
      };

  @override
  Future<String> execute(Map<String, dynamic> args) async {
    final query = args['query']?.toString() ?? '';
    if (query.isEmpty) return '[error: 搜索关键词为空]';

    try {
      final results = await _dataSource.searchCourseOfferings(query: query);

      if (results.isEmpty) {
        return '未找到与 "$query" 相关的开课课程。';
      }

      final buf = StringBuffer();
      buf.writeln('搜索 "$query" 找到 ${results.length} 门课程：\n');
      for (var i = 0; i < results.length; i++) {
        final o = results[i];
        buf.writeln('${i + 1}. **${o.courseName}**');
        if (o.teacher != null) buf.writeln('   教师: ${o.teacher}');
        if (o.schedule != null && o.schedule!.isNotEmpty) {
          buf.writeln('   时间: ${o.schedule}');
        }
        if (o.location != null && o.location!.isNotEmpty) {
          buf.writeln('   地点: ${o.location}');
        }
        if (o.credits > 0) buf.writeln('   学分: ${o.credits}');
        if (o.courseType != null) buf.writeln('   性质: ${o.courseType}');
        buf.writeln();
      }

      return buf.toString().trim();
    } catch (e) {
      return '[搜索失败: $e]';
    }
  }

  @override
  bool get readOnly => true;
}
