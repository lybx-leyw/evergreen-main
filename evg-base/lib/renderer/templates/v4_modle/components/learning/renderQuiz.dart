/// HTML render: renderQuiz
import 'dart:convert';
import 'package:evergreen_base/renderer/components/shared/html_helpers.dart';

String renderQuiz(Map<String, dynamic> comp) {
  final cfg = comp['config'] as Map<String, dynamic>? ?? {};
  final raw = cfg['wordList'];
  final words = raw is List ? raw : <dynamic>[];
  final types = (cfg['questionTypes'] as List<dynamic>? ?? []).cast<String>();
  final timeLimit = cfg['timeLimit'] as int? ?? 0;
  final passScore = cfg['passScore'] as int? ?? 0;

  if (words.isEmpty) {
    return renderEmpty('quiz', '暂无题目（运行时加载词库）');
  }

  final first = words.first;
  final qWord = first is Map ? (first['word'] ?? first['term'] ?? '') : first.toString();
  final qMeaning = first is Map ? (first['meaning'] ?? first['def'] ?? '') : '';
  // 取其它词的释义作为干扰项
  final distractors = words.skip(1).take(3).map((w) {
    final m = w is Map ? (w['meaning'] ?? w['def'] ?? '') : '';
    return m.toString();
  }).where((s) => s.isNotEmpty).toList();
  final options = [qMeaning.toString(), ...distractors];
  options.shuffle();

  final optsHtml = options.asMap().entries.map((e) {
    final letter = String.fromCharCode(65 + e.key);
    return '<label><input type="radio" name="q1" /> $letter. ${esc(e.value)}</label>';
  }).join('');

  return '''
<div class="evg-comp evg-comp-quiz">
  <div class="evg-comp-title">❓ 测验（${types.join('/')} · 限时 ${timeLimit}s · 及格 $passScore 分）</div>
  <div class="evg-quiz-question">
    <div class="evg-quiz-q">1. 「${esc(qWord.toString())}」的正确释义是？</div>
    <div class="evg-quiz-options">$optsHtml</div>
  </div>
  <button class="evg-quiz-submit">提交答案</button>
</div>''';
}
