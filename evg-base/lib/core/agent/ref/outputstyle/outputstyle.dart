/// Port of reasonix/internal/outputstyle.
///
/// Selectable output style / persona appended to (or replacing) the system prompt.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../frontmatter/frontmatter.dart' as fm;

class OutputStyle {
  final String name;
  final String description;
  final String body;
  final bool keepCoding;
  final bool builtin;
  final String path;

  const OutputStyle({
    required this.name,
    this.description = '',
    this.body = '',
    this.keepCoding = true,
    this.builtin = false,
    this.path = '',
  });
}

const _builtins = [
  OutputStyle(
    name: 'explanatory',
    description: 'Explain non-obvious implementation choices as you go',
    keepCoding: true,
    builtin: true,
    body: 'Communication style — Explanatory: as you work, surface the reasoning behind '
        'non-obvious choices. After a substantive change, add a short "## Insight" note '
        'covering the key trade-off or why an alternative was rejected. Teach the why, not just the what; keep it brief.',
  ),
  OutputStyle(
    name: 'learning',
    description: 'Collaborate and leave TODO(human) stubs for the user to complete',
    keepCoding: true,
    builtin: true,
    body: 'Communication style — Learning: work collaboratively rather than doing everything. '
        'When a meaningful implementation decision comes up, pause and ask the user to make the call. '
        'For the most instructive pieces, write the surrounding code but leave a small, clearly-marked '
        '`TODO(human)` stub with a one-line description for the user to implement themselves.',
  ),
  OutputStyle(
    name: 'concise',
    description: 'Terse replies: minimal prose, code and bullets only',
    keepCoding: true,
    builtin: true,
    body: 'Communication style — Concise: keep replies terse. No preamble or postamble, no restating '
        'the request. Prefer code and short bullet points over paragraphs; answer in the fewest words that are still clear.',
  ),
];

const _conventionDirs = ['.reasonix', '.agents', '.agent', '.claude'];

List<String> dirs() {
  final dirs = <String>[];
  final reasonixHome = Platform.environment['REASONIX_HOME'];
  if (reasonixHome == null || reasonixHome.isEmpty) {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'];
    if (home != null && home.isNotEmpty) {
      for (final v in _conventionDirs.reversed) {
        dirs.add(p.join(home, v, 'output-styles'));
      }
    }
  }
  for (final v in _conventionDirs.reversed) {
    dirs.add(p.join('.', v, 'output-styles'));
  }
  return dirs;
}

List<OutputStyle> list(List<String> dirs) {
  final byName = <String, OutputStyle>{};
  for (final b in _builtins) {
    byName[b.name.toLowerCase()] = b;
  }
  for (final dir in dirs) {
    final d = Directory(dir);
    if (!d.existsSync()) continue;
    for (final entity in d.listSync(followLinks: false)) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('.md')) continue;
      final parsed = _parseFile(entity.path);
      if (parsed == null) continue;
      byName[parsed.name.toLowerCase()] = parsed;
    }
  }
  final out = byName.values.toList();
  out.sort((a, b) => a.name.compareTo(b.name));
  return out;
}

OutputStyle? resolve(String name, List<String> dirs) {
  final n = name.trim().toLowerCase();
  if (n.isEmpty || n == 'default') return null;
  for (final st in list(dirs)) {
    if (st.name.toLowerCase() == n) return st;
  }
  return null;
}

String apply(String base, OutputStyle st) {
  final body = st.body.trim();
  if (body.isEmpty) return base;
  if (!st.keepCoding) return body;
  if (base.trim().isEmpty) return body;
  return '$base\n\n$body';
}

OutputStyle? _parseFile(String path) {
  try {
    final bytes = File(path).readAsBytesSync();
    final text = utf8.decode(bytes, allowMalformed: true);
    final (meta, body) = fm.split(text);
    var name = meta['name'] ?? '';
    if (name.isEmpty) {
      name = p.basenameWithoutExtension(path);
    }
    final trimmedBody = body.trim();
    if (trimmedBody.isEmpty) return null;
    var keep = true;
    if (meta.containsKey('keep-coding-instructions')) {
      keep = !_isFalse(meta['keep-coding-instructions']!);
    }
    return OutputStyle(
      name: name,
      description: meta['description'] ?? '',
      body: trimmedBody,
      keepCoding: keep,
      path: path,
    );
  } on Exception {
    return null;
  }
}

bool _isFalse(String s) {
  switch (s.trim().toLowerCase()) {
    case 'false':
    case 'no':
    case '0':
    case 'off':
      return true;
  }
  return false;
}

String describeList(List<OutputStyle> styles, String active) {
  final buf = StringBuffer();
  for (final st in styles) {
    final marker = st.name.toLowerCase() == active.toLowerCase() ? '* ' : '  ';
    final scope = st.builtin ? 'builtin' : 'custom';
    buf.writeln('$marker${st.name} ($scope) — ${st.description}');
  }
  final s = buf.toString();
  return s.endsWith('\n') ? s.substring(0, s.length - 1) : s;
}
