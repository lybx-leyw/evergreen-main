/// Port of reasonix/internal/diff/diff_extra_test.go.
///
/// The Go test exercises private helpers (`splitLines`, `isBinary`, `itoa`)
/// from inside the package. Dart library privacy prevents importing those
/// helpers from `test/`, so the same edge cases are asserted through the
/// public `build` API and public enum names.
library;

import 'package:evergreen_base/core/agent/ref/diff/diff.dart' as diff;
import 'package:test/test.dart';

void main() {
  test('build both empty is a no-op', () {
    final c = diff.build('empty.txt', '', '', diff.Kind.modify);
    expect(c.diff, isEmpty);
    expect(c.added, 0);
    expect(c.removed, 0);
  });

  test('build empty old non-empty new', () {
    final c = diff.build('new.txt', '', 'line1\nline2\n', diff.Kind.create);
    expect(c.added, 2);
    expect(c.removed, 0);
    expect(c.kind, diff.Kind.create);
  });

  test('build non-empty old empty new', () {
    final c = diff.build('del.txt', 'line1\nline2\n', '', diff.Kind.delete);
    expect(c.added, 0);
    expect(c.removed, 2);
  });

  test('build CRLF keeps \\r in line content', () {
    final c = diff.build('crlf.txt', 'line1\r\nline2\r\n', 'line1\r\nLINE2\r\n',
        diff.Kind.modify);
    expect(c.added, 1);
    expect(c.removed, 1);
  });

  test('build whitespace-only change counts as a change', () {
    final c = diff.build('ws.txt', 'a\tb\n', 'a  b\n', diff.Kind.modify);
    expect(c.added, 1);
    expect(c.removed, 1);
  });

  test('build large file with one changed line', () {
    final old = List.generate(1000, (i) => 'line').join('\n') + '\n';
    final neu =
        List.generate(1000, (i) => i == 500 ? 'CHANGED' : 'line').join('\n') +
            '\n';
    final c = diff.build('large.txt', old, neu, diff.Kind.modify);
    expect(c.added, 1);
    expect(c.removed, 1);
  });

  test('kind constants match Go wire strings', () {
    expect(diff.Kind.create.name, 'create');
    expect(diff.Kind.modify.name, 'modify');
    expect(diff.Kind.delete.name, 'delete');
  });

  test('binary detection through build', () {
    expect(diff.build('b', '', '', diff.Kind.modify).binary, isFalse);
    expect(diff.build('b', 'hello world\nline 2', '', diff.Kind.modify).binary,
        isFalse);
    expect(
        diff.build('b', 'hello\x00world', '', diff.Kind.modify).binary, isTrue);
    expect(diff.build('b', 'hello\x00', '', diff.Kind.modify).binary, isTrue);
  });
}
