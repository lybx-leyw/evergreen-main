/// HTML render: renderTimeline
import 'dart:convert';
import 'package:evergreen_base/renderer/components/shared/html_helpers.dart';

String renderTimeline(Map<String, dynamic> comp) {
  final cfg = comp['config'] as Map<String, dynamic>? ?? {};
  final items = (cfg['items'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
  final title = cfg['title'] as String? ?? '时间线';

  if (items.isEmpty) {
    return renderPlaceholder('timeline', cfg);
  }

  final itemsHtml = items.asMap().entries.map((e) {
    final item = e.value;
    final time = item['time'] as String? ?? '';
    final label = item['label'] as String? ?? '';
    final desc = item['description'] as String? ?? '';
    final isLast = e.key == items.length - 1;
    return '''
<div class="evg-tl-item">
  <div class="evg-tl-marker"></div>
  ${isLast ? '' : '<div class="evg-tl-line"></div>'}
  <div class="evg-tl-content">
    <div class="evg-tl-time">${esc(time)}</div>
    <div class="evg-tl-label">${esc(label)}</div>
    ${desc.isNotEmpty ? '<div class="evg-tl-desc">${esc(desc)}</div>' : ''}
  </div>
</div>''';
  }).join('');

  return '''
<div class="evg-comp evg-comp-timeline">
  <div class="evg-comp-title">📅 ${esc(title)}</div>
  <div class="evg-tl-container">$itemsHtml</div>
</div>''';
}
