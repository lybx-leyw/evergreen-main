/// HTML render: renderTypeCheck — 模板引擎渲染，读取 config.question/options。
library;

import '../shared/template_engine.dart';

const _tpl = '''
<div class="evg-comp evg-comp-typecheck">
  <div class="evg-comp-title">✅ 类型检查</div>
  <div class="evg-tc-question">
    <span class="evg-tc-q-number">Q1.</span>
    <span class="evg-tc-q-text">{{ config.question | default('请回答问题') }}</span>
  </div>
  <div class="evg-tc-options">
    {% for o in opts %}
    <div class="evg-tc-opt{{ o.cls }}">{{ o.letter }}. {{ o.text }}</div>
    {% endfor %}
  </div>
  <div class="evg-tc-score">得分: <span style="color:var(--evg-state-success)">{{ config.score | default(0) }}/{{ len(opts) }}</span> | 尝试: {{ config.attempts | default(1) }}</div>
</div>
''';

String renderTypeCheck(Map<String, dynamic> comp) {
  final cfg = comp['config'] as Map<String, dynamic>? ?? {};
  final options = (cfg['options'] as List<dynamic>? ?? [])
      .whereType<Map>()
      .map((e) => e.cast<String, dynamic>())
      .toList();
  final opts = <Map<String, dynamic>>[
    for (var i = 0; i < options.length; i++)
      {
        'text': options[i]['text'] ?? '',
        'cls': options[i]['correct'] == true ? ' correct' : '',
        'letter': String.fromCharCode(65 + i),
      },
  ];
  final ctx = <String, dynamic>{...comp, 'opts': opts};
  return renderTemplate(_tpl, ctx);
}
