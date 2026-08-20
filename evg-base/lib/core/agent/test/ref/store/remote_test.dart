import 'package:evergreen_base/core/agent/ref/store/remote.dart' as store;
import 'package:test/test.dart';

void main() {
  test('remote workspace slug is deterministic', () {
    final slug = store.remoteWorkspaceSlug('/srv/my-project');
    expect(slug, isNotEmpty);
    expect(slug, store.remoteWorkspaceSlug('/srv/my-project'));
    expect(slug, isNot(store.remoteWorkspaceSlug('/srv/my-project/')));
  });

  test('serve state names', () {
    expect(store.remoteServeStateName('abc'), 'serve-abc.json');
    expect(store.remoteServeTokenName('abc'), 'serve-abc.token');
  });
}
