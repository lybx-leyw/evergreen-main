/// HTML render: renderCodeEditor
import 'dart:convert';
import '../shared/html_helpers.dart';

String renderCodeEditor(Map<String, dynamic> comp) {
  final cfg = comp['config'] as Map<String, dynamic>? ?? {};
  final lang = cfg['language'] as String? ?? 'python';
  final code = codeSamples[lang] ?? codeSamples['python']!;
  final lines = code.split('\n');

  return '''
<div class="evg-comp evg-comp-code">
  <div class="evg-code-header">
    <span>📄 main.${langExt(lang)}</span>
    <span class="evg-code-lang">$lang</span>
  </div>
  <div class="evg-code-body">
    <div class="evg-code-lines">${List.generate(lines.length, (i) => i + 1).join('<br>')}</div>
    <pre class="evg-code-pre">$code</pre>
  </div>
</div>''';
}
