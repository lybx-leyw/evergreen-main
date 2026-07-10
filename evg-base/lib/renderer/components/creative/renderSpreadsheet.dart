/// HTML render: renderSpreadsheet
import 'dart:convert';
import '../shared/html_helpers.dart';

String renderSpreadsheet(Map<String, dynamic> comp) {
  const cols = ['A', 'B', 'C', 'D', 'E'];

  return '''
<div class="evg-comp evg-comp-sheet">
  <div class="evg-sheet-header">
    <span>📊 电子表格</span>
    <span style="font-size:11px;color:var(--evg-text-secondary)">10列 × 50行</span>
  </div>
  <div class="evg-sheet-table">
    <table>
      <thead><tr><th></th>${cols.map((c) => '<th>$c</th>').join('')}</tr></thead>
      <tbody>${[1, 2, 3, 4, 5].map((r) => '<tr><td class="evg-row-num">$r</td>${cols.map((c) => '<td contenteditable="true">${c == 'A' ? '数据$r' : ''}</td>').join('')}</tr>').join('')}</tbody>
    </table>
  </div>
</div>''';
}
