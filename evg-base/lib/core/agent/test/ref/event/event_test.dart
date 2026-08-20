/// Port of reasonix/internal/event/event_test.go.
///
/// Translation notes:
/// - Dart enums replace Go iota constants; index assertions map 1:1.
/// - Go's typed-nil sink case maps to a null Dart sink (Dart has no typed nil).
/// - The 100-way concurrent emit test maps to 100 sequential emits (Dart's
///   single-threaded event loop makes concurrent synchronous emits atomic;
///   the Go test's -race guarantee is preserved by Dart's model).
library;

import 'package:test/test.dart';

import '../../../../ref/event/event.dart' as event;
import '../../../../ref/evidence/readiness_audit.dart' as evidence;
import '../../../../ref/provider/usage.dart' as provider;

void main() {
  group('Kind constants', () {
    test('core kinds are stable and sequential', () {
      final kinds = [
        event.Kind.turnStarted,
        event.Kind.reasoning,
        event.Kind.text,
        event.Kind.message,
        event.Kind.toolDispatch,
        event.Kind.toolResult,
        event.Kind.usage,
        event.Kind.notice,
        event.Kind.phase,
        event.Kind.approvalRequest,
        event.Kind.askRequest,
        event.Kind.turnDone,
      ];
      for (var i = 0; i < kinds.length; i++) {
        expect(kinds[i].index, i, reason: 'Kind ${kinds[i]} index');
      }
      // New kinds must sit before the sentinel (KindCount == values.length).
      expect(event.Kind.turnPhase.index, lessThan(event.Kind.values.length));
      expect(event.Kind.completionSummary.index,
          lessThan(event.Kind.values.length));
    });

    test('turn phase names are stable', () {
      expect(event.TurnPhaseName.working.name, 'working');
      expect(event.TurnPhaseName.reviewing.name, 'reviewing');
    });
  });

  group('Level constants', () {
    test('info=0 warn=1', () {
      expect(event.Level.info.index, 0);
      expect(event.Level.warn.index, 1);
    });
  });

  group('NoticeAudience constants', () {
    test('default is empty for backward-compatible delivery', () {
      expect(event.noticeAudienceValue(event.NoticeAudience.$default), '');
    });

    test('operator is "operator"', () {
      expect(
          event.noticeAudienceValue(event.NoticeAudience.operator), 'operator');
    });
  });

  group('FuncSink', () {
    test('forwards event to wrapped function', () {
      event.Event? received;
      final fs = event.FuncSink((e) => received = e);
      fs.emit(event.Event()
        ..kind = event.Kind.text
        ..text = 'hello');
      expect(received, isNotNull);
      expect(received!.kind, event.Kind.text);
      expect(received!.text, 'hello');
    });

    test('nil function emit is a no-op', () {
      final fs = event.FuncSink();
      fs.emit(event.Event()
        ..kind = event.Kind.text
        ..text = 'hello');
    });
  });

  group('Sync', () {
    test('treats null sink as discard', () {
      event.sync(null).emit(event.Event()
        ..kind = event.Kind.text
        ..text = 'hello');
    });

    test('forwards turn completion', () {
      final rec = _ReadinessAuditRecorder();
      event.recordTurnCompletion(event.sync(rec));
      expect(rec.turns, 1);
    });

    test('forwards workspace mutation without UI event', () {
      final rec = _ReadinessAuditRecorder();
      final sink = event.sync(rec);
      event.recordWorkspaceMutation(
          sink,
          event.WorkspaceMutation()
            ..toolName = 'write_file'
            ..paths = ['a.go']
            ..content = true);
      expect(rec.workspace.length, 1);
      expect(rec.workspace[0].toolName, 'write_file');
      expect(rec.workspace[0].paths.length, 1);
    });

    test('forwards readiness audit receipts', () {
      final rec = _ReadinessAuditRecorder();
      final sink = event.sync(rec);
      event.recordReadinessAudit(
          sink,
          evidence.ReadinessAudit()
            ..result = 'blocked'
            ..missingProjectChecks = 1
            ..commandMismatchMissing = 1);
      expect(rec.audits.length, 1);
      expect(rec.audits[0].result, 'blocked');
      expect(rec.audits[0].missingProjectChecks, 1);
    });

    test('forwards protocol recovery without emitting UI event', () {
      final rec = _ReadinessAuditRecorder();
      final sink = event.sync(rec);
      event.recordProtocolRecovery(
          sink,
          event.ProtocolRecoveryAudit(
              kind: event.ProtocolRecoveryKind.missingReasoningRetryReplaced));
      expect(rec.recovery.length, 1);
      expect(rec.recovery[0].kind,
          event.ProtocolRecoveryKind.missingReasoningRetryReplaced);
    });
  });

  group('Discard', () {
    test('accepts any event without panic', () {
      event.discard.emit(event.Event()..kind = event.Kind.turnStarted);
      event.discard.emit(event.Event()
        ..kind = event.Kind.text
        ..text = 'discarded');
      event.discard.emit(event.Event()..kind = event.Kind.turnDone);
    });
  });

  group('Event fields', () {
    test('usage/pricing/session counters', () {
      final usage = provider.Usage()
        ..promptTokens = 100
        ..completionTokens = 50;
      final pricing = provider.Pricing()
        ..input = 2.0
        ..output = 10.0
        ..currency = r'$';
      final e = event.Event()
        ..kind = event.Kind.usage
        ..usage = usage
        ..pricing = pricing
        ..sessionHit = 80
        ..sessionMiss = 20;
      expect(e.kind, event.Kind.usage);
      expect(e.usage!.promptTokens, 100);
      expect(e.pricing!.currency, r'$');
      expect(e.sessionHit, 80);
      expect(e.sessionMiss, 20);
    });
  });

  group('Tool struct', () {
    test('dispatch and result shapes', () {
      final tool = event.Tool()
        ..id = 'call-1'
        ..name = 'bash'
        ..args = '{"command":"echo hi"}'
        ..readOnly = false
        ..partial = true
        ..parentId = 'parent-1';
      expect(tool.id, 'call-1');
      expect(tool.name, 'bash');
      expect(tool.partial, isTrue);
      expect(tool.parentId, 'parent-1');

      final result = event.Tool()
        ..id = 'call-1'
        ..name = 'bash'
        ..output = 'hi\n'
        ..err = ''
        ..truncated = false;
      expect(result.output, 'hi\n');
    });
  });

  group('Approval struct', () {
    test('fields', () {
      final a = event.Approval()
        ..id = '42'
        ..tool = 'bash'
        ..subject = 'rm -rf /';
      expect(a.id, '42');
      expect(a.tool, 'bash');
      expect(a.subject, 'rm -rf /');
    });
  });

  group('Ask structs', () {
    test('question/ask/answer', () {
      final q = event.AskQuestion(
        id: 'q1',
        header: 'Confirm',
        prompt: 'Are you sure?',
        options: const [
          event.AskOption(label: 'Yes', description: 'Proceed'),
          event.AskOption(label: 'No', description: 'Cancel'),
        ],
        multi: false,
      );
      final ask = event.Ask(id: 'ask-1', questions: [q]);
      expect(ask.questions.length, 1);
      expect(ask.questions[0].options[0].label, 'Yes');

      final ans = event.AskAnswer(questionId: 'q1', selected: const ['Yes']);
      expect(ans.selected.length, 1);
      expect(ans.selected[0], 'Yes');
    });
  });

  group('Channel-backed sink', () {
    test('delivers every event in order', () {
      final received = <event.Event>[];
      final sink = event.FuncSink(received.add);

      final events = [
        event.Event()..kind = event.Kind.turnStarted,
        event.Event()
          ..kind = event.Kind.text
          ..text = 'hello',
        event.Event()
          ..kind = event.Kind.toolDispatch
          ..tool = event.Tool()
          ..name = 'bash',
        event.Event()
          ..kind = event.Kind.toolResult
          ..tool = event.Tool()
          ..output = 'ok',
        event.Event()
          ..kind = event.Kind.usage
          ..usage = provider.Usage()
          ..totalTokens = 42,
        event.Event()
          ..kind = event.Kind.notice
          ..level = event.Level.warn
          ..text = 'heads up'
          ..detail = 'diagnostics',
        event.Event()..kind = event.Kind.turnDone,
      ];
      for (final e in events) {
        sink.emit(e);
      }

      expect(received.length, events.length);
      for (var i = 0; i < events.length; i++) {
        expect(received[i].kind, events[i].kind);
        expect(received[i].detail, events[i].detail);
      }
    });
  });

  group('FuncSink concurrent emits', () {
    test('forwards each emit exactly once', () {
      var count = 0;
      final sink = event.FuncSink((_) => count++);
      for (var i = 0; i < 100; i++) {
        sink.emit(event.Event()..kind = event.Kind.text);
      }
      expect(count, 100);
    });
  });
}

/// Mirrors Go's readinessAuditRecorder test double: implements Sink plus the
/// optional audit capabilities exercised by the Sync forwarding tests.
class _ReadinessAuditRecorder
    implements
        event.Sink,
        event.ReadinessAuditSink,
        event.ProtocolRecoveryAuditSink,
        event.TurnCompletionSink,
        event.WorkspaceMutationSink {
  final audits = <evidence.ReadinessAudit>[];
  final recovery = <event.ProtocolRecoveryAudit>[];
  final workspace = <event.WorkspaceMutation>[];
  int turns = 0;

  @override
  void emit(event.Event e) {}

  @override
  void recordReadinessAudit(evidence.ReadinessAudit a) => audits.add(a);

  @override
  void recordProtocolRecovery(event.ProtocolRecoveryAudit a) => recovery.add(a);

  @override
  void recordTurnCompletion() => turns++;

  @override
  void recordWorkspaceMutation(event.WorkspaceMutation m) => workspace.add(m);
}
