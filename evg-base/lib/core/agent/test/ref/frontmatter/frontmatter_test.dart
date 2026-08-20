import 'package:evergreen_base/core/agent/ref/frontmatter/frontmatter.dart' as fm;
import 'package:test/test.dart';

void main() {
  test('split no fence', () {
    final (front, body) = fm.split('just body text\nno fence');
    expect(front, isEmpty);
    expect(body, contains('just body text'));
  });

  test('split unclosed fence', () {
    final (front, body) = fm.split('---\nkey: val\n\nno closing fence');
    expect(front, isEmpty);
    expect(body, contains('---'));
  });

  test('split empty body', () {
    final (front, body) = fm.split('---\nkey: val\n---\n');
    expect(front['key'], 'val');
    expect(body.trim(), isEmpty);
  });

  test('split nested metadata', () {
    final (front, body) = fm.split(
        '---\nname: test\ndescription: desc\nmetadata:\n  type: user\n---\n\nbody here');
    expect(front['name'], 'test');
    expect(front['description'], 'desc');
    expect(front['type'], 'user');
    expect(body, contains('body here'));
  });

  test('split CRLF', () {
    final (front, body) = fm.split('---\r\nname: test\r\n---\r\nbody\r\n');
    expect(front['name'], 'test');
    expect(body, contains('body'));
  });

  test('split quoted values', () {
    final (front, _) = fm.split('---\nname: test\ndescription: "quoted desc"\n---\n');
    expect(front['description'], 'quoted desc');
  });

  test('split single quotes', () {
    final (front, _) = fm.split("---\nname: test\ndescription: 'single quoted'\n---\n");
    expect(front['description'], 'single quoted');
  });

  test('split empty input', () {
    final (front, body) = fm.split('');
    expect(front, isEmpty);
    expect(body, isEmpty);
  });

  test('split only fence', () {
    final (front, body) = fm.split('---\n---\n');
    expect(front, isEmpty);
    expect(body.trim(), isEmpty);
  });

  test('split multiple keys', () {
    final (front, _) = fm.split('---\na: 1\nb: 2\nc: 3\n---\n');
    expect(front['a'], '1');
    expect(front['b'], '2');
    expect(front['c'], '3');
  });

  test('split case insensitive', () {
    final (front, _) = fm.split('---\nName: Test\nDESCRIPTION: desc\n---\n');
    expect(front['name'], 'Test');
    expect(front['description'], 'desc');
  });

  test('split multiline literal', () {
    final (front, body) = fm.split('---\nname: test\ndescription: "run: with colon"\nnotes: |\n  first line\n  second line\n---\nbody');
    expect(front['description'], 'run: with colon');
    expect(front['notes'], 'first line\nsecond line');
    expect(body, 'body');
  });

  test('decode reports malformed YAML', () {
    final (_, err) = fm.decode('---\nname: [unterminated\n---\nbody', null,
        const fm.DecodeOptions());
    expect(err, isNotNull);
  });
}
