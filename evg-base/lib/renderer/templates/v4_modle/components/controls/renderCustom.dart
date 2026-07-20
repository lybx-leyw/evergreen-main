/// HTML render: renderCustom
import 'dart:convert';
import 'package:evergreen_base/renderer/components/shared/html_helpers.dart';

String renderCustom(Map<String, dynamic> comp) {
  final cfg = comp['config'] as Map<String, dynamic>? ?? {};
  final html = cfg['html'] as String?;
  final src = cfg['src'] as String?;

  if (html != null) {
    return '''
<div class="evg-comp evg-comp-custom">
  $html
</div>''';
  }

  if (src != null) {
    return '''
<div class="evg-comp evg-comp-custom">
  <iframe src="${esc(src)}" class="evg-custom-iframe" sandbox="allow-scripts allow-same-origin"></iframe>
</div>''';
  }

  return renderPlaceholder('custom', cfg);
}
