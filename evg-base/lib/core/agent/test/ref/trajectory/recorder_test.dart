/// Port of reasonix/internal/trajectory/recorder_test.go.
library;

import 'dart:io';

import 'package:test/test.dart';

import '../../../ref/event/event.dart' as event;
import '../../../ref/evidence/outcome_sample.dart' as evidence;
import '../../../ref/evidence/readiness_audit.dart' as evidence_readiness;
import '../../../ref/trajectory/recorder.dart' as trajectory;

void main() {
  test('recorder appends ordered timestamped records', () async {
    final dir = Directory.systemTemp.createTempSync('trajectory-test-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/run.trajectory.jsonl';
    final inner = _CapabilitySink();
    var now = DateTime.fromMillisecondsSinceEpoch(1754500000000);
    final r = await trajectory.Recorder.open(inner, path, clock: () => now);

    r.emit(event.Event()
      ..kind = event.Kind.toolDispatch
      ..tool = event.Tool()
      ..id = 'c1'
      ..name = 'bash'
      ..args = '{"command":"ls"}');
    now = now.add(const Duration(milliseconds: 120));
    r.emit(event.Event()
      ..kind = event.Kind.toolResult
      ..tool = event.Tool()
      ..id = 'c1'
      ..name = 'bash'
      ..output = 'ok'
      ..durationMs = 100
      ..startedAt = 1754500000010
      ..endedAt = 1754500000110);
    r.emit(event.Event()
      ..kind = event.Kind.reasoning
      ..text = 'thinking about the next step');
    await r.close();

    final recs = trajectory.readRecords(path);
    expect(recs.length, 3);
    for (var i = 0; i < recs.length; i++) {
      expect(recs[i].seq, i + 1);
      expect(recs[i].schemaVersion, trajectory.schemaVersion);
      expect(recs[i].event, isNotNull);
    }
    expect(recs[0].ts, 1754500000000);
    expect(recs[1].ts, 1754500000120);
    expect(recs[1].event!.tool, isNotNull);
    expect(recs[1].event!.tool!.startedAt, 1754500000010);
    expect(recs[1].event!.tool!.endedAt, 1754500000110);
    expect(recs[2].event!.kind, 'reasoning');
    expect(recs[2].event!.text, 'thinking about the next step');
    expect(inner.events.length, 3);
  });

  test('recorder records and forwards optional capabilities', () async {
    final dir = Directory.systemTemp.createTempSync('trajectory-test-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/run.trajectory.jsonl';
    final inner = _CapabilitySink();
    final r = await trajectory.Recorder.open(inner, path);

    r.recordReadinessAudit(evidence_readiness.ReadinessAudit()
      ..result = 'blocked'
      ..missingVerification = 2);
    r.recordProtocolRecovery(event.ProtocolRecoveryAudit(
        kind: event.ProtocolRecoveryKind.missingReasoningDetected));
    r.recordTurnCompletion();
    r.recordOutcomeProgress(evidence.OutcomeSample()
      ..round = 3
      ..exploration = 2
      ..objective = 1
      ..legacyGain = 4);
    r.recordDelegationAdmission(event.DelegationAdmissionAudit()
      ..tool = 'research'
      ..verdict = 'deny'
      ..reason = 'local_fix_no_external_need'
      ..intent = 'mutation');
    r.recordCompletionReport(event.CompletionReportAudit()
      ..verdict = 'partial'
      ..changes = 2
      ..changesUnreviewed = 1
      ..gaps = 1
      ..gapKinds = ['unreviewed_change']);
    await r.close();

    final recs = trajectory.readRecords(path);
    expect(recs.length, 6);
    expect(recs[0].readinessAudit, isNotNull);
    expect(recs[0].readinessAudit!.result, 'blocked');
    expect(recs[0].readinessAudit!.missingVerification, 2);
    expect(recs[1].protocolRecovery, 'missing_reasoning_detected');
    expect(recs[2].turnCompletion, isTrue);
    expect(recs[3].outcomeProgress, isNotNull);
    expect(recs[3].outcomeProgress!.round, 3);
    expect(recs[3].outcomeProgress!.objective, 1);
    expect(recs[3].outcomeProgress!.legacyGain, 4);
    expect(recs[4].delegationAdmission, isNotNull);
    expect(recs[4].delegationAdmission!.verdict, 'deny');
    expect(recs[4].delegationAdmission!.tool, 'research');
    expect(recs[5].completionReport, isNotNull);
    expect(recs[5].completionReport!.verdict, 'partial');
    expect(recs[5].completionReport!.changesUnreviewed, 1);
    expect(recs[5].completionReport!.gapKinds.length, 1);
    expect(inner.readiness.length, 1);
    expect(inner.recoveries.length, 1);
    expect(inner.turns, 1);
    expect(inner.outcomes.length, 1);
    expect(inner.reports.length, 1);
  });

  test('recorder forwards after close without recording', () async {
    final dir = Directory.systemTemp.createTempSync('trajectory-test-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/run.trajectory.jsonl';
    final inner = _CapabilitySink();
    final r = await trajectory.Recorder.open(inner, path);
    r.emit(event.Event()
      ..kind = event.Kind.text
      ..text = 'before');
    await r.close();
    r.emit(event.Event()
      ..kind = event.Kind.text
      ..text = 'after');

    expect(trajectory.readRecords(path).length, 1);
    expect(inner.events.length, 2);
  });

  test('open fails on unwritable path', () {
    final dir = Directory.systemTemp.createTempSync('trajectory-test-');
    addTearDown(() => dir.deleteSync(recursive: true));
    expect(
      trajectory.Recorder.open(event.discard, '${dir.path}/missing/run.jsonl'),
      throwsA(isA<FileSystemException>()),
    );
  });
}

class _CapabilitySink
    implements
        event.Sink,
        event.ReadinessAuditSink,
        event.ProtocolRecoveryAuditSink,
        event.TurnCompletionSink,
        event.OutcomeProgressSink,
        event.CompletionReportAuditSink {
  final events = <event.Event>[];
  final readiness = <evidence_readiness.ReadinessAudit>[];
  final recoveries = <event.ProtocolRecoveryAudit>[];
  final outcomes = <evidence.OutcomeSample>[];
  final reports = <event.CompletionReportAudit>[];
  int turns = 0;

  @override
  void emit(event.Event e) => events.add(e);

  @override
  void recordReadinessAudit(evidence_readiness.ReadinessAudit a) =>
      readiness.add(a);

  @override
  void recordProtocolRecovery(event.ProtocolRecoveryAudit a) =>
      recoveries.add(a);

  @override
  void recordTurnCompletion() => turns++;

  @override
  void recordOutcomeProgress(evidence.OutcomeSample sample) =>
      outcomes.add(sample);

  @override
  void recordCompletionReport(event.CompletionReportAudit a) => reports.add(a);
}
