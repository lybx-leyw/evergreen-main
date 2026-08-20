import 'package:evergreen_base/core/agent/ref/textutil/grapheme.dart' as textutil;
import 'package:test/test.dart';

void main() {
  const cluster = '\u{1F468}\u200D\u{1F469}\u200D\u{1F467}\u200D\u{1F466}';

  test('fitGraphemeBytes keeps cluster', () {
    expect(textutil.fitGraphemeBytes('$cluster!', cluster.length), cluster);
    expect(textutil.fitGraphemeBytes('$cluster!', 1), cluster);
  });

  test('clipGraphemes counts suffix inside budget', () {
    expect(textutil.clipGraphemes('a${cluster}bc', 3, '…'),
        'a${cluster}…');
    expect(textutil.clipGraphemes('abc', 1, '…'), 'a');
  });

  test('truncateGraphemes appends suffix outside budget', () {
    expect(textutil.truncateGraphemes('a${cluster}bc', 2, '...'),
        'a${cluster}...');
  });
}
