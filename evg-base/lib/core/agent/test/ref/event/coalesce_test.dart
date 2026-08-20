import 'package:evergreen_base/core/agent/ref/event/event.dart' as event;
import 'package:evergreen_base/core/agent/ref/evidence/readiness_audit.dart'
    as evidence;
import 'package:test/test.dart';

class _RecordSink implements event.Sink {
  final events = <event.Event>[];
  int readiness = 0;
  int turns = 0;
  int recovery = 0;
  int workspace = 0;

  @override
  void emit(event.Event e) => events.add(e);

  void recordReadinessAudit(evidence.ReadinessAudit a) => readiness++;
  void recordTurnCompletion() => turns++;
  void recordProtocolRecovery(event.ProtocolRecoveryAudit a) => recovery++;
  void recordWorkspaceMutation(event.WorkspaceMutation m) => workspace++;
}

void main() {
  test('first delta forwards immediately', () {
    final inner = _RecordSink();
    final c = event.coalesce(inner, const Duration(hours: 1));
    c.emit(event.Event()
      ..kind = event.Kind.text
      ..text = 'hello');
    expect(inner.events.length, 1);
    expect(inner.events.first.text, 'hello');
  });

  test('merges burst and flushes on barrier', () {
    final inner = _RecordSink();
    final c = event.coalesce(inner, const Duration(hours: 1));
    c.emit(event.Event()
      ..kind = event.Kind.reasoning
      ..text = 'a');
    c.emit(event.Event()
      ..kind = event.Kind.reasoning
      ..text = 'b');
    c.emit(event.Event()
      ..kind = event.Kind.reasoning
      ..text = 'c');
    c.emit(event.Event()
      ..kind = event.Kind.toolDispatch
      ..tool = (event.Tool()
        ..id = 't1'
        ..name = 'bash'));
    expect(inner.events.length, 3);
    expect(inner.events[1].kind, event.Kind.reasoning);
    expect(inner.events[1].text, 'bc');
    expect(inner.events[2].kind, event.Kind.toolDispatch);
  });

  test('disabled with zero window', () {
    final inner = _RecordSink();
    final c = event.coalesce(inner, Duration.zero);
    expect(identical(c, inner), isTrue);
  });

  test('nil inner returns discard', () {
    final c = event.coalesce(null, const Duration(seconds: 1));
    expect(c, isNotNull);
  });
}
