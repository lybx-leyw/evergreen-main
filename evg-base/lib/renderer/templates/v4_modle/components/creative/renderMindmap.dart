/// HTML render: renderMindmap — 模板引擎渲染，读取 config.root(标签/子节点)。
library;
import 'package:evergreen_base/renderer/components/shared/template_engine.dart';

const _tpl = '''
<div class="evg-comp evg-comp-mindmap">
  <div class="evg-comp-title">🧠 思维导图</div>
  <div class="evg-mindmap-node" style="text-align:center;padding:20px">
    <div class="evg-mm-root">{{ config.root.label | default('核心主题') }}</div>
    {% if config.root.children %}
    <div style="display:flex;justify-content:center;gap:24px;margin-top:16px">
      {% for ch in config.root.children %}<div class="evg-mm-branch">{{ ch.label }}</div>{% endfor %}
    </div>
    {% endif %}
  </div>
</div>
''';

String renderMindmap(Map<String, dynamic> comp) => renderTemplate(_tpl, comp);
