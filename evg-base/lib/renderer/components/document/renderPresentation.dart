/// HTML render: renderPresentation — 模板引擎渲染，读取 config.slides。
library;

import '../shared/template_engine.dart';

const _tpl = '''
<div class="evg-comp evg-comp-pres">
  {% if config.slides %}
  {% for s in config.slides %}
  <div class="evg-pres-slide">
    <div class="evg-pres-title">{{ s.title | default('幻灯片') }}</div>
    <div class="evg-pres-content"><p>{{ s.content }}</p></div>
    <div class="evg-pres-page">{{ loop.index }} / {{ len(config.slides) }}</div>
  </div>
  {% endfor %}
  {% else %}
  <div class="evg-pres-slide">
    <div class="evg-pres-title">幻灯片演示</div>
    <div class="evg-pres-content"><p>暂无幻灯片内容</p></div>
  </div>
  {% endif %}
  <div class="evg-pres-nav">
    <button>◀ 上一页</button>
    <button>下一页 ▶</button>
  </div>
</div>
''';

String renderPresentation(Map<String, dynamic> comp) => renderTemplate(_tpl, comp);
