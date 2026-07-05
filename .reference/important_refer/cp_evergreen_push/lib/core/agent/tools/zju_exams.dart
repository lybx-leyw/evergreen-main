/// ZJU 考试工具——获取考试日程。
library;

import '../tool.dart';
import 'zju_data_source.dart';

class ZjuExamsTool extends Tool {
  final ZjuDataSource _dataSource;

  ZjuExamsTool(this._dataSource);

  @override
  String get name => 'get_exams';

  @override
  String get description => '获取即将到来的考试日程，包括考试名称、时间和地点。';

  @override
  Map<String, dynamic> get schema => {
        'type': 'object',
        'properties': {},
        'required': [],
      };

  @override
  Future<String> execute(Map<String, dynamic> args) async {
    try {
      final exams = await _dataSource.getExams();
      if (exams.isEmpty) return '当前没有考试安排。';

      final buf = StringBuffer();
      buf.writeln('共有 ${exams.length} 场考试：');
      final now = DateTime.now();
      for (final e in exams) {
        final timeStr = e.startTime != null
            ? '${e.startTime!.year}-${e.startTime!.month.toString().padLeft(2, '0')}-${e.startTime!.day.toString().padLeft(2, '0')} ${e.startTime!.hour.toString().padLeft(2, '0')}:${e.startTime!.minute.toString().padLeft(2, '0')}'
            : '时间待定';
        final locationStr = e.location ?? '地点待定';

        String tag;
        if (e.startTime != null) {
          final daysLeft = e.startTime!.difference(now).inDays;
          if (daysLeft < 0) {
            tag = ' ✅ 已结束';
          } else if (daysLeft <= 7) {
            tag = ' 🔴 $daysLeft 天后';
          } else {
            tag = ' 🟡 $daysLeft 天后';
          }
        } else {
          tag = '';
        }

        buf.writeln('- **${e.name}** $tag');
        buf.writeln('  时间: $timeStr');
        buf.writeln('  地点: $locationStr');
      }
      return buf.toString().trim();
    } catch (e) {
      return '[查询失败: $e]';
    }
  }

  @override
  bool get readOnly => true;
}
