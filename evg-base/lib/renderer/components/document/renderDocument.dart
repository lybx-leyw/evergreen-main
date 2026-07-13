/// HTML render: renderDocument — 模板引擎渲染，读取 config.document/exportFormats。
library;

import '../shared/template_engine.dart';

const _tpl = '''
<div class="evg-comp evg-comp-doc">
  <div class="evg-doc-toolbar">
    <span class="evg-doc-logo">📝 文档编辑器</span>
    <div class="evg-doc-actions">
      {% for f in config.exportFormats %}<span class="evg-doc-tag">{{ f }}</span>{% endfor %}
    </div>
  </div>
  <div class="evg-doc-content">
    {% if config.document.title %}<h2>{{ config.document.title }}</h2>{% endif %}
    {% if config.document.content %}<p>{{ config.document.content }}</p>{% endif %}
    {% if config.content %}<p>{{ config.content }}</p>{% endif %}
    {% if config.paragraphs %}{% for p in config.paragraphs %}<p>{{ p }}</p>{% endfor %}{% endif %}
  </div>
</div>
''';

String renderDocument(Map<String, dynamic> comp) {
  final cfg = comp['config'] as Map<String, dynamic>? ?? {};
  final doc = cfg['document'] as Map<String, dynamic>? ?? {};
  final formats = (cfg['exportFormats'] as List<dynamic>? ??
          doc['exportFormats'] as List<dynamic>? ??
          const ['pdf', 'docx', 'md', 'html', 'txt'])
      .map((f) => f.toString())
      .toList();
  final ctx = <String, dynamic>{...comp, 'formats': formats};
  return renderTemplate(_tpl, ctx);
}
