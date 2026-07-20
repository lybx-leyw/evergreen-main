/// HTML render: renderCardList
import 'dart:convert';
import 'package:evergreen_base/renderer/components/shared/html_helpers.dart';

String renderCardList(Map<String, dynamic> comp) {
  final cfg = comp['config'] as Map<String, dynamic>? ?? {};
  final cards = (cfg['cards'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
  final title = cfg['title'] as String? ?? '卡片列表';

  if (cards.isEmpty) {
    // 回退到 data-table 的卡片模式
    return renderDataCards(title, cfg['columns'] as List<dynamic>? ?? []);
  }

  final cardsHtml = cards.map((card) {
    final image = card['image'] as String?;
    final header = card['title'] as String? ?? '';
    final body = card['body'] as String? ?? '';
    final footer = card['footer'] as String? ?? '';
    return '''
<div class="evg-cl-card">
  ${image != null ? '<div class="evg-cl-image" style="background-image:url(${esc(image)})"></div>' : ''}
  <div class="evg-cl-body">
    <div class="evg-cl-title">${esc(header)}</div>
    <div class="evg-cl-text">${esc(body)}</div>
  </div>
  ${footer.isNotEmpty ? '<div class="evg-cl-footer">${esc(footer)}</div>' : ''}
</div>''';
  }).join('');

  return '''
<div class="evg-comp evg-comp-card-list">
  ${title.isNotEmpty ? '<div class="evg-comp-title">🃏 ${esc(title)}</div>' : ''}
  <div class="evg-cl-grid">$cardsHtml</div>
</div>''';
}
