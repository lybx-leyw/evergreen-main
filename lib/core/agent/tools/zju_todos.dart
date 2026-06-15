/// ZJU 待办工具——获取作业/待办列表。
library;

import '../tool.dart';
import 'zju_data_source.dart';

class ZjuTodosTool extends Tool {
  final ZjuDataSource _dataSource;

  ZjuTodosTool(this._dataSource);

  @override
  String get name => 'get_todos';

  @override
  String get description => '获取当前的待办作业列表，包括标题、截止日期和类型。';

  @override
  Map<String, dynamic> get schema => {
        'type': 'object',
        'properties': {},
        'required': [],
      };

  @override
  Future<String> execute(Map<String, dynamic> args) async {
    try {
      final todos = await _dataSource.getTodos();
      if (todos.isEmpty) return '当前没有待办作业。';

      final buf = StringBuffer();
      buf.writeln('共有 ${todos.length} 项待办：');
      final now = DateTime.now();
      for (final t in todos) {
        final deadlineStr = t.deadline != null ? '截止: ${t.deadline}' : '无截止日期';
        String tag;
        if (t.deadline != null) {
          final deadline = DateTime.tryParse(t.deadline!);
          if (deadline != null) {
            final daysLeft = deadline.difference(now).inDays;
            if (daysLeft < 0) {
              tag = ' ⏰ 已逾期 ${-daysLeft} 天';
            } else if (daysLeft <= 3) {
              tag = ' 🔴 ${daysLeft} 天内到期';
            } else if (daysLeft <= 7) {
              tag = ' 🟡 ${daysLeft} 天内到期';
            } else {
              tag = '';
            }
          } else {
            tag = '';
          }
        } else {
          tag = '';
        }
        buf.writeln('- **${t.title}** ($deadlineStr$tag)');
      }
      return buf.toString().trim();
    } catch (e) {
      return '[查询失败: $e]';
    }
  }

  @override
  bool get readOnly => true;
}
