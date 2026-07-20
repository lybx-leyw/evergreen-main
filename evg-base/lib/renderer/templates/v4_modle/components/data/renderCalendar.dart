/// HTML render: renderCalendar — 模板引擎渲染，读取 config.year/month/events。
library;
import 'package:evergreen_base/renderer/components/shared/template_engine.dart';

const _dayHeaders = ['一', '二', '三', '四', '五', '六', '日'];

const _tpl = '''
<div class="evg-comp evg-comp-cal">
  <div class="evg-cal-header">
    <button>◀</button>
    <span>{{ year }}年 {{ month }}月</span>
    <button>▶</button>
  </div>
  <div class="evg-cal-grid">
    {% for d in dayHeaders %}<div class="evg-cal-dh">{{ d }}</div>{% endfor %}
    {% for cell in days %}<div class="evg-cal-day{{ cell.cls }}">{{ cell.day }}</div>{% endfor %}
  </div>
  {% if events %}
  <div class="evg-cal-events">
    {% for ev in events %}<div class="evg-cal-event">📌 {{ ev.title }}（{{ ev.date }}）</div>{% endfor %}
  </div>
  {% endif %}
</div>
''';

String renderCalendar(Map<String, dynamic> comp) {
  final cfg = comp['config'] as Map<String, dynamic>? ?? {};
  final year = cfg['year'] as int? ?? DateTime.now().year;
  final month = cfg['month'] as int? ?? DateTime.now().month;
  final events = (cfg['events'] as List<dynamic>? ?? [])
      .whereType<Map>()
      .map((e) => e.cast<String, dynamic>())
      .toList();
  final eventDates = <String>{
    for (final e in events)
      if (e['date'] is String) e['date'] as String
  };
  final pad2 = (int n) => n.toString().padLeft(2, '0');
  final daysInMonth = DateTime(year, month + 1, 0).day;
  final days = <Map<String, dynamic>>[
    for (var d = 1; d <= daysInMonth; d++)
      {
        'day': d,
        'cls': eventDates.contains('$year-${pad2(month)}-${pad2(d)}') ? ' active' : '',
      },
  ];
  final ctx = <String, dynamic>{
    ...comp,
    'year': year,
    'month': month,
    'dayHeaders': _dayHeaders,
    'days': days,
    'events': events,
  };
  return renderTemplate(_tpl, ctx);
}
