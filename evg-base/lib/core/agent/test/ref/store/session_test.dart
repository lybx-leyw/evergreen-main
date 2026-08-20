import 'package:evergreen_base/core/agent/ref/store/session.dart' as store;
import 'package:test/test.dart';

void main() {
  test('session sidecar paths', () {
    const session = '/tmp/foo/session.jsonl';
    expect(store.isSessionTranscriptName('session.jsonl'), isTrue);
    expect(store.isSessionTranscriptName('session.events.jsonl'), isFalse);
    expect(store.sessionContext(session), '/tmp/foo/session.context.json');
    expect(store.sessionMeta(session), '/tmp/foo/session.jsonl.meta');
    expect(store.sessionEventLog(session), '/tmp/foo/session.events.jsonl');
  });
}
