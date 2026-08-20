/// Port of reasonix/internal/diff/largediff_test.go.
///
/// Translation notes:
/// - The Go test measures memory/time to prove the edit-distance cap is
///   bounded. Dart has no portable equivalent of runtime.MemStats here, so we
///   assert the observable contract instead: a full rewrite above the cap
///   yields the omitted-diff marker with correct tallies, while a small edit
///   on a large file still produces a real line-by-line diff.
library;

import 'package:evergreen_base/core/agent/ref/diff/diff.dart' as diff;
import 'package:test/test.dart';

void main() {
  test('large rewrite is bounded and reports omitted diff', () {
    const n = 6000;
    final old = List.generate(n, (i) => 'old line $i').join('\n') + '\n';
    final neu =
        List.generate(n, (i) => 'totally different new line $i').join('\n') +
            '\n';
    final c = diff.build('big.txt', old, neu, diff.Kind.modify);
    expect(c.added, n);
    expect(c.removed, n);
    expect(c.diff, contains('too large'));
  });

  test('small edit on large file still diffs', () {
    const n = 8000;
    final old = List.generate(n, (i) => 'line $i').join('\n') + '\n';
    final updated = old.replaceFirst('line 4000\n', 'line 4000 EDITED\n');
    final c = diff.build('big.txt', old, updated, diff.Kind.modify);
    expect(c.added, 1);
    expect(c.removed, 1);
    expect(c.diff, contains('line 4000 EDITED'));
    expect(c.diff, isNot(contains('too large')));
  });
}
