/// ZJU 智云课堂工具——获取录播课程列表。
library;

import '../tool.dart';
import 'zju_data_source.dart';

class ZjuClassroomTool extends Tool {
  final ZjuDataSource _dataSource;

  ZjuClassroomTool(this._dataSource);

  @override
  String get name => 'get_classroom_videos';

  @override
  String get description => '获取智云课堂的录播课程列表，包括课程名称。';

  @override
  Map<String, dynamic> get schema => {
        'type': 'object',
        'properties': {},
        'required': [],
      };

  @override
  Future<String> execute(Map<String, dynamic> args) async {
    try {
      final courses = await _dataSource.getClassroomCourses();
      if (courses.isEmpty) return '智云课堂暂无可用的录播课程。';

      final buf = StringBuffer();
      buf.writeln('智云课堂共有 ${courses.length} 门课程：');
      for (final c in courses) {
        buf.writeln('- **${c.title}**');
      }
      return buf.toString().trim();
    } catch (e) {
      return '[查询失败: $e]';
    }
  }

  @override
  bool get readOnly => true;
}
