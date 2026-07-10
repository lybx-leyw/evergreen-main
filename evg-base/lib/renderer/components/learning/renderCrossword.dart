/// HTML render: renderCrossword
import 'dart:convert';
import '../shared/html_helpers.dart';

// 简单 5x5 填字网格
const _crosswordGrid = <List<String?>>[
  ['D', 'E', 'F', null, null],
  [null, null, 'O', null, null],
  ['L', 'I', 'S', 'T', null],
  [null, null, null, null, null],
  [null, null, null, null, null],
];

String renderCrossword(Map<String, dynamic> comp) {
  final cfg = comp['config'] as Map<String, dynamic>? ?? {};
  final title = cfg['title'] as String? ?? '填字游戏';

  // 简单 5x5 网格
  final gridHtml = List.generate(5, (row) {
    final cells = List.generate(5, (col) {
      final letter = _crosswordGrid[row][col];
      return '<div class="evg-cw-cell${letter != null ? ' filled' : ''}">${letter ?? ''}</div>';
    }).join('');
    return '<div class="evg-cw-row">$cells</div>';
  }).join('');

  return '''
<div class="evg-comp evg-comp-crossword">
  <div class="evg-comp-title">🔤 ${esc(title)}</div>
  <div class="evg-cw-grid">$gridHtml</div>
  <div class="evg-cw-clues">
    <div class="evg-cw-clue-title">横向:</div>
    <div class="evg-cw-clue">1. Python关键字 — def</div>
    <div class="evg-cw-clue">2. 列表声明 — list</div>
    <div class="evg-cw-clue-title" style="margin-top:8px">纵向:</div>
    <div class="evg-cw-clue">1. 数据类型 — dict</div>
    <div class="evg-cw-clue">2. 循环 — for</div>
  </div>
</div>''';
}
