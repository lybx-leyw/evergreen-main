/// HTML render: renderMarkdown
import 'dart:convert';
import '../shared/html_helpers.dart';

String renderMarkdown(Map<String, dynamic> comp) {
  final cfg = comp['config'] as Map<String, dynamic>? ?? {};
  final content = cfg['content'] as String? ?? '# Markdown 内容\n\n在 config.content 中设置你的 Markdown 文本。';

  return '''
<div class="evg-comp evg-comp-md">
  <div class="evg-comp-title">📄 Markdown</div>
  <div class="evg-md-content" style="white-space:pre-wrap;line-height:1.8;padding:12px">${esc(content)}</div>
</div>''';
}
