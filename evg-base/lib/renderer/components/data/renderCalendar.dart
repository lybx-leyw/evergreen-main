/// HTML render: renderCalendar
import 'dart:convert';
import '../shared/html_helpers.dart';

String renderCalendar(Map<String, dynamic> comp) {
  const dayHeaders = ['一', '二', '三', '四', '五', '六', '日'];
  // 简单 7×5 网格日历
  final cells = <String>[];
  for (var i = 1; i <= 31; i++) {
    cells.add('<div class="evg-cal-day${i == 15 ? ' active' : ''}">$i</div>');
  }
  // Pad remaining
  for (var i = 32; i <= 35; i++) {
    cells.add('<div class="evg-cal-day"></div>');
  }

  return '''
<div class="evg-comp evg-comp-cal">
  <div class="evg-cal-header">
    <button>◀</button>
    <span>2026年 7月</span>
    <button>▶</button>
  </div>
  <div class="evg-cal-grid">
    ${dayHeaders.map((d) => '<div class="evg-cal-dh">$d</div>').join('')}
    ${cells.join('')}
  </div>
</div>''';
}
