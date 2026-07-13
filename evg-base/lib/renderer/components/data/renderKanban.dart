/// HTML render: renderKanban — 模板引擎渲染，读取 config.columns；
/// 空时显示空态，不再写死默认 3 列（R4/R11 合规）。
library;

import '../shared/template_engine.dart';

const _tpl = '''
<div class="evg-comp evg-comp-kanban">
  {% if config.columns %}
  <div class="evg-kb-board">
    {% for col in config.columns %}
    <div class="evg-kb-column">
      <div class="evg-kb-col-header">
        <span>{{ col.title }}</span>
        <span class="evg-kb-count">{{ len(col.items) }}</span>
      </div>
      <div class="evg-kb-col-body">
        {% for it in col.items %}
        <div class="evg-kb-card">
          <span>{{ it.text | default(it.label) }}</span>
          {% if it.tag %}<span class="evg-kb-tag">{{ it.tag }}</span>{% endif %}
        </div>
        {% endfor %}
      </div>
    </div>
    {% endfor %}
  </div>
  {% else %}
  <div class="evg-empty">暂无看板数据（config.columns）</div>
  {% endif %}
</div>
''';

String renderKanban(Map<String, dynamic> comp) => renderTemplate(_tpl, comp);
