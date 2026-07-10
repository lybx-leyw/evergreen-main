/// HTML render: renderKanban
import 'dart:convert';
import '../shared/html_helpers.dart';

String renderKanban(Map<String, dynamic> comp) {
  final cfg = comp['config'] as Map<String, dynamic>? ?? {};
  final columns = (cfg['columns'] as List<dynamic>? ?? [
    {'title': '待办', 'items': ['任务 A', '任务 B']},
    {'title': '进行中', 'items': ['任务 C']},
    {'title': '已完成', 'items': ['任务 D', '任务 E']},
  ]).cast<Map<String, dynamic>>();

  final colsHtml = columns.map((col) {
    final colTitle = col['title'] as String? ?? '';
    final items = (col['items'] as List<dynamic>? ?? []).map((it) {
      final text = it is Map ? (it['text'] ?? it['label'] ?? '') : it.toString();
      final tag = it is Map ? it['tag'] as String? : null;
      return '''
<div class="evg-kb-card">
  <span>${esc(text)}</span>
  ${tag != null ? '<span class="evg-kb-tag">${esc(tag)}</span>' : ''}
</div>''';
    }).join('');

    return '''
<div class="evg-kb-column">
  <div class="evg-kb-col-header">
    <span>${esc(colTitle)}</span>
    <span class="evg-kb-count">${items.length}</span>
  </div>
  <div class="evg-kb-col-body">$items</div>
</div>''';
  }).join('');

  return '''
<div class="evg-comp evg-comp-kanban">
  <div class="evg-kb-board">$colsHtml</div>
</div>''';
}
