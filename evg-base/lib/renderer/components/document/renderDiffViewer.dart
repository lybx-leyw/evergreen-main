/// HTML render: renderDiffViewer
import 'dart:convert';
import '../shared/html_helpers.dart';

String renderDiffViewer(Map<String, dynamic> comp) {
  final cfg = comp['config'] as Map<String, dynamic>? ?? {};
  final leftLabel = cfg['leftLabel'] as String? ?? '原文件';
  final rightLabel = cfg['rightLabel'] as String? ?? '新文件';

  // 示例 diff 行
  const diffLines = [
    {'type': 'same', 'text': 'import json'},
    {'type': 'same', 'text': 'from pathlib import Path'},
    {'type': 'same', 'text': ''},
    {'type': 'del', 'text': '- def old_function():'},
    {'type': 'add', 'text': '+ def new_function(data: dict) -> dict:'},
    {'type': 'add', 'text': '+     """处理数据并返回结果"""'},
    {'type': 'same', 'text': '      result = {}'},
    {'type': 'del', 'text': '-     result["count"] = 0'},
    {'type': 'add', 'text': '+     result["count"] = len(data)'},
    {'type': 'same', 'text': '      return result'},
  ];

  final linesHtml = diffLines.map((l) {
    final cls = switch (l['type']) {
      'add' => 'evg-diff-add',
      'del' => 'evg-diff-del',
      _ => 'evg-diff-same',
    };
    return '<div class="evg-diff-line $cls"><code>${esc(l['text']!)}</code></div>';
  }).join('');

  return '''
<div class="evg-comp evg-comp-diff">
  <div class="evg-diff-header">
    <span class="evg-diff-label left">📄 ${esc(leftLabel)}</span>
    <span class="evg-diff-label right">📄 ${esc(rightLabel)}</span>
  </div>
  <div class="evg-diff-body">$linesHtml</div>
</div>''';
}
