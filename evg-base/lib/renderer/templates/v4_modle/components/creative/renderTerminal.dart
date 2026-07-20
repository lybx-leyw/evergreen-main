/// HTML render: renderTerminal — 模板引擎渲染，读取 config.cwd/lines（颜色经 hex 校验）。
library;
import 'package:evergreen_base/renderer/components/shared/template_engine.dart';

const _tpl = '''
<div class="evg-comp evg-comp-terminal">
  <div class="evg-term-header">
    <span class="evg-term-dot" style="background:#ff5f56"></span>
    <span class="evg-term-dot" style="background:#ffbd2e"></span>
    <span class="evg-term-dot" style="background:#27c93f"></span>
    <span class="evg-term-title">{{ config.cwd | default('~/projects') }} — bash</span>
  </div>
  <div class="evg-term-body">
    {% for l in config.lines %}
    <div class="evg-term-line">{% if l.prompt %}<span class="evg-term-prompt">{{ l.prompt }}</span>{% endif %}<span style="color:{{ l.color | hex }}">{{ l.text }}</span></div>
    {% endfor %}
  </div>
</div>
''';

String renderTerminal(Map<String, dynamic> comp) => renderTemplate(_tpl, comp);
