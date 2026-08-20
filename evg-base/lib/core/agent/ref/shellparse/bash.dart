/// Port of reasonix/internal/shellparse/bash.go.
///
/// Dart translation note: the Go implementation uses `mvdan.cc/sh/v3/syntax`.
/// This port implements a conservative static Bash scanner covering the
/// behaviors the Go tests and runtime callers depend on: static argv fields,
/// top-level splitting, glob detection, approval features, and failure-masking
/// analysis. It never evaluates shell expansion or runs a shell.
library;

class StaticCommandPolicy {
  final bool allowEnvAssignments;
  final bool allowStderrToStdout;

  const StaticCommandPolicy({
    this.allowEnvAssignments = false,
    this.allowStderrToStdout = false,
  });
}

class StaticCommand {
  List<String> argv = [];
  List<String> env = [];
  bool mergeStderr = false;
}

enum StaticRejectReason {
  parse,
  hereDoc,
  control,
  redirection,
  assignment,
  expansion
}

class StaticRejectError implements Exception {
  final StaticRejectReason reason;
  final String detail;

  StaticRejectError(this.reason, [this.detail = '']);

  @override
  String toString() => detail.isEmpty ? reason.name : detail;
}

class ApprovalFeatures {
  List<String> commandPrefix = [];
  bool dynamicCommandName = false;
  bool nestedExecution = false;
  bool expansion = false;
  bool assignment = false;
  bool redirection = false;
}

class _ParseException implements Exception {
  final String message;
  _ParseException(this.message);
}

class _Token {
  final String kind; // word, op, redir
  final String text;
  final int start;
  final int end;
  final bool dynamic;
  final bool quoted;
  final bool glob;

  _Token({
    required this.kind,
    required this.text,
    required this.start,
    required this.end,
    this.dynamic = false,
    this.quoted = false,
    this.glob = false,
  });
}

class _ScanResult {
  final List<_Token> tokens;
  final bool hasHeredoc;
  final bool hasCompound;

  _ScanResult(this.tokens,
      {required this.hasHeredoc, required this.hasCompound});
}

/// Parses [command] with a conservative Bash scanner and returns tokenized
/// top-level syntax. Throws [_ParseException] for unterminated quotes or
/// substitutions.
_ScanResult _scan(String source) {
  final tokens = <_Token>[];
  var i = 0;
  var hasHeredoc = false;
  var hasCompound = false;
  var firstWord = true;

  void addOp(String op, int start, int end) {
    tokens.add(_Token(kind: 'op', text: op, start: start, end: end));
  }

  while (i < source.length) {
    final c = source[i];
    if (c == ' ' || c == '\t' || c == '\r' || c == '\f') {
      i++;
      continue;
    }
    if (c == '\n') {
      addOp('newline', i, i + 1);
      firstWord = true;
      i++;
      continue;
    }
    if (c == '#') {
      while (i < source.length && source[i] != '\n') {
        i++;
      }
      continue;
    }

    // Operators.
    final two = i + 1 < source.length ? source.substring(i, i + 2) : '';
    if (two == '&&' ||
        two == '||' ||
        two == '|&' ||
        two == '>>' ||
        two == '<<' ||
        two == '<<<' ||
        two == '>&') {
      if (two == '<<' && (i + 2 >= source.length || source[i + 2] != '<')) {
        hasHeredoc = true;
      }
      addOp(two, i, i + 2);
      firstWord = true;
      i += 2;
      continue;
    }
    if (c == '|' || c == ';' || c == '&' || c == '>' || c == '<') {
      addOp(c, i, i + 1);
      firstWord = true;
      i++;
      continue;
    }

    // Word.
    final start = i;
    final buf = StringBuffer();
    var dynamic = false;
    var quoted = false;
    var glob = false;
    var closed = true;

    while (i < source.length) {
      final w = source[i];
      if (w == ' ' || w == '\t' || w == '\r' || w == '\f' || w == '\n') break;
      // Process substitution is part of a word/argument, not a top-level
      // redirection operator.
      if ((w == '<' || w == '>') &&
          i + 1 < source.length &&
          source[i + 1] == '(') {
        dynamic = true;
        final end = _skipBalanced(source, i + 1, '(', ')');
        if (end < 0) {
          closed = false;
          break;
        }
        buf.write(source.substring(i, end + 1));
        i = end + 1;
        continue;
      }
      if (w == '&' || w == '|' || w == ';' || w == '>' || w == '<') break;
      if (i + 1 < source.length &&
          (source.substring(i, i + 2) == '&&' ||
              source.substring(i, i + 2) == '||' ||
              source.substring(i, i + 2) == '|&' ||
              source.substring(i, i + 2) == '>>' ||
              source.substring(i, i + 2) == '<<' ||
              source.substring(i, i + 2) == '<<<' ||
              source.substring(i, i + 2) == '>&')) {
        break;
      }

      if (w == '\\') {
        if (i + 1 >= source.length) {
          closed = false;
          break;
        }
        buf.write(source[i + 1]);
        i += 2;
        continue;
      }
      if (w == '\'') {
        quoted = true;
        final close = source.indexOf('\'', i + 1);
        if (close < 0) {
          closed = false;
          break;
        }
        buf.write(source.substring(i + 1, close));
        i = close + 1;
        continue;
      }
      if (w == '"') {
        quoted = true;
        var j = i + 1;
        final inner = StringBuffer();
        var dqClosed = false;
        while (j < source.length) {
          final q = source[j];
          if (q == '\\' &&
              j + 1 < source.length &&
              (source[j + 1] == '"' ||
                  source[j + 1] == r'$' ||
                  source[j + 1] == '`' ||
                  source[j + 1] == '\\')) {
            inner.write(source[j + 1]);
            j += 2;
            continue;
          }
          if (q == '"') {
            dqClosed = true;
            j++;
            break;
          }
          if (q == r'$' || q == '`') dynamic = true;
          inner.write(q);
          j++;
        }
        if (!dqClosed) {
          closed = false;
          break;
        }
        buf.write(inner.toString());
        i = j;
        continue;
      }
      if (w == '`') {
        dynamic = true;
        final close = source.indexOf('`', i + 1);
        if (close < 0) {
          closed = false;
          break;
        }
        buf.write(source.substring(i + 1, close));
        i = close + 1;
        continue;
      }
      if (w == r'$' && i + 1 < source.length && source[i + 1] == '(') {
        dynamic = true;
        final end = _skipBalanced(source, i + 1, '(', ')');
        if (end < 0) {
          closed = false;
          break;
        }
        buf.write(source.substring(i, end + 1));
        i = end + 1;
        continue;
      }
      if ((w == '<' || w == '>') &&
          i + 1 < source.length &&
          source[i + 1] == '(') {
        dynamic = true;
        final end = _skipBalanced(source, i + 1, '(', ')');
        if (end < 0) {
          closed = false;
          break;
        }
        buf.write(source.substring(i, end + 1));
        i = end + 1;
        continue;
      }
      if (w == r'$') {
        dynamic = true;
      }
      if (!quoted &&
          (w == '{' ||
              (w == '@' && i + 1 < source.length && source[i + 1] == '(') ||
              (w == '!' && i + 1 < source.length && source[i + 1] == '(') ||
              (w == '?' && i + 1 < source.length && source[i + 1] == '(') ||
              (w == '*' && i + 1 < source.length && source[i + 1] == '(') ||
              (w == '+' && i + 1 < source.length && source[i + 1] == '('))) {
        dynamic = true;
      }
      if (!quoted && (w == '*' || w == '?' || w == '[')) glob = true;
      buf.write(w);
      i++;
    }

    if (!closed) {
      throw _ParseException('unterminated shell token');
    }
    if (i == start) {
      // Should not happen; advance defensively.
      i++;
      continue;
    }
    final raw = source.substring(start, i);
    final isAssignment = firstWord && _isAssignmentRaw(raw);
    tokens.add(_Token(
      kind: isAssignment ? 'assignment' : 'word',
      text: raw,
      start: start,
      end: i,
      dynamic: dynamic,
      quoted: quoted,
      glob: glob,
    ));
    if (firstWord && !isAssignment) {
      final lowered = _unquote(raw).toLowerCase();
      if (lowered == 'if' ||
          lowered == 'for' ||
          lowered == 'while' ||
          lowered == 'until' ||
          lowered == 'case' ||
          lowered == 'function' ||
          lowered == '{' ||
          lowered == '(' ||
          lowered == '[[') {
        hasCompound = true;
      }
      firstWord = false;
    }
  }

  return _ScanResult(tokens, hasHeredoc: hasHeredoc, hasCompound: hasCompound);
}

int _skipBalanced(String s, int openIndex, String open, String close) {
  var depth = 0;
  var i = openIndex;
  while (i < s.length) {
    if (s[i] == '\'') {
      final end = s.indexOf('\'', i + 1);
      if (end < 0) return -1;
      i = end + 1;
      continue;
    }
    if (s[i] == '"') {
      var j = i + 1;
      while (j < s.length) {
        if (s[j] == '\\') {
          j += 2;
          continue;
        }
        if (s[j] == '"') break;
        j++;
      }
      if (j >= s.length) return -1;
      i = j + 1;
      continue;
    }
    if (s[i] == open) depth++;
    if (s[i] == close) {
      depth--;
      if (depth == 0) return i;
    }
    i++;
  }
  return -1;
}

bool _isAssignmentRaw(String raw) {
  final eq = raw.indexOf('=');
  if (eq <= 0) return false;
  final name = raw.substring(0, eq);
  if (name.isEmpty) return false;
  for (var i = 0; i < name.length; i++) {
    final c = name.codeUnitAt(i);
    final ok = c == 0x5F ||
        (c >= 0x41 && c <= 0x5A) ||
        (c >= 0x61 && c <= 0x7A) ||
        (i > 0 && c >= 0x30 && c <= 0x39);
    if (!ok) return false;
  }
  return true;
}

String _unquote(String raw) {
  final out = StringBuffer();
  var i = 0;
  while (i < raw.length) {
    final c = raw[i];
    if (c == '\\' && i + 1 < raw.length) {
      out.write(raw[i + 1]);
      i += 2;
      continue;
    }
    if (c == '\'') {
      final end = raw.indexOf('\'', i + 1);
      if (end > 0) {
        out.write(raw.substring(i + 1, end));
        i = end + 1;
        continue;
      }
    }
    out.write(c);
    i++;
  }
  return out.toString();
}

String _staticFieldsMessage(Object error) {
  if (error is StaticRejectError) {
    switch (error.reason) {
      case StaticRejectReason.parse:
        return error.toString();
      case StaticRejectReason.hereDoc:
        return 'here document';
      case StaticRejectReason.expansion:
        return 'shell expansion';
      default:
        return 'shell control syntax';
    }
  }
  if (error is _ParseException) return error.message;
  return error.toString();
}

/// Returns the fields of a single static Bash command, or a rejection message.
(List<String>, String) staticFields(String command) {
  try {
    final cmd = parseStaticCommand(command, const StaticCommandPolicy());
    return (cmd.argv, '');
  } catch (e) {
    return (const [], _staticFieldsMessage(e));
  }
}

/// Parses a single static Bash command into argv and optional environment
/// assignments. It never evaluates shell expansion or runs a shell.
StaticCommand parseStaticCommand(String command, StaticCommandPolicy policy) {
  final out = StaticCommand();
  if (command.trim().isEmpty) return out;
  final _ScanResult scan;
  try {
    scan = _scan(command);
  } on _ParseException catch (e) {
    throw StaticRejectError(StaticRejectReason.parse, e.message);
  }
  if (scan.hasHeredoc) throw StaticRejectError(StaticRejectReason.hereDoc);
  if (scan.hasCompound) throw StaticRejectError(StaticRejectReason.control);

  final ops =
      scan.tokens.where((t) => t.kind == 'op' || t.kind == 'redir').toList();
  if (ops.any((t) =>
      t.text == '&&' ||
      t.text == '||' ||
      t.text == '|' ||
      t.text == '|&' ||
      t.text == ';' ||
      t.text == '&' ||
      t.text == 'newline')) {
    throw StaticRejectError(StaticRejectReason.control);
  }
  final redirs = ops
      .where((t) =>
          t.text == '>' ||
          t.text == '<' ||
          t.text == '>>' ||
          t.text == '<<<' ||
          t.text == '>&')
      .toList();
  if (redirs.isNotEmpty) {
    if (!policy.allowStderrToStdout ||
        redirs.length != 1 ||
        !_isStderrToStdout(scan.tokens, redirs.first)) {
      throw StaticRejectError(StaticRejectReason.redirection);
    }
    out.mergeStderr = true;
  }

  // Redirection operands (fd numbers and target words) are not argv entries.
  final redirOperandIndices = <int>{};
  for (final redir in redirs) {
    final idx = scan.tokens.indexOf(redir);
    if (idx > 0 &&
        scan.tokens[idx - 1].kind == 'word' &&
        RegExp(r'^\d+$').hasMatch(scan.tokens[idx - 1].text)) {
      redirOperandIndices.add(idx - 1);
    }
    if (idx + 1 < scan.tokens.length && scan.tokens[idx + 1].kind == 'word') {
      redirOperandIndices.add(idx + 1);
    }
  }

  for (var i = 0; i < scan.tokens.length; i++) {
    final t = scan.tokens[i];
    if (redirOperandIndices.contains(i)) continue;
    if (t.kind == 'assignment') {
      if (!policy.allowEnvAssignments) {
        throw StaticRejectError(StaticRejectReason.assignment);
      }
      final eq = t.text.indexOf('=');
      final name = t.text.substring(0, eq);
      final value = t.text.substring(eq + 1);
      if (t.dynamic) throw StaticRejectError(StaticRejectReason.expansion);
      out.env.add('$name=$_staticWordValue(value)');
      continue;
    }
    if (t.kind != 'word') continue;
    if (t.dynamic) throw StaticRejectError(StaticRejectReason.expansion);
    out.argv.add(_staticWordValue(t.text));
  }
  if (out.argv.isEmpty && out.env.isNotEmpty) {
    throw StaticRejectError(
        StaticRejectReason.assignment, 'shell assignment without command');
  }
  return out;
}

bool _isStderrToStdout(List<_Token> tokens, _Token redir) {
  if (redir.text != '>' && redir.text != '>&' && redir.text != '>>')
    return false;
  // Look for a preceding bare "2" token immediately before the redir, and the
  // word after it being "1".
  final idx = tokens.indexOf(redir);
  if (idx < 1) return false;
  final prev = tokens[idx - 1];
  if (prev.kind != 'word' || prev.text != '2') return false;
  if (idx + 1 >= tokens.length) return false;
  final next = tokens[idx + 1];
  return next.kind == 'word' && next.text == '1';
}

String _staticWordValue(String raw) {
  final out = StringBuffer();
  var i = 0;
  while (i < raw.length) {
    final c = raw[i];
    if (c == '\\' && i + 1 < raw.length) {
      out.write(raw[i + 1]);
      i += 2;
      continue;
    }
    if (c == '\'') {
      final end = raw.indexOf('\'', i + 1);
      if (end > 0) {
        out.write(raw.substring(i + 1, end));
        i = end + 1;
        continue;
      }
    }
    if (c == '"') {
      final end = raw.indexOf('"', i + 1);
      if (end > 0) {
        out.write(_unquote(raw.substring(i + 1, end)));
        i = end + 1;
        continue;
      }
    }
    out.write(c);
    i++;
  }
  return out.toString();
}

/// Reports whether [command] is anything other than a single static Bash
/// command. Parse failures are treated as syntax to keep callers conservative.
bool containsShellSyntax(String command) {
  if (command.trim().isEmpty) return false;
  final (_, malformed) = staticFields(command);
  return malformed.isNotEmpty;
}

/// Reports whether [command] contains an unquoted shell glob token.
bool containsUnquotedGlob(String command) {
  try {
    final scan = _scan(command);
    if (scan.hasHeredoc || scan.hasCompound) return true;
    for (final t in scan.tokens) {
      if (t.kind == 'word' && t.glob) return true;
    }
    return false;
  } on _ParseException {
    return true;
  }
}

/// Inspects one simple Bash command without evaluating expansions.
(ApprovalFeatures, bool) analyzeApprovalFeatures(String command) {
  final features = ApprovalFeatures();
  final _ScanResult scan;
  try {
    scan = _scan(command);
  } on _ParseException {
    return (features, false);
  }
  if (scan.hasHeredoc || scan.hasCompound) return (features, false);
  final ops = scan.tokens.where((t) => t.kind == 'op').toList();
  if (ops.any((t) =>
      t.text == '&&' ||
      t.text == '||' ||
      t.text == '|' ||
      t.text == '|&' ||
      t.text == ';' ||
      t.text == '&' ||
      t.text == 'newline')) {
    return (features, false);
  }
  for (final t in scan.tokens) {
    if (t.text == '<' ||
        t.text == '>' ||
        t.text == '>>' ||
        t.text == '<<<' ||
        t.text == '>&') {
      features.redirection = true;
    }
    if (t.kind == 'assignment') features.assignment = true;
    if (t.dynamic) {
      features.nestedExecution = features.nestedExecution ||
          t.text.contains(r'$(') ||
          t.text.contains('`') ||
          t.text.contains('<(') ||
          t.text.contains('>(');
      features.expansion = true;
    }
  }
  for (var i = 0; i < scan.tokens.length; i++) {
    final t = scan.tokens[i];
    if (t.kind != 'word' && t.kind != 'assignment') continue;
    if (t.dynamic) {
      if (i == 0) features.dynamicCommandName = true;
      break;
    }
    features.commandPrefix.add(_staticWordValue(t.text));
  }
  return (features, true);
}

/// Reports whether [command] contains a here-document.
bool hasHereDoc(String command) {
  try {
    return _scan(command).hasHeredoc;
  } on _ParseException {
    return false;
  }
}

/// Reports whether a later part of [command] can hide the failure of an
/// earlier part.
(bool, bool) canMaskEarlierFailure(String command) {
  if (command.trim().isEmpty) return (false, true);
  final _ScanResult scan;
  try {
    scan = _scan(command);
  } on _ParseException {
    return (false, false);
  }
  if (scan.hasHeredoc || scan.hasCompound) return (false, false);
  final ops = scan.tokens.where((t) => t.kind == 'op').toList();
  if (ops.isNotEmpty) {
    final last = ops.last;
    if (last.text == '&&' ||
        last.text == '||' ||
        last.text == '|' ||
        last.text == '|&' ||
        last.text == ';' ||
        last.text == '&') {
      return (false, false);
    }
  }
  for (final op in ops) {
    if (op.text == 'newline' ||
        op.text == ';' ||
        op.text == '|' ||
        op.text == '|&' ||
        op.text == '||' ||
        op.text == '&') {
      return (true, true);
    }
  }
  // Only `&&` chains are non-masking.
  return (false, true);
}

/// Returns simple command segments split at top-level shell control operators.
(List<String>, bool, bool) splitTopLevel(String command) {
  if (command.trim().isEmpty) return (const [], false, true);
  final _ScanResult scan;
  try {
    scan = _scan(command);
  } on _ParseException {
    return (const [], false, false);
  }
  if (scan.hasHeredoc || scan.hasCompound) return (const [], false, false);

  final segments = <String>[];
  var segmentStart = 0;
  var split = false;
  var lastEnd = 0;
  final ops = scan.tokens.where((t) => t.kind == 'op').toList();
  for (final op in ops) {
    if (op.text == '&&' ||
        op.text == '||' ||
        op.text == '|' ||
        op.text == '|&' ||
        op.text == ';' ||
        op.text == '&' ||
        op.text == 'newline') {
      split = true;
      final raw = command.substring(segmentStart, op.start).trim();
      if (raw.isNotEmpty && !raw.startsWith('#')) segments.add(raw);
      segmentStart = op.end;
    }
    lastEnd = op.end;
  }
  final tail = command.substring(segmentStart).trim();
  if (tail.isNotEmpty && !tail.startsWith('#')) segments.add(tail);
  return (segments, split, true);
}

/// Reports whether [word] has Bash assignment syntax.
bool isAssignment(String word) {
  final eq = word.indexOf('=');
  if (eq <= 0) return false;
  return _isAssignmentRaw(word.substring(0, eq + 1));
}

/// Returns the basename of a shell command word.
String wordBase(String word) {
  final slash = word.lastIndexOf('/');
  return slash >= 0 ? word.substring(slash + 1) : word;
}
