/// HTML render: renderCodeEditor — 模板引擎渲染，读取 config.language/content。
library;
import 'package:evergreen_base/renderer/components/shared/template_engine.dart';

const _tpl = '''
<div class="evg-comp evg-comp-code">
  <div class="evg-code-header">
    <span>📄 main.{{ config.language | default('txt') | lower }}</span>
    <span class="evg-code-lang">{{ config.language | default('text') }}</span>
  </div>
  <div class="evg-code-body">
    <div class="evg-code-lines">{% for n in lineNums %}{{ n }}<br>{% endfor %}</div>
    <pre class="evg-code-pre">{{ config.content | default('// 暂无代码') }}</pre>
  </div>
</div>
''';

String renderCodeEditor(Map<String, dynamic> comp) {
  final cfg = comp['config'] as Map<String, dynamic>? ?? {};
  final content = cfg['content'] as String? ?? '';
  final lineCount = content.isEmpty ? 1 : content.split('\n').length;
  final ctx = <String, dynamic>{
    ...comp,
    'lineNums': List.generate(lineCount, (i) => i + 1),
  };
  return renderTemplate(_tpl, ctx);
}
