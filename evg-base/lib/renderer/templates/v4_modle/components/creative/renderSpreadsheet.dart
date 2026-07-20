/// HTML render: renderSpreadsheet — 模板引擎渲染，读取 config.columns/rows。
library;
import 'package:evergreen_base/renderer/components/shared/template_engine.dart';

const _tpl = '''
<div class="evg-comp evg-comp-sheet">
  <div class="evg-sheet-header">
    <span>📊 电子表格</span>
    <span style="font-size:11px;color:var(--evg-text-secondary)">{{ len(config.columns) }}列 × {{ len(config.rows) }}行</span>
  </div>
  <div class="evg-sheet-table">
    <table>
      <thead><tr><th></th>{% for c in config.columns %}<th>{{ c.label | default(c.key) }}</th>{% endfor %}</tr></thead>
      <tbody>
        {% for r in config.rows %}
        <tr><td class="evg-row-num">{{ loop.index }}</td>{% for c in config.columns %}<td contenteditable="true">{{ r | get(c.key) }}</td>{% endfor %}</tr>
        {% endfor %}
      </tbody>
    </table>
  </div>
</div>
''';

String renderSpreadsheet(Map<String, dynamic> comp) => renderTemplate(_tpl, comp);
