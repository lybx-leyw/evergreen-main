/// HTML render: renderFlashcards
import 'dart:convert';
import 'package:evergreen_base/renderer/components/shared/html_helpers.dart';

String renderFlashcards(Map<String, dynamic> comp) {
  final cfg = comp['config'] as Map<String, dynamic>? ?? {};
  final raw = cfg['wordList'];
  final words = raw is List
      ? raw
      : <dynamic>[];
  final algorithm = cfg['algorithm'] as String? ?? 'spaced-repetition';
  final total = words.length;

  if (total == 0) {
    return renderEmpty('flashcards', '暂无词卡（运行时加载词库）');
  }

  final first = words.first;
  final front = first is Map ? (first['word'] ?? first['term'] ?? '') : first.toString();
  final back = first is Map ? (first['meaning'] ?? first['def'] ?? first['definition'] ?? '') : '';

  final cardsHtml = words.take(8).map((w) {
    final f = w is Map ? (w['word'] ?? w['term'] ?? '') : w.toString();
    final b = w is Map ? (w['meaning'] ?? w['def'] ?? w['definition'] ?? '') : '';
    return '''
<div class="evg-flash-card">
  <div class="evg-flash-front">${esc(f.toString())}</div>
  <div class="evg-flash-back"><code>${esc(b.toString())}</code></div>
</div>''';
  }).join('');

  return '''
<div class="evg-comp evg-comp-flash">
  <div class="evg-comp-title">🃏 闪卡复习（$algorithm）</div>
  <div class="evg-flash-deck">$cardsHtml</div>
  <div class="evg-flash-nav">
    <button>◀ 上一张</button><span>1 / $total</span><button>下一张 ▶</button>
    <button>翻转</button>
  </div>
</div>''';
}
