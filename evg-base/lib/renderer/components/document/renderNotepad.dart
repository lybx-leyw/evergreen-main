/// HTML render: renderNotepad
import 'dart:convert';
import '../shared/html_helpers.dart';

String renderNotepad(Map<String, dynamic> comp) {
  final cfg = comp['config'] as Map<String, dynamic>? ?? {};
  final content = cfg['content'] as String? ?? '';
  final placeholder = cfg['placeholder'] as String? ?? '在这里写点什么...';

  return '''
<div class="evg-comp evg-comp-notepad">
  <div class="evg-np-toolbar">
    <span>📝 记事本</span>
    <span class="evg-np-status">已保存</span>
  </div>
  <textarea class="evg-np-editor" placeholder="${esc(placeholder)}">${esc(content)}</textarea>
</div>''';
}
