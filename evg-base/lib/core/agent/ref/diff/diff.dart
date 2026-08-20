/// Port of reasonix/internal/diff.
///
/// Computes a line-level unified diff between two versions of a file.
library;

enum Kind { create, modify, delete }

enum OutputMode { patch, preview }

class Change {
  final String path;
  final Kind kind;
  final String oldText;
  final String newText;
  final int added;
  final int removed;
  final String diff;
  final bool binary;
  final String mode;
  final int hunks;

  const Change({
    required this.path,
    required this.kind,
    this.oldText = '',
    this.newText = '',
    this.added = 0,
    this.removed = 0,
    this.diff = '',
    this.binary = false,
    this.mode = '',
    this.hunks = 0,
  });
}

class BuildOptions {
  final int contextLines;
  final String oldLabel;
  final String newLabel;
  final OutputMode mode;

  const BuildOptions({
    this.contextLines = -1,
    this.oldLabel = '',
    this.newLabel = '',
    this.mode = OutputMode.patch,
  });
}

const int _defaultContext = 3;
const int _maxDiffEdits = 2000;

Change build(String path, String oldText, String newText, Kind kind) =>
    buildWithOptions(
        path, oldText, newText, kind, const BuildOptions(contextLines: -1));

Change buildWithOptions(
    String path, String oldText, String newText, Kind kind, BuildOptions opts) {
  opts = _normalizeOptions(path, opts);

  if (_isBinary(oldText) || _isBinary(newText)) {
    return Change(
      path: path,
      kind: kind,
      oldText: oldText,
      newText: newText,
      binary: true,
    );
  }
  if (oldText == newText) {
    return Change(
      path: path,
      kind: kind,
      oldText: oldText,
      newText: newText,
    );
  }

  final oldSplit = _splitLines(oldText);
  final newSplit = _splitLines(newText);

  if (_exactDiffTooLarge(oldSplit.lines, newSplit.lines)) {
    final (added, removed) = _approxTally(oldSplit.lines, newSplit.lines);
    final msg = '(diff omitted: change too large to render '
        '— +$added / -$removed lines)';
    return Change(
      path: path,
      kind: kind,
      oldText: oldText,
      newText: newText,
      added: added,
      removed: removed,
      diff: msg,
    );
  }

  final edits = _lineDiff(oldSplit.lines, newSplit.lines);
  final (added, removed) = _tallyEdits(edits);
  final diff = _toUnified(
    oldSplit.lines,
    newSplit.lines,
    oldSplit.trailing,
    newSplit.trailing,
    edits,
    opts.oldLabel,
    opts.newLabel,
    opts.contextLines,
  );
  final hunks = _countHunks(diff);

  return Change(
    path: path,
    kind: kind,
    oldText: oldText,
    newText: newText,
    added: added,
    removed: removed,
    diff: diff,
    mode: opts.mode == OutputMode.patch ? '' : 'preview',
    hunks: hunks,
  );
}

BuildOptions _normalizeOptions(String path, BuildOptions opts) {
  final context = opts.contextLines < 0 ? _defaultContext : opts.contextLines;
  final mode = opts.mode;
  var oldLabel = opts.oldLabel;
  var newLabel = opts.newLabel;
  if (oldLabel.isEmpty) {
    oldLabel = '${mode == OutputMode.patch ? 'a/' : 'before/'}$path';
  }
  if (newLabel.isEmpty) {
    newLabel = '${mode == OutputMode.patch ? 'b/' : 'after/'}$path';
  }
  return BuildOptions(
    contextLines: context,
    oldLabel: oldLabel,
    newLabel: newLabel,
    mode: mode,
  );
}

bool _isBinary(String s) => s.contains('\x00');

({List<String> lines, bool trailing}) _splitLines(String s) {
  if (s.isEmpty) return (lines: <String>[], trailing: true);
  final trailing = s.endsWith('\n');
  final body = trailing ? s.substring(0, s.length - 1) : s;
  return (lines: body.split('\n'), trailing: trailing);
}

bool _exactDiffTooLarge(List<String> oldLines, List<String> newLines) {
  return _changedWindowSize(oldLines, newLines) > _maxDiffEdits;
}

int _changedWindowSize(List<String> oldLines, List<String> newLines) {
  var start = 0;
  while (start < oldLines.length &&
      start < newLines.length &&
      oldLines[start] == newLines[start]) {
    start++;
  }
  var oldEnd = oldLines.length;
  var newEnd = newLines.length;
  while (oldEnd > start &&
      newEnd > start &&
      oldLines[oldEnd - 1] == newLines[newEnd - 1]) {
    oldEnd--;
    newEnd--;
  }
  return (oldEnd - start) + (newEnd - start);
}

({int added, int removed}) _approxTally(
    List<String> oldLines, List<String> newLines) {
  final counts = <String, int>{};
  for (final l in oldLines) {
    counts[l] = (counts[l] ?? 0) + 1;
  }
  var added = 0;
  for (final l in newLines) {
    if ((counts[l] ?? 0) > 0) {
      counts[l] = counts[l]! - 1;
    } else {
      added++;
    }
  }
  var removed = 0;
  for (final v in counts.values) removed += v;
  return (added: added, removed: removed);
}

class _Edit {
  final String kind; // equal, delete, insert
  final String oldLine;
  final String newLine;
  _Edit(this.kind, this.oldLine, this.newLine);
}

List<_Edit> _lineDiff(List<String> oldLines, List<String> newLines) {
  final n = oldLines.length;
  final m = newLines.length;
  final dp = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      if (oldLines[i] == newLines[j]) {
        dp[i][j] = dp[i + 1][j + 1] + 1;
      } else {
        dp[i][j] = dp[i + 1][j] > dp[i][j + 1] ? dp[i + 1][j] : dp[i][j + 1];
      }
    }
  }
  final edits = <_Edit>[];
  var i = 0, j = 0;
  while (i < n && j < m) {
    if (oldLines[i] == newLines[j]) {
      edits.add(_Edit('equal', oldLines[i], newLines[j]));
      i++;
      j++;
    } else if (dp[i + 1][j] >= dp[i][j + 1]) {
      edits.add(_Edit('delete', oldLines[i], ''));
      i++;
    } else {
      edits.add(_Edit('insert', '', newLines[j]));
      j++;
    }
  }
  while (i < n) {
    edits.add(_Edit('delete', oldLines[i], ''));
    i++;
  }
  while (j < m) {
    edits.add(_Edit('insert', '', newLines[j]));
    j++;
  }
  return edits;
}

({int added, int removed}) _tallyEdits(List<_Edit> edits) {
  var added = 0;
  var removed = 0;
  for (final e in edits) {
    if (e.kind == 'delete') removed++;
    if (e.kind == 'insert') added++;
  }
  return (added: added, removed: removed);
}

int _countHunks(String diff) {
  if (diff.isEmpty) return 0;
  var count = 0;
  for (final line in diff.split('\n')) {
    if (line.startsWith('@@ ')) count++;
  }
  return count;
}

String _toUnified(
  List<String> oldLines,
  List<String> newLines,
  bool oldTrailing,
  bool newTrailing,
  List<_Edit> edits,
  String oldLabel,
  String newLabel,
  int context,
) {
  final oldPos = List<int>.filled(edits.length + 1, 0);
  final newPos = List<int>.filled(edits.length + 1, 0);
  for (var i = 0; i < edits.length; i++) {
    final e = edits[i];
    oldPos[i + 1] =
        oldPos[i] + ((e.kind == 'equal' || e.kind == 'delete') ? 1 : 0);
    newPos[i + 1] =
        newPos[i] + ((e.kind == 'equal' || e.kind == 'insert') ? 1 : 0);
  }

  final changeIndices = <int>[];
  for (var i = 0; i < edits.length; i++) {
    if (edits[i].kind != 'equal') changeIndices.add(i);
  }
  if (changeIndices.isEmpty) return '';

  final hunks = <({int opStart, int opEnd, int oldStart, int newStart})>[];
  for (var idx = 0; idx < changeIndices.length; idx++) {
    final first = changeIndices[idx];
    var opStart = first - context;
    if (opStart < 0) opStart = 0;
    var opEnd = first + context + 1;
    if (opEnd > edits.length) opEnd = edits.length;

    if (hunks.isNotEmpty) {
      final prev = hunks.last;
      if (opStart <= prev.opEnd + 2 * context) {
        hunks.last = (
          opStart: prev.opStart,
          opEnd: opEnd,
          oldStart: prev.oldStart,
          newStart: prev.newStart,
        );
        continue;
      }
    }
    hunks.add((
      opStart: opStart,
      opEnd: opEnd,
      oldStart: oldPos[opStart] + 1,
      newStart: newPos[opStart] + 1,
    ));
  }

  final buf = StringBuffer('--- $oldLabel\n+++ $newLabel\n');

  for (final h in hunks) {
    final oldEnd = oldPos[h.opEnd];
    final newEnd = newPos[h.opEnd];

    final oldLen = (oldEnd - h.oldStart + 1).clamp(0, oldLines.length);
    final newLen = (newEnd - h.newStart + 1).clamp(0, newLines.length);

    final oldHeader = oldLen == 0 && h.oldStart == 1
        ? '0,0'
        : '${h.oldStart},$oldLen';
    final newHeader = newLen == 0 && h.newStart == 1
        ? '0,0'
        : '${h.newStart},$newLen';

    buf.writeln('@@ -$oldHeader +$newHeader @@');

    var emittedOldLast = h.oldStart - 1;
    var emittedNewLast = h.newStart - 1;

    for (var i = h.opStart; i < h.opEnd; i++) {
      final e = edits[i];
      switch (e.kind) {
        case 'equal':
          emittedOldLast++;
          emittedNewLast++;
          buf.writeln(' ${e.oldLine}');
        case 'delete':
          emittedOldLast++;
          buf.writeln('-${e.oldLine}');
        case 'insert':
          emittedNewLast++;
          buf.writeln('+${e.newLine}');
      }
    }

    if (oldLen > 0 && emittedOldLast == oldLines.length && !oldTrailing) {
      buf.writeln('\\ No newline at end of file');
    }
    if (newLen > 0 && emittedNewLast == newLines.length && !newTrailing) {
      buf.writeln('\\ No newline at end of file');
    }
  }

  return buf.toString();
}
