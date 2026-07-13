/// HTML render: renderLotteryWheel — 模板引擎渲染，读取 config.lottery(标题/奖项/按钮)。
library;

import '../shared/template_engine.dart';

const _tpl = '''
<div class="evg-comp evg-comp-lottery">
  <div class="evg-lottery-header">
    <div class="evg-comp-title">🎰 {{ config.lottery.title | default('幸运大转盘') }}</div>
    {% if config.lottery.subtitle %}<div class="evg-lottery-sub">{{ config.lottery.subtitle }}</div>{% endif %}
  </div>
  <div class="evg-lottery-wheel-container">
    <canvas class="evg-lottery-canvas" width="200" height="200"></canvas>
    <button class="evg-lottery-btn">🎯 {{ config.lottery.buttonText | default('立即抽奖!') }}</button>
  </div>
  <div class="evg-lottery-history">
    <span style="font-size:11px;color:var(--evg-text-secondary)">📜 奖项: {% for s in config.lottery.segments %}{{ s }}{% if not loop.last %} / {% endif %}{% endfor %}</span>
  </div>
</div>
''';

String renderLotteryWheel(Map<String, dynamic> comp) => renderTemplate(_tpl, comp);
