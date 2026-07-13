/// HTML render: renderPronunciation — 模板引擎渲染，读取 config.word/phonetic/score。
library;

import '../shared/template_engine.dart';

const _tpl = '''
<div class="evg-comp evg-comp-pronunciation">
  <div class="evg-comp-title">🔊 发音练习</div>
  <div class="evg-pron-word">{{ config.word | default('hello') }}</div>
  <div class="evg-pron-phonetic">{{ config.phonetic | default('/həˈloʊ/') }}</div>
  <div class="evg-pron-controls">
    <button class="evg-pron-btn">▶ 播放</button>
    <button class="evg-pron-btn">🎤 录音</button>
    <button class="evg-pron-btn">🔄 对比</button>
  </div>
  <div class="evg-pron-score">
    <span style="color:var(--evg-text-secondary)">发音评分:</span>
    <span style="color:var(--evg-state-success);font-size:18px;font-weight:700">{{ config.score | default(0) }}</span>
    <span style="color:var(--evg-text-secondary)">/100</span>
  </div>
</div>
''';

String renderPronunciation(Map<String, dynamic> comp) => renderTemplate(_tpl, comp);
