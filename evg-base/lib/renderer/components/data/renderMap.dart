/// HTML render: renderMap — 模板引擎渲染，读取 config.map.center/markers。
library;

import '../shared/template_engine.dart';

const _tpl = '''
<div class="evg-comp evg-comp-map">
  <div class="evg-map-placeholder">
    <div class="evg-map-pin">📍</div>
    <div class="evg-map-coords">{{ config.map.center.lat | default('39.9042') }}, {{ config.map.center.lng | default('116.4074') }}</div>
    {% if config.map.markers %}
    <div class="evg-map-markers">
      {% for m in config.map.markers %}
      <div class="evg-map-marker">📌 {{ m.label | default('标记') }}</div>
      {% endfor %}
    </div>
    {% endif %}
    <div class="evg-map-zoom">
      <button>+</button><button>−</button>
    </div>
  </div>
</div>
''';

String renderMap(Map<String, dynamic> comp) => renderTemplate(_tpl, comp);
