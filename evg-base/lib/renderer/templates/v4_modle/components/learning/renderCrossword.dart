/// HTML render: renderCrossword — 模板引擎渲染，读取 config.title/grid/clues。
library;
import 'package:evergreen_base/renderer/components/shared/template_engine.dart';

const _tpl = '''
<div class="evg-comp evg-comp-crossword">
  <div class="evg-comp-title">🔤 {{ config.title | default('填字游戏') }}</div>
  <div class="evg-cw-grid">
    {% for row in grid %}
    <div class="evg-cw-row">
      {% for cell in row %}<div class="evg-cw-cell{{ cell.cls }}">{{ cell.ch }}</div>{% endfor %}
    </div>
    {% endfor %}
  </div>
  <div class="evg-cw-clues">
    <div class="evg-cw-clue-title">横向:</div>
    {% for c in config.clues.across %}<div class="evg-cw-clue">1. {{ c }}</div>{% endfor %}
    <div class="evg-cw-clue-title" style="margin-top:8px">纵向:</div>
    {% for c in config.clues.down %}<div class="evg-cw-clue">1. {{ c }}</div>{% endfor %}
  </div>
</div>
''';

String renderCrossword(Map<String, dynamic> comp) {
  final cfg = comp['config'] as Map<String, dynamic>? ?? {};
  final grid = (cfg['grid'] as List<dynamic>? ?? [])
      .whereType<List>()
      .map((row) => row
          .map((c) => c is String
              ? <String, dynamic>{'ch': c, 'cls': ' filled'}
              : <String, dynamic>{'ch': '', 'cls': ''})
          .toList())
      .toList();
  final ctx = <String, dynamic>{...comp, 'grid': grid};
  return renderTemplate(_tpl, ctx);
}
