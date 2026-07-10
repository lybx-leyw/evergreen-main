/// HTML render: renderNavButton
import 'dart:convert';
import '../shared/html_helpers.dart';

String renderNavButton(Map<String, dynamic> comp) {
  final cfg = comp['config'] as Map<String, dynamic>? ?? {};
  final label = cfg['label'] as String? ?? '导航';
  final icon = cfg['icon'] as String? ?? '📌';
  final target = cfg['target'] as String? ?? '#';
  return '''
<div class="evg-comp evg-comp-navbtn">
  <a class="evg-navbtn" href="${esc(target)}">
    <span class="evg-navbtn-icon">$icon</span>
    <span class="evg-navbtn-label">${esc(label)}</span>
  </a>
</div>''';
}
