/// HTML render: renderDiffViewer — 模板引擎渲染，读取 config.lines/left/right/leftLabel/rightLabel。
library;
import 'package:evergreen_base/renderer/components/shared/template_engine.dart';

const _tpl = '''
<div class="evg-comp evg-comp-diff">
  <div class="evg-diff-header">
    <span class="evg-diff-label left">📄 {{ config.leftLabel | default('原文件') }}</span>
    <span class="evg-diff-label right">📄 {{ config.rightLabel | default('新文件') }}</span>
  </div>
  <div class="evg-diff-body">
    {% for l in diffLines %}<div class="evg-diff-line {{ l.cls }}"><code>{{ l.text }}</code></div>{% endfor %}
  </div>
</div>
''';

String renderDiffViewer(Map<String, dynamic> comp) {
  final cfg = comp['config'] as Map<String, dynamic>? ?? {};
  final lines = (cfg['lines'] as List<dynamic>? ?? [])
      .whereType<Map>()
      .map((e) => e.cast<String, dynamic>())
      .toList();
  final left = cfg['left'] as String?;
  final right = cfg['right'] as String?;

  final diffLines = lines.isNotEmpty
      ? lines.map((l) {
          final type = l['type'] as String? ?? 'same';
          final cls = type == 'add'
              ? 'evg-diff-add'
              : type == 'del'
                  ? 'evg-diff-del'
                  : 'evg-diff-same';
          return <String, dynamic>{'cls': cls, 'text': l['text'] ?? ''};
        }).toList()
      : <Map<String, dynamic>>[
          if (left != null) {'cls': 'evg-diff-del', 'text': left},
          if (right != null) {'cls': 'evg-diff-add', 'text': right},
        ];

  final ctx = <String, dynamic>{...comp, 'diffLines': diffLines};
  return renderTemplate(_tpl, ctx);
}
