/// HTML render: renderImageGallery
import 'dart:convert';
import 'package:evergreen_base/renderer/components/shared/html_helpers.dart';

String renderImageGallery(Map<String, dynamic> comp) {
  final cfg = comp['config'] as Map<String, dynamic>? ?? {};
  final images = (cfg['images'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
  final title = cfg['title'] as String? ?? '图片画廊';

  if (images.isEmpty) {
    return renderPlaceholder('image-gallery', cfg);
  }

  final thumbsHtml = images.map((img) {
    final url = img['url'] as String? ?? img['src'] as String? ?? '';
    final caption = img['caption'] as String? ?? '';
    return '''
<div class="evg-gal-item">
  <div class="evg-gal-thumb" style="background-image:url(${esc(url)})">
    <div class="evg-gal-overlay">🔍</div>
  </div>
  ${caption.isNotEmpty ? '<div class="evg-gal-caption">${esc(caption)}</div>' : ''}
</div>''';
  }).join('');

  return '''
<div class="evg-comp evg-comp-gallery">
  <div class="evg-comp-title">🖼️ ${esc(title)}</div>
  <div class="evg-gal-grid">$thumbsHtml</div>
</div>''';
}
