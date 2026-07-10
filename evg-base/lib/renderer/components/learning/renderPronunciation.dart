/// HTML render: renderPronunciation
import 'dart:convert';
import '../shared/html_helpers.dart';

String renderPronunciation(Map<String, dynamic> comp) {
  final cfg = comp['config'] as Map<String, dynamic>? ?? {};
  final word = cfg['word'] as String? ?? 'hello';
  final phonetic = cfg['phonetic'] as String? ?? '/həˈloʊ/';

  return '''
<div class="evg-comp evg-comp-pronunciation">
  <div class="evg-comp-title">🔊 发音练习</div>
  <div class="evg-pron-word">${esc(word)}</div>
  <div class="evg-pron-phonetic">${esc(phonetic)}</div>
  <div class="evg-pron-controls">
    <button class="evg-pron-btn">▶ 播放</button>
    <button class="evg-pron-btn">🎤 录音</button>
    <button class="evg-pron-btn">🔄 对比</button>
  </div>
  <div class="evg-pron-score">
    <span style="color:var(--evg-text-secondary)">发音评分:</span>
    <span style="color:var(--evg-state-success);font-size:18px;font-weight:700">85</span>
    <span style="color:var(--evg-text-secondary)">/100</span>
  </div>
</div>''';
}
