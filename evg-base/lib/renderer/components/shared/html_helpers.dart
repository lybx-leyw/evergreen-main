/// Shared HTML render helpers — used by render functions across all component domains.
library;

import 'dart:convert';

String esc(String s) => s
    .replaceAll('&', '&amp;').replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll("'", '&#39;');

String renderEmpty(String type, String hint) =>
    '<div class="evg-placeholder evg-empty"><span class="evg-placeholder-icon">${componentIcon(type)}</span>'
    '<span class="evg-placeholder-text">$hint</span></div>';

String renderPlaceholder(String type, Map<String, dynamic> config) {
  final cfg = config.isNotEmpty ? ' config="${esc(jsonEncode(config))}"' : '';
  return '<div class="evg-placeholder"$cfg>'
         '<span class="evg-placeholder-icon">${componentIcon(type)}</span>'
         '<span class="evg-placeholder-text">$type</span></div>';
}

String renderGeneric(Map<String, dynamic> comp) {
  final type = comp['type'] ?? 'unknown';
  return '<div class="evg-placeholder evg-unknown"><span class="evg-placeholder-icon">📦</span>'
         '<span class="evg-placeholder-text">$type</span></div>';
}

String componentIcon(String type) {
  const map = {
    'ai-assistant': '🤖', 'chat': '💬', 'form': '📝', 'settings': '⚙️',
    'code-editor': '⌨️', 'data-table': '📊', 'chart': '📈', 'stat-tile': '📊',
    'card-list': '📋', 'kanban': '📌', 'tree': '🌲', 'timeline': '⏳', 'map': '🗺️',
    'document': '📄', 'video-player': '🎬', 'audio-player': '🎵',
    'image-gallery': '🖼', 'presentation': '📊', 'spreadsheet': '📈',
    'notepad': '📝', 'whiteboard': '🎨', 'mindmap': '🧠', 'diff-viewer': '🔍',
    'terminal': '💻', 'type-check': '⌨️', 'flashcards': '📇', 'quiz': '❓',
    'crossword': '🔢', 'pronunciation': '🎙', 'prompt-builder': '💡',
    'data-dashboard': '📊', 'calendar': '📅', 'timetable': '📅',
    'lottery-wheel': '🎰', 'custom': '📋', 'webview': '🌐',
    'button': '🔘', 'nav-button': '🔁', 'divider': '―',
  };
  return map[type] ?? '📦';
}

String renderBarChart(String title, Map<String, dynamic> cfg, bool legend) {
  final data = (cfg['data'] as List<dynamic>?) ?? [];
  if (data.isEmpty) return '<div class="evg-chart"><div class="evg-placeholder">暂无数据</div></div>';
  final maxVal = data.fold<double>(0, (m, e) {
    if (e is! Map) return m;
    final v = (e['value'] is num) ? (e['value'] as num).toDouble() : 0.0;
    return v > m ? v : m;
  });
  final bars = data.map((e) {
    if (e is! Map) return '';
    final label = esc((e['label'] ?? '').toString());
    final value = (e['value'] is num) ? (e['value'] as num).toDouble() : 0.0;
    final pct = maxVal > 0 ? (value / maxVal * 100).toInt() : 0;
    return '<div class="evg-bar-item"><span class="evg-bar-label">$label</span>'
           '<div class="evg-bar-track"><div class="evg-bar-fill" style="width:${pct}%"></div></div>'
           '<span class="evg-bar-value">$value</span></div>';
  }).join('');
  return '<div class="evg-chart">${title.isNotEmpty ? '<div class="evg-comp-title">${esc(title)}</div>' : ''}<div class="evg-bars">$bars</div></div>';
}

String renderPieChart(String title, bool donut, bool legend, Map<String, dynamic> cfg) {
  final inner = donut ? '<circle class="evg-donut-hole" r="35" cx="60" cy="60"/>' : '';
  return '<div class="evg-chart">${title.isNotEmpty ? '<div class="evg-comp-title">${esc(title)}</div>' : ''}'
         '<svg viewBox="0 0 120 120" class="evg-pie-svg">$inner<circle class="evg-pie-placeholder" r="60" cx="60" cy="60"/></svg></div>';
}

String renderLineChart(String title, String type, Map<String, dynamic> cfg) {
  return '<div class="evg-chart">${title.isNotEmpty ? '<div class="evg-comp-title">${esc(title)}</div>' : ''}'
         '<svg viewBox="0 0 400 200" class="evg-line-svg"><polyline class="evg-line-placeholder"/></svg></div>';
}

String renderDataTableHTML(String title, List<dynamic> columns, bool filter, bool sortable, List<Map<String, dynamic>> rows) {
  final headers = columns.map((c) {
    final label = esc(c is Map ? (c['label'] ?? c['key'] ?? '') as String : c.toString());
    return '<th>$label</th>';
  }).join('');
  final body = rows.map((row) {
    final cells = columns.map((c) {
      final key = c is Map ? (c['key'] ?? '') as String : c.toString();
      final val = esc((row[key] ?? '').toString());
      return '<td>$val</td>';
    }).join('');
    return '<tr>$cells</tr>';
  }).join('');
  return '<div class="evg-comp">${title.isNotEmpty ? '<div class="evg-comp-title">${esc(title)}</div>' : ''}'
         '<table class="evg-dt">${columns.isNotEmpty ? '<thead><tr>$headers</tr></thead>' : ''}<tbody>$body</tbody></table></div>';
}

String renderDataCards(String title, List<dynamic> columns, [List<Map<String, dynamic>>? rowsParam]) {
  final cards = (rowsParam ?? []).map((row) {
    final items = columns.map((c) {
      final key = c is Map ? (c['key'] ?? '') as String : c.toString();
      final lbl = c is Map ? (c['label'] ?? key) as String : '';
      final val = esc((row[key] ?? '').toString());
      return '<div class="evg-dc-item"><span class="evg-dc-label">${esc(lbl)}</span><span class="evg-dc-value">$val</span></div>';
    }).join('');
    return '<div class="evg-dc-card">$items</div>';
  }).join('');
  return '<div class="evg-comp">${title.isNotEmpty ? '<div class="evg-comp-title">${esc(title)}</div>' : ''}'
         '<div class="evg-dc-grid">$cards</div></div>';
}

String sampleCell(String key, String label, List<Map<String, dynamic>> rows) {
  final cells = rows.map((r) => '<td>${esc((r[key] ?? '').toString())}</td>').join('');
  return '<td>$cells</td>';
}

String langExt(String lang) => switch (lang) {
  'dart' => 'dart', 'python' => 'py', 'javascript' => 'js', 'typescript' => 'ts',
  'java' => 'java', 'c' => 'c', 'cpp' => 'cpp', 'rust' => 'rs', 'go' => 'go',
  _ => 'txt',
};

String lineDiff(List<String> left, List<String> right) {
  int n = left.length > right.length ? left.length : right.length;
  var buf = StringBuffer();
  for (int i = 0; i < n; i++) {
    String l = i < left.length ? esc(left[i]) : '';
    String r = i < right.length ? esc(right[i]) : '';
    String cls = 'evg-diff-eq';
    if (i >= left.length) cls = 'evg-diff-add';
    else if (i >= right.length) cls = 'evg-diff-del';
    else if (l != r) { cls = 'evg-diff-mod'; l = '<del>$l</del>'; r = '<ins>$r</ins>'; }
    buf.write('<tr class="$cls"><td class="evg-diff-ln">${i + 1}</td><td>$l</td><td class="evg-diff-ln">${i + 1}</td><td>$r</td></tr>');
  }
  return buf.toString();
}

String jsStr(String s) => "'${s.replaceAll("'", "\\'")}'";

const Map<String, String> codeSamples = {
  'dart': "import 'package:flutter/material.dart';\n\nclass Demo extends StatelessWidget {\n  @override\n  Widget build(BuildContext context) {\n    return const Text('Hello');\n  }\n}",
  'python': "def hello():\n    print('Hello, World!')\n\nif __name__ == '__main__':\n    hello()",
};
