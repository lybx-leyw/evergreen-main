import 'package:evergreen_base/core/agent/ref/fileutil/globset.dart' as globset;
import 'package:test/test.dart';

void main() {
  test('include all, exclude node_modules', () {
    final set = globset.GlobSet.create(['**/*.dart'], ['**/node_modules/**']);
    expect(set.match('lib/foo.dart'), isTrue);
    expect(set.match('node_modules/x/lib.dart'), isFalse);
  });

  test('** prefix matches deeply', () {
    final set = globset.GlobSet.create(['**/test_*.go'], []);
    expect(set.match('a/b/c/test_foo.go'), isTrue);
    expect(set.match('test_foo.go'), isTrue);
  });
}
