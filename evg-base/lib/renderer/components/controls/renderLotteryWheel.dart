/// HTML render: renderLotteryWheel
import 'dart:convert';
import '../shared/html_helpers.dart';

String renderLotteryWheel(Map<String, dynamic> comp) {
  final cfg = (comp['config'] as Map<String, dynamic>? ?? {})['lottery'] as Map<String, dynamic>? ?? {};
  final title = cfg['title'] as String? ?? '幸运大转盘';
  final subtitle = cfg['subtitle'] as String? ?? '';
  final buttonText = cfg['buttonText'] as String? ?? '立即抽奖!';

  return '''
<div class="evg-comp evg-comp-lottery">
  <div class="evg-lottery-header">
    <div class="evg-comp-title">🎰 $title</div>
    ${subtitle.isNotEmpty ? '<div class="evg-lottery-sub">$subtitle</div>' : ''}
  </div>
  <div class="evg-lottery-wheel-container">
    <canvas class="evg-lottery-canvas" width="200" height="200"></canvas>
    <button class="evg-lottery-btn">🎯 $buttonText</button>
  </div>
  <div class="evg-lottery-history">
    <span style="font-size:11px;color:var(--evg-text-secondary)">📜 最近: 一等奖 二等奖 三等奖...</span>
  </div>
</div>''';
}
