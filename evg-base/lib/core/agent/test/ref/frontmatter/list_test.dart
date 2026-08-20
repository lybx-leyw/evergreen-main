/// Port of reasonix/internal/frontmatter/list_test.go.
///
/// Verifies a YAML list value is flattened into the comma-separated frontmatter
/// map so a subagent skill can keep its allowed-tools scoping.
library;

import 'package:evergreen_base/core/agent/ref/frontmatter/frontmatter.dart'
    as fm;
import 'package:test/test.dart';

void main() {
  test('split parses YAML list', () {
    const input = '---\n'
        'name: review\n'
        'allowed-tools:\n'
        '  - read_file\n'
        '  - grep\n'
        '---\n'
        'body here\n';
    final (front, body) = fm.split(input);
    expect(front['name'], 'review');
    final got = front['allowed-tools'];
    expect(got, isNotNull);
    expect(got, isNotEmpty);
    expect(got, contains('read_file'));
    expect(got, contains('grep'));
    expect(body, 'body here\n');
  });
}
