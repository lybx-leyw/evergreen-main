/// ZJU 课表工具——获取当前课表。
///
/// 按学期 → 星期几分组展示，每节课标注课程名、节次、教师、地点。
library;

import '../tool.dart';
import 'zju_data_source.dart';

const _dayNames = ['', '周一', '周二', '周三', '周四', '周五', '周六', '周日'];

class ZjuTimetableTool extends Tool {
  final ZjuDataSource _dataSource;

  ZjuTimetableTool(this._dataSource);

  @override
  String get name => 'get_timetable';

  @override
  String get description =>
      '获取当前课表（可能包含多个学期），按学期和星期几分组展示，'
      '包括每节课的课程名称、节次、上课地点、授课教师、周次。'
      '可用于回答"今天有什么课""这周的课表""秋学期课表"等问题。';

  @override
  Map<String, dynamic> get schema => {
        'type': 'object',
        'properties': {},
        'required': [],
      };

  @override
  Future<String> execute(Map<String, dynamic> args) async {
    try {
      final entries = await _dataSource.getTimetable();
      if (entries.isEmpty) return '当前没有课表数据。请先在数据状态面板或仪表盘刷新数据后重试。';

      // 按学期分组
      final bySemester = <String, List<ZjuTimetableEntry>>{};
      for (final e in entries) {
        final label = e.semesterLabel ?? '未知学期';
        bySemester.putIfAbsent(label, () => []);
        bySemester[label]!.add(e);
      }

      final buf = StringBuffer();
      buf.writeln('## 课表\n');

      // 按学期排序（优先显示有年份的）
      final semesterKeys = bySemester.keys.toList()
        ..sort((a, b) {
          final hasYearA = a.contains(RegExp(r'\d'));
          final hasYearB = b.contains(RegExp(r'\d'));
          if (hasYearA && !hasYearB) return -1;
          if (!hasYearA && hasYearB) return 1;
          return a.compareTo(b);
        });

      for (final semKey in semesterKeys) {
        final semEntries = bySemester[semKey]!;

        buf.writeln('### $semKey\n');

        // 按星期几分组
        final byDay = <int, List<ZjuTimetableEntry>>{};
        for (final e in semEntries) {
          byDay.putIfAbsent(e.dayOfWeek, () => []);
          byDay[e.dayOfWeek]!.add(e);
        }

        for (int day = 1; day <= 7; day++) {
          final dayEntries = byDay[day];
          if (dayEntries == null || dayEntries.isEmpty) continue;

          buf.writeln('**${_dayNames[day]}**');
          dayEntries.sort((a, b) => a.periods.first.compareTo(b.periods.first));

          for (final e in dayEntries) {
            final periodStr = e.periods.length == 1
                ? '第 ${e.periods.first} 节'
                : '第 ${e.periods.first}-${e.periods.last} 节';
            buf.write('- $periodStr ${e.courseName}');
            if (e.teacher != null && e.teacher!.isNotEmpty) {
              buf.write(' | ${e.teacher}');
            }
            if (e.location != null && e.location!.isNotEmpty) {
              buf.write(' | ${e.location}');
            }
            if (e.weekRange != null && e.weekRange!.isNotEmpty) {
              buf.write(' | ${e.weekRange}');
            }
            buf.writeln();
          }
          buf.writeln();
        }
      }

      buf.writeln('---\n_数据来源：ZDBK 教务系统_');
      return buf.toString().trim();
    } catch (e) {
      return '[查询失败: $e]';
    }
  }

  @override
  bool get readOnly => true;
}
