import 'package:evergreen_base/core/agent/ref/outputstyle/outputstyle.dart' as outputstyle;
import 'package:test/test.dart';

void main() {
  test('built-in styles are available', () {
    final styles = outputstyle.list([]);
    final names = styles.map((s) => s.name).toSet();
    expect(names, containsAll(['explanatory', 'learning', 'concise']));
  });

  test('apply appends keep-coding style', () {
    final style = outputstyle.resolve('concise', []);
    expect(style, isNotNull);
    final result = outputstyle.apply('base prompt', style!);
    expect(result, startsWith('base prompt\n\n'));
  });
}
