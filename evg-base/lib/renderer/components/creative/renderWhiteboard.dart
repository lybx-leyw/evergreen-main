/// HTML render: renderWhiteboard — 模板引擎渲染，读取 config.tools/colors/lineWidth。
library;

import '../shared/template_engine.dart';

const _iconMap = {
  'pen': '✏️',
  'eraser': '🧹',
  'shape': '⬜',
  'text': '🔤',
};

const _tpl = '''
<div class="evg-comp evg-comp-whiteboard">
  <div class="evg-wb-toolbar">
    {% for t in tools %}<button class="evg-wb-tool" title="工具">{{ t }}</button>{% endfor %}
    <span style="flex:1"></span>
    <button class="evg-wb-tool" title="撤销">↩️</button>
    <button class="evg-wb-tool" title="重做">↪️</button>
    <button class="evg-wb-tool" title="清空">🗑️</button>
  </div>
  <div class="evg-wb-canvas">
    <div class="evg-wb-placeholder">
      <span style="font-size:48px;opacity:.3">🎨</span>
      <span style="font-size:14px;color:var(--evg-text-secondary)">白板画布 — 线宽 {{ lineWidth }}</span>
    </div>
  </div>
</div>
''';

String renderWhiteboard(Map<String, dynamic> comp) {
  final cfg = comp['config'] as Map<String, dynamic>? ?? {};
  final tools = ((cfg['tools'] as List<dynamic>?) ?? const ['pen', 'eraser', 'shape', 'text'])
      .map((t) {
        final name = t is Map ? (t['name'] ?? t['type'] ?? '') : t.toString();
        return _iconMap[name] ?? '🔧';
      })
      .toList();
  final ctx = <String, dynamic>{...comp, 'tools': tools, 'lineWidth': cfg['lineWidth'] ?? 2};
  return renderTemplate(_tpl, ctx);
}
