/// ZJU 课程工具——获取用户已选课程列表。
library;

import '../tool.dart';
import 'zju_data_source.dart';

class ZjuCoursesTool extends Tool {
  final ZjuDataSource _dataSource;

  ZjuCoursesTool(this._dataSource);

  @override
  String get name => 'get_courses';

  @override
  String get description => '获取所有学期的总课程列表，包括课程名称、授课教师、进行状态（并不可靠）。';

  @override
  Map<String, dynamic> get schema => {
        'type': 'object',
        'properties': {},
        'required': [],
      };

  @override
  Future<String> execute(Map<String, dynamic> args) async {
    try {
      final courses = await _dataSource.getCourses();
      if (courses.isEmpty) return '当前没有课程数据。';

      final buf = StringBuffer();
      buf.writeln('共有 ${courses.length} 门课程：');
      for (final c in courses) {
        final status = c.isActive ? '进行中' : '已结束';
        buf.writeln('- **${c.name}** ($status) ${c.teacher != null ? "授课: ${c.teacher}" : ""}');
      }
      return buf.toString().trim();
    } catch (e) {
      return '[查询失败: $e]';
    }
  }

  @override
  bool get readOnly => true;
}
