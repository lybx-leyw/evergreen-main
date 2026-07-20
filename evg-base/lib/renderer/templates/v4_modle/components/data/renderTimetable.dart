/// HTML render: renderTimetable
import 'dart:convert';
import 'package:evergreen_base/renderer/components/shared/html_helpers.dart';

String renderTimetable(Map<String, dynamic> comp) {
  final cfg = comp['config'] as Map<String, dynamic>? ?? {};
  final sessions = (cfg['sessions'] as List<dynamic>? ?? [])
      .whereType<Map<dynamic, dynamic>>()
      .toList();
  if (sessions.isEmpty) {
    return renderEmpty('timetable', '暂无课表数据（官方空态）');
  }
  // 计算最大节次，构建 7 列网格
  var maxPeriod = 1;
  for (final s in sessions) {
    final ps = (s['periods'] as List<dynamic>? ?? []);
    for (final p in ps) {
      final n = p is int ? p : int.tryParse(p.toString()) ?? 0;
      if (n > maxPeriod) maxPeriod = n;
    }
  }
  final dayHeaders = ['一', '二', '三', '四', '五', '六', '日'];
  final grid = <String>[];
  for (var p = 1; p <= maxPeriod; p++) {
    final row = <String>[];
    for (var d = 1; d <= 7; d++) {
      final cellSessions = sessions.where((s) {
        final dow = s['dayOfWeek'] is int
            ? s['dayOfWeek'] as int
            : int.tryParse(s['dayOfWeek'].toString()) ?? 0;
        final ps = (s['periods'] as List<dynamic>? ?? [])
            .map((x) => x is int ? x : int.tryParse(x.toString()) ?? 0)
            .toList();
        return dow == d && ps.contains(p);
      }).toList();
      if (cellSessions.isEmpty) {
        row.add('<td class="evg-tt-cell"></td>');
      } else {
        final inner = cellSessions.map((s) {
          final name = esc((s['courseName'] ?? s['name'] ?? '?').toString());
          final teacher = esc((s['teacher'] ?? '').toString());
          final loc = esc((s['location'] ?? '').toString());
          return '<div class="evg-tt-session"><div class="evg-tt-name">$name</div>'
              '${teacher.isNotEmpty ? '<div class="evg-tt-teacher">$teacher</div>' : ''}'
              '${loc.isNotEmpty ? '<div class="evg-tt-loc">$loc</div>' : ''}</div>';
        }).join('');
        row.add('<td class="evg-tt-cell evg-tt-filled">$inner</td>');
      }
    }
    grid.add('<tr><th class="evg-tt-period">第$p节</th>${row.join('')}</tr>');
  }

  return '''
<div class="evg-comp evg-comp-timetable">
  <div class="evg-comp-title">📅 周课表（${sessions.length} 节课次）</div>
  <table class="evg-tt-table">
    <thead><tr><th></th>${dayHeaders.map((d) => '<th>周$d</th>').join('')}</tr></thead>
    <tbody>${grid.join('')}</tbody>
  </table>
</div>''';
}
