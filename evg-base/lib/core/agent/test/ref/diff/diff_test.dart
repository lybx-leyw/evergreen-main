import 'package:evergreen_base/core/agent/ref/diff/diff.dart' as diff;
import 'package:test/test.dart';

void main() {
  test('no change', () {
    final c = diff.build('f.txt', 'a\nb\n', 'a\nb\n', diff.Kind.modify);
    expect(c.diff, isEmpty);
    expect(c.added, 0);
    expect(c.removed, 0);
  });

  test('create', () {
    final c = diff.build('new.txt', '', 'hello\nworld\n', diff.Kind.create);
    expect(c.added, 2);
    expect(c.removed, 0);
    expect(c.diff, contains('@@ -0,0 +1,2 @@'));
    expect(c.diff, contains('+hello'));
    expect(c.diff, contains('+world'));
  });

  test('delete all', () {
    final c = diff.build('gone.txt', 'x\ny\n', '', diff.Kind.delete);
    expect(c.added, 0);
    expect(c.removed, 2);
    expect(c.diff, contains('@@ -1,2 +0,0 @@'));
  });

  test('modify middle', () {
    final old = '1\n2\n3\n4\n5\n';
    final neu = '1\n2\nThree\n4\n5\n';
    final c = diff.build('m.txt', old, neu, diff.Kind.modify);
    expect(c.added, 1);
    expect(c.removed, 1);
    expect(c.diff, contains('-3'));
    expect(c.diff, contains('+Three'));
    expect(c.diff, contains(' 1'));
    expect(c.diff, contains(' 5'));
  });

  test('preview labels and context', () {
    final old = '1\n2\n3\n4\n5\n';
    final neu = '1\n2\nThree\n4\n5\n';
    final c = diff.buildWithOptions(
        'm.txt',
        old,
        neu,
        diff.Kind.modify,
        const diff.BuildOptions(
            contextLines: 0, mode: diff.OutputMode.preview));
    expect(c.mode, 'preview');
    expect(c.diff, contains('--- before/m.txt'));
    expect(c.diff, contains('+++ after/m.txt'));
    expect(c.diff, isNot(contains(' 1')));
    expect(c.diff, isNot(contains(' 5')));
    expect(c.hunks, 1);
  });

  test('custom labels', () {
    final c = diff.buildWithOptions(
        'x.txt',
        'old\n',
        'new\n',
        diff.Kind.modify,
        const diff.BuildOptions(
            contextLines: 1, oldLabel: 'left', newLabel: 'right'));
    expect(c.diff, contains('--- left'));
    expect(c.diff, contains('+++ right'));
  });

  test('prepend', () {
    final c = diff.build('p.txt', 'b\nc\n', 'a\nb\nc\n', diff.Kind.modify);
    expect(c.added, 1);
    expect(c.removed, 0);
    expect(c.diff, contains('@@ -1,2 +1,3 @@'));
  });

  test('two separate hunks', () {
    final old = 'a\nb\nc\nd\ne\nf\ng\nh\ni\nj\nk\nl\n';
    final neu = 'a\nB\nc\nd\ne\nf\ng\nh\ni\nj\nK\nl\n';
    final c = diff.build('two.txt', old, neu, diff.Kind.modify);
    expect(c.hunks, 2);
    expect(c.added, 2);
    expect(c.removed, 2);
  });

  test('adjacent changes merge', () {
    final old = 'a\nb\nc\nd\ne\n';
    final neu = 'a\nB\nc\nD\ne\n';
    final c = diff.build('adj.txt', old, neu, diff.Kind.modify);
    expect(c.hunks, 1);
  });

  test('no newline at EOF', () {
    final c = diff.build('nonl.txt', 'a\nb', 'a\nc', diff.Kind.modify);
    expect(c.diff, contains(r'\ No newline at end of file'));
  });

  test('binary', () {
    final c = diff.build('bin', 'ok\n', 'bad\x00data', diff.Kind.modify);
    expect(c.binary, isTrue);
    expect(c.diff, isEmpty);
    expect(c.added, 0);
    expect(c.removed, 0);
  });

  test('minimal edit script', () {
    final c =
        diff.build('min.txt', 'x\nx\nx\n', 'x\nx\ny\nx\n', diff.Kind.modify);
    expect(c.added, 1);
    expect(c.removed, 0);
  });
}
