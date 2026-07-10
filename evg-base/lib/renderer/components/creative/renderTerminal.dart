/// HTML render: renderTerminal
import 'dart:convert';
import '../shared/html_helpers.dart';

String renderTerminal(Map<String, dynamic> comp) {
  final cfg = comp['config'] as Map<String, dynamic>? ?? {};
  final cwd = cfg['cwd'] as String? ?? '~/projects';
  const lines = [
    {'prompt': '❯', 'text': 'git status', 'color': '#58a6ff'},
    {'prompt': '', 'text': 'On branch main', 'color': '#c9d1d9'},
    {'prompt': '', 'text': 'nothing to commit, working tree clean', 'color': '#3fb950'},
    {'prompt': '❯', 'text': 'ls -la', 'color': '#58a6ff'},
    {'prompt': '', 'text': 'total 24', 'color': '#c9d1d9'},
    {'prompt': '', 'text': 'drwxr-xr-x  5 user  staff   160 Jul  6 14:00 .', 'color': '#8b949e'},
    {'prompt': '', 'text': 'drwxr-xr-x  3 user  staff    96 Jul  6 13:00 ..', 'color': '#8b949e'},
    {'prompt': '', 'text': '-rw-r--r--  1 user  staff  1024 Jul  6 14:00 README.md', 'color': '#8b949e'},
    {'prompt': '❯', 'text': '<span class="evg-term-cursor">█</span>', 'color': '#58a6ff'},
  ];

  final linesHtml = lines.map((l) {
    final prompt = l['prompt'] as String;
    final text = l['text'] as String;
    final color = l['color'] as String;
    return '<div class="evg-term-line">${prompt.isNotEmpty ? '<span class="evg-term-prompt">$prompt</span>' : ''}<span style="color:$color">$text</span></div>';
  }).join('');

  return '''
<div class="evg-comp evg-comp-terminal">
  <div class="evg-term-header">
    <span class="evg-term-dot" style="background:#ff5f56"></span>
    <span class="evg-term-dot" style="background:#ffbd2e"></span>
    <span class="evg-term-dot" style="background:#27c93f"></span>
    <span class="evg-term-title">${esc(cwd)} — bash</span>
  </div>
  <div class="evg-term-body">$linesHtml</div>
</div>''';
}
