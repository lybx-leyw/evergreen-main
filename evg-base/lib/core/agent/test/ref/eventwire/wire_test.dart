/// Port of reasonix/internal/eventwire/wire_test.go.
///
/// Translation notes:
/// - JSON assertions use jsonEncode(w.toJson()) and substring checks,
///   mirroring Go's json.Marshal + strings.Contains.
/// - The two tests that read .reasonix-ref/desktop/frontend/src/lib/types.ts
///   assert host-side TS contract coverage; evg-base is a Flutter app with no
///   TS frontend, so those are adapted to assert the same invariant locally:
///   every event.Kind has a non-empty, unique wire name (the TS file in the
///   ref would be generated from the same kindNames table).
library;

import 'dart:convert';

import 'package:test/test.dart';

import '../../../ref/event/event.dart' as event;
import '../../../ref/eventwire/wire.dart' as wire;
import '../../../ref/provider/decision_receipt.dart' as provider;
import '../../../ref/provider/pricing.dart' as pricing;
import '../../../ref/provider/usage.dart' as usage;

void main() {
  group('ToWire retrying JSON', () {
    test('carries retry fields', () {
      final w = wire.toWire(event.Event()
        ..kind = event.Kind.retrying
        ..retryAttempt = 3
        ..retryMax = 10
        ..retryScope = event.RetryScope.stream);
      final s = jsonEncode(w.toJson());
      for (final want in [
        '"kind":"retrying"',
        '"retryAttempt":3',
        '"retryMax":10',
        '"retryScope":"stream"',
      ]) {
        expect(s, contains(want));
      }
    });
  });

  group('ToWire stream attempt JSON', () {
    test('carries attempt fields', () {
      final w = wire.toWire(event.Event()
        ..kind = event.Kind.streamAttempt
        ..streamAttempt = event.StreamAttemptInfo()
        ..id = 'sa-1'
        ..action = event.StreamAttemptAction.discard
        ..attempt = 2
        ..max = 6
        ..reason = 'connection_reset');
      final s = jsonEncode(w.toJson());
      for (final want in [
        '"kind":"stream_attempt"',
        '"id":"sa-1"',
        '"action":"discard"',
        '"attempt":2',
        '"max":6',
        '"reason":"connection_reset"',
      ]) {
        expect(s, contains(want));
      }
    });
  });

  group('ToWire workspace changed', () {
    test('keeps bounded empty arrays', () {
      final w = wire.toWire(event.Event()
        ..kind = event.Kind.workspaceChanged
        ..workspace = event.WorkspaceChangedPayload()
        ..revisions = event.WorkspaceRevision()
        ..content = 4
        ..tree = 2
        ..workingTree = 3
        ..gitMeta = 1
        ..session = 7
        ..watchState = event.WorkspaceWatchState.degraded
        ..source = 'reconcile');
      expect(w.workspace, isNotNull);
      expect(w.workspace!.changes, isNotNull);
      final s = jsonEncode(w.toJson());
      for (final want in [
        '"kind":"workspace_changed"',
        '"changes":[]',
        '"watchState":"degraded"',
        '"session":7',
      ]) {
        expect(s, contains(want));
      }
    });
  });

  group('ToWire context maintenance JSON', () {
    test('carries maintenance fields', () {
      final w = wire.toWire(event.Event()
        ..kind = event.Kind.contextMaintenanceEvent
        ..maintenance = event.ContextMaintenance()
        ..status = 'applied'
        ..action = 'prune'
        ..savedTokens = 4096
        ..projectionVersion = 3
        ..cacheBreak = true);
      final s = jsonEncode(w.toJson());
      for (final want in [
        '"kind":"context_maintenance"',
        '"action":"prune"',
        '"savedTokens":4096',
        '"projectionVersion":3',
        '"cacheBreak":true',
      ]) {
        expect(s, contains(want));
      }
    });
  });

  group('ToWire notice', () {
    test('carries stable code and omits when absent', () {
      final w1 = wire.toWire(event.Event()
        ..kind = event.Kind.notice
        ..level = event.Level.info
        ..code = event.noticeCodeFinalReadiness
        ..text = 'readiness copy');
      expect(jsonEncode(w1.toJson()), contains('"code":"final_readiness"'));

      final w2 = wire.toWire(event.Event()
        ..kind = event.Kind.notice
        ..level = event.Level.info
        ..text = 'codeless notice');
      expect(jsonEncode(w2.toJson()), isNot(contains('"code"')));

      final w3 = wire.toWire(event.Event()
        ..kind = event.Kind.text
        ..code = 'stray');
      expect(jsonEncode(w3.toJson()), isNot(contains('"code"')));
    });

    test('carries decision receipt', () {
      final w = wire.toWire(event.Event()
        ..kind = event.Kind.notice
        ..level = event.Level.info
        ..code = event.noticeCodeDecisionReceipt
        ..text = 'Decision recorded: allow_once'
        ..decisionReceipt = const provider.DecisionReceipt(
            id: 'approval-1',
            kind: 'tool',
            tool: 'write_file',
            subject: 'src/app.go',
            outcome: 'allow_once'));
      expect(w.decisionReceipt, isNotNull);
      expect(w.decisionReceipt!.id, 'approval-1');
      expect(w.decisionReceipt!.outcome, 'allow_once');
      final s = jsonEncode(w.toJson());
      for (final want in [
        '"code":"decision_receipt"',
        '"decisionReceipt"',
        '"outcome":"allow_once"',
      ]) {
        expect(s, contains(want));
      }
    });

    test('level and detail', () {
      final w = wire.toWire(event.Event()
        ..kind = event.Kind.notice
        ..level = event.Level.warn
        ..text = 'short'
        ..detail = 'diagnostics');
      expect(w.kind, 'notice');
      expect(w.level, 'warn');
      expect(w.text, 'short');
      expect(w.detail, 'diagnostics');
      final s = jsonEncode(w.toJson());
      for (final want in [
        '"kind":"notice"',
        '"text":"short"',
        '"detail":"diagnostics"',
        '"level":"warn"',
      ]) {
        expect(s, contains(want));
      }
    });
  });

  group('ToWire write-access approval', () {
    test('keeps non-nil arrays', () {
      final w = wire.toWire(event.Event()
        ..kind = event.Kind.approvalRequest
        ..approval = event.Approval()
        ..id = 'a3'
        ..tool = 'bash'
        ..subject = 'install'
        ..kind = event.approvalKindWriteAccess
        ..writeAccess =
            event.normalizeWriteAccessApproval(event.WriteAccessApproval()));
      final body = jsonEncode(w.toJson());
      expect(body, contains('"write_access"'));
      expect(body, contains('"directories":[]'));
    });
  });

  group('Kind names', () {
    test('every kind has a non-empty wire name', () {
      for (final k in event.Kind.values) {
        expect(wire.kindName(k), isNotNull, reason: 'kind $k has no wire name');
        expect(wire.kindName(k), isNotEmpty,
            reason: 'kind $k has empty wire name');
      }
    });

    test('wire names are unique', () {
      final names = event.Kind.values.map((k) => wire.kindName(k)).toList();
      expect(names.toSet().length, names.length);
    });

    test('kindNames covers all kinds in order', () {
      final names = wire.kindNames();
      expect(names.length, event.Kind.values.length);
      for (var i = 0; i < names.length; i++) {
        expect(names[i], wire.kindName(event.Kind.values[i]));
      }
    });
  });

  group('ToWire tool', () {
    test('carries resolved capability metadata', () {
      final w = wire.toWire(event.Event()
        ..kind = event.Kind.toolDispatch
        ..tool = event.Tool()
        ..id = 'c1'
        ..name = 'use_capability'
        ..args = '{"action":"call","capability_id":"mcp-tool:db/write"}'
        ..resolvedName = 'mcp__db__write'
        ..capabilityId = 'mcp-tool:db/write'
        ..readOnly = false
        ..refreshed = true);
      final s = jsonEncode(w.toJson());
      for (final want in [
        '"name":"use_capability"',
        '"resolvedName":"mcp__db__write"',
        '"capabilityId":"mcp-tool:db/write"',
        '"readOnly":false',
        '"refreshed":true',
      ]) {
        expect(s, contains(want));
      }
    });

    test('omits host-only workspace mutation metadata', () {
      const privatePath = '/Users/private/secret-project/file.go';
      final w = wire.toWire(event.Event()
        ..kind = event.Kind.toolResult
        ..tool = event.Tool()
        ..id = 'c1'
        ..name = 'write_file'
        ..workspaceMutation = true
        ..workspacePaths = [privatePath]
        ..workspaceAllPaths = true);
      final s = jsonEncode(w.toJson());
      expect(s, isNot(contains(privatePath)));
      expect(s, isNot(contains('workspaceMutation')));
      expect(s, isNot(contains('workspacePaths')));
    });

    test('full payload JSON', () {
      final w = wire.toWire(event.Event()
        ..kind = event.Kind.toolDispatch
        ..tool = event.Tool()
        ..id = 'call-1'
        ..name = 'task'
        ..args = '{"prompt":"x"}'
        ..output = 'ignored'
        ..err = 'blocked'
        ..readOnly = true
        ..truncated = true
        ..durationMs = 522
        ..startedAt = 1754500000000
        ..endedAt = 1754500000522
        ..partial = true
        ..refreshed = true
        ..parentId = 'parent-1'
        ..diff = '@@ -1 +1 @@\n-old\n+new\n'
        ..added = 1
        ..removed = 1
        ..profile = event.Profile(model: 'deepseek-pro', effort: 'max'));
      final s = jsonEncode(w.toJson());
      for (final want in [
        '"kind":"tool_dispatch"',
        '"id":"call-1"',
        '"name":"task"',
        '"args":"{\\"prompt\\":\\"x\\"}"',
        '"output":"ignored"',
        '"err":"blocked"',
        '"readOnly":true',
        '"truncated":true',
        '"durationMs":522',
        '"partial":true',
        '"refreshed":true',
        '"startedAt":1754500000000',
        '"endedAt":1754500000522',
        '"parentId":"parent-1"',
        '"diff":"@@ -1 +1 @@\\n-old\\n+new\\n"',
        '"added":1',
        '"removed":1',
        '"profile":{"model":"deepseek-pro","effort":"max"}',
      ]) {
        expect(s, contains(want));
      }
    });
  });

  group('ToWire usage payload', () {
    test('full payload JSON', () {
      final w = wire.toWire(event.Event()
        ..kind = event.Kind.usage
        ..usage = usage.Usage()
        ..promptTokens = 1000
        ..completionTokens = 200
        ..totalTokens = 1200
        ..cacheHitTokens = 900
        ..cacheMissTokens = 100
        ..reasoningTokens = 33
        ..estimated = true
        ..pricing = pricing.Pricing()
        ..cacheHit = 0.02
        ..input = 1
        ..output = 2
        ..usageSource = event.usageSourceTitle
        ..cacheDiagnostics = event.CacheDiagnostics()
        ..prefixHash = 'p'
        ..prefixChanged = true
        ..prefixChangeReasons = ['log_rewrite']
        ..systemHash = 's'
        ..toolsHash = 't'
        ..logRewriteVersion = 1
        ..toolSchemaTokens = 42
        ..cacheMissTokens = 100
        ..cacheHitTokens = 900
        ..sessionHit = 8000
        ..sessionMiss = 2000);
      final s = jsonEncode(w.toJson());
      for (final want in [
        '"kind":"usage"',
        '"promptTokens":1000',
        '"completionTokens":200',
        '"totalTokens":1200',
        '"cacheHitTokens":900',
        '"cacheMissTokens":100',
        '"reasoningTokens":33',
        '"estimated":true',
        '"source":"title"',
        '"sessionCacheHitTokens":8000',
        '"sessionCacheMissTokens":2000',
        '"currency":"¥"',
        '"costUsd":',
        '"cacheDiagnostics":',
        '"prefixHash":"p"',
        '"prefixChanged":true',
        '"prefixChangeReasons":["log_rewrite"]',
        '"toolSchemaTokens":42',
      ]) {
        expect(s, contains(want));
      }
    });
  });

  group('ToWire interaction and lifecycle payloads', () {
    test('approval', () {
      final w = wire.toWire(event.Event()
        ..kind = event.Kind.approvalRequest
        ..approval = event.Approval()
        ..id = 'a1'
        ..tool = 'bash'
        ..subject = 'rm');
      final s = jsonEncode(w.toJson());
      expect(s, contains('"kind":"approval_request"'));
      expect(
          s, contains('"approval":{"id":"a1","tool":"bash","subject":"rm"}'));
    });

    test('fresh approval', () {
      final w = wire.toWire(event.Event()
        ..kind = event.Kind.approvalRequest
        ..approval = event.Approval()
        ..id = 'a2'
        ..tool = 'mcp__srv__wipe'
        ..subject = 'srv/wipe'
        ..fresh = true);
      final s = jsonEncode(w.toJson());
      expect(s, contains('"kind":"approval_request"'));
      expect(s, contains('"tool":"mcp__srv__wipe"'));
      expect(s, contains('"fresh":true'));
    });

    test('recovery task grant', () {
      final w = wire.toWire(event.Event()
        ..kind = event.Kind.approvalRequest
        ..approval = event.Approval()
        ..id = 'r1'
        ..tool = 'bash'
        ..subject = 'git push origin feature'
        ..fresh = true
        ..kind = 'recovery'
        ..recovery = event.RecoveryApproval()
        ..nextAction = 'git push origin feature'
        ..canGrantTask = true
        ..taskGrantScope = 'git push origin → feature');
      final s = jsonEncode(w.toJson());
      expect(s, contains('"kind":"recovery"'));
      expect(s, contains('"next_action":"git push origin feature"'));
      expect(s, contains('"can_grant_task":true'));
      expect(s, contains('"task_grant_scope":"git push origin → feature"'));
    });

    test('recovery plan transition', () {
      final w = wire.toWire(event.Event()
        ..kind = event.Kind.approvalRequest
        ..approval = event.Approval()
        ..id = 'r-plan'
        ..tool = 'todo_write'
        ..subject = 'Update the active execution plan'
        ..fresh = true
        ..kind = 'recovery'
        ..recovery = event.RecoveryApproval()
        ..changeKind = 'scope'
        ..planBefore = '1. Keep API'
        ..planAfter = '1. Replace API');
      final s = jsonEncode(w.toJson());
      expect(s, contains('"kind":"recovery"'));
      expect(s, contains('"change_kind":"scope"'));
      expect(s, contains('"plan_before":"1. Keep API"'));
      expect(s, contains('"plan_after":"1. Replace API"'));
    });

    test('ask', () {
      final w = wire.toWire(event.Event()
        ..kind = event.Kind.askRequest
        ..ask = event.Ask(id: 'ask-1', questions: [
          event.AskQuestion(
            id: 'q1',
            header: 'Pick',
            prompt: 'Choose',
            multi: true,
            options: const [
              event.AskOption(label: 'A', description: 'Alpha'),
              event.AskOption(label: 'B'),
            ],
          ),
        ]));
      final s = jsonEncode(w.toJson());
      expect(s, contains('"kind":"ask_request"'));
      expect(s, contains('"ask":{"id":"ask-1"'));
      expect(s, contains('"header":"Pick"'));
      expect(s, contains('"description":"Alpha"'));
      expect(s, contains('"multi":true'));
    });

    test('compaction', () {
      final w = wire.toWire(event.Event()
        ..kind = event.Kind.compactionDone
        ..compaction = event.Compaction()
        ..trigger = 'manual'
        ..messages = 7
        ..summary = 'brief'
        ..archive = '/tmp/archive.jsonl');
      final s = jsonEncode(w.toJson());
      expect(s, contains('"kind":"compaction_done"'));
      expect(s, contains('"trigger":"manual"'));
      expect(s, contains('"messages":7'));
      expect(s, contains('"summary":"brief"'));
      expect(s, contains('"archive":"/tmp/archive.jsonl"'));
    });

    test('turn done error', () {
      final w = wire.toWire(event.Event()
        ..kind = event.Kind.turnDone
        ..err = Exception('boom'));
      final s = jsonEncode(w.toJson());
      expect(s, contains('"kind":"turn_done"'));
      expect(s, contains('"err":"Exception: boom"'));
    });

    test('steer', () {
      final w = wire.toWire(event.Event()
        ..kind = event.Kind.steer
        ..text = 'mid-turn guidance');
      final s = jsonEncode(w.toJson());
      expect(s, contains('"kind":"steer"'));
      expect(s, contains('"text":"mid-turn guidance"'));
    });
  });

  group('ToWire turn done', () {
    test('outcome is optional and machine readable', () {
      final readiness = wire.toWire(event.Event()
        ..kind = event.Kind.turnDone
        ..err = Exception('final-answer readiness failed 3 times')
        ..outcome = event.turnOutcomeFinalReadiness
        ..readiness = event.FinalReadiness()
        ..attempts = 3
        ..missing = ['verification', 'review']);
      expect(readiness.outcome, event.turnOutcomeFinalReadiness);
      expect(readiness.err, isNotEmpty);
      expect(readiness.readiness, isNotNull);
      expect(readiness.readiness!.attempts, 3);
      final s = jsonEncode(readiness.toJson());
      expect(s, contains('"outcome":"final_readiness"'));
      expect(s, contains('"missing":["verification","review"]'));

      final ordinary = jsonEncode(wire
          .toWire(event.Event()
            ..kind = event.Kind.turnDone
            ..err = Exception('provider failed'))
          .toJson());
      expect(ordinary, isNot(contains('"outcome"')));
    });

    test('checkpoint turn preserves zero and omits nil', () {
      final withCheckpoint = jsonEncode(wire
          .toWire(event.Event()
            ..kind = event.Kind.turnDone
            ..checkpointTurn = 0)
          .toJson());
      expect(withCheckpoint, contains('"checkpointTurn":0'));

      final withoutCheckpoint = jsonEncode(
          wire.toWire(event.Event()..kind = event.Kind.turnDone).toJson());
      expect(withoutCheckpoint, isNot(contains('"checkpointTurn"')));
    });
  });

  group('ToWire message memory citations', () {
    test('preserves citation fields', () {
      final w = wire.toWire(event.Event()
        ..kind = event.Kind.message
        ..text = 'done'
        ..memoryCitations = [
          usage.MemoryCitation(
            id: 'mem-1',
            source: 'MEMORY.md',
            lineStart: 116,
            lineEnd: 123,
            note: 'reasonix workflow',
            kind: 'memory_reference',
          ),
        ]);
      expect(w.memoryCitations.length, 1);
      final got = w.memoryCitations[0];
      expect(got.source, 'MEMORY.md');
      expect(got.lineStart, 116);
      expect(got.lineEnd, 123);
      expect(got.note, 'reasonix workflow');
      expect(jsonEncode(w.toJson()), contains('"memoryCitations":['));
    });
  });
}
