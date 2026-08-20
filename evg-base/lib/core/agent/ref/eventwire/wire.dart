/// Port of reasonix/internal/eventwire.
///
/// Shared frontend JSON contract for event.Event: wire-friendly mirror types
/// plus ToWire conversions. JSON tags from the Go structs are reproduced via
/// explicit toJson() maps so the emitted shape stays byte-compatible.
library;

import 'dart:convert';

import '../billing/cost_quote.dart' as billing;
import '../event/event.dart' as event;
import '../provider/decision_receipt.dart' as provider;
import '../provider/usage.dart' as provider_usage;

// ═══════ Kind name table ═══════

const Map<event.Kind, String> _kindNames = {
  event.Kind.turnStarted: 'turn_started',
  event.Kind.reasoning: 'reasoning',
  event.Kind.text: 'text',
  event.Kind.message: 'message',
  event.Kind.toolDispatch: 'tool_dispatch',
  event.Kind.toolResult: 'tool_result',
  event.Kind.usage: 'usage',
  event.Kind.notice: 'notice',
  event.Kind.phase: 'phase',
  event.Kind.approvalRequest: 'approval_request',
  event.Kind.askRequest: 'ask_request',
  event.Kind.turnDone: 'turn_done',
  event.Kind.compactionStarted: 'compaction_started',
  event.Kind.compactionDone: 'compaction_done',
  event.Kind.toolProgress: 'tool_progress',
  event.Kind.mcpSurfaceReady: 'mcp_surface_ready',
  event.Kind.retrying: 'retrying',
  event.Kind.steer: 'steer',
  event.Kind.guardianAssessment: 'guardian_assessment',
  event.Kind.extensionSurface: 'extension_surface',
  event.Kind.extensionStatus: 'extension_status',
  event.Kind.streamAttempt: 'stream_attempt',
  event.Kind.contextMaintenanceEvent: 'context_maintenance',
  event.Kind.workspaceChanged: 'workspace_changed',
  event.Kind.turnPhase: 'turn_phase',
  event.Kind.completionSummary: 'completion_summary',
  event.Kind.toolResultPreview: 'tool_result_preview',
};

/// Every stable frontend event kind name in event.Kind order.
List<String> kindNames() =>
    event.Kind.values.map((k) => _kindNames[k] ?? '').toList();

/// Stable wire name of one event kind, or null for a kind outside the set.
String? kindName(event.Kind kind) => _kindNames[kind];

// ═══════ Wire Event ═══════

class WireEvent {
  String kind = '';
  String text = '';
  String detail = '';
  String code = '';
  String reasoning = '';
  List<WireMemoryCitation> memoryCitations = [];
  String level = '';
  WireTool? tool;
  WireUsage? usage;
  WireApproval? approval;
  WireAsk? ask;
  WireCompaction? compaction;
  WireContextMaintenance? maintenance;
  WireGuardian? guardian;
  WireDecisionReceipt? decisionReceipt;
  WireExtensionSurface? extension;
  String err = '';
  String outcome = '';
  WireFinalReadiness? readiness;
  WireCompletionReceipt? receipt;
  int? checkpointTurn;
  int retryAttempt = 0;
  int retryMax = 0;
  String retryScope = '';
  WireStreamAttempt? streamAttempt;
  String itemId = '';
  WireWorkspaceChanged? workspace;
  String phase = '';
  WireCompletionSummary? completion;

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{'kind': kind};
    void put(String key, Object? v) {
      if (v != null && v != '' && v != 0 && v != false && v != const []) {
        m[key] = v;
      }
    }

    put('text', text);
    put('detail', detail);
    put('code', code);
    put('reasoning', reasoning);
    if (memoryCitations.isNotEmpty) {
      m['memoryCitations'] = memoryCitations.map((c) => c.toJson()).toList();
    }
    put('level', level);
    put('tool', tool?.toJson());
    put('usage', usage?.toJson());
    put('approval', approval?.toJson());
    put('ask', ask?.toJson());
    put('compaction', compaction?.toJson());
    put('maintenance', maintenance?.toJson());
    put('guardian', guardian?.toJson());
    put('decisionReceipt', decisionReceipt?.toJson());
    put('extension', extension?.toJson());
    put('err', err);
    put('outcome', outcome);
    put('readiness', readiness?.toJson());
    put('receipt', receipt?.toJson());
    if (checkpointTurn != null) {
      m['checkpointTurn'] = checkpointTurn;
    }
    put('retryAttempt', retryAttempt);
    put('retryMax', retryMax);
    put('retryScope', retryScope);
    put('streamAttempt', streamAttempt?.toJson());
    put('itemId', itemId);
    put('workspace', workspace?.toJson());
    put('phase', phase);
    put('completion', completion?.toJson());
    return m;
  }
}

class WireCompletionSummary {
  String preset = '';
  String verdict = '';
  int mutations = 0;
  int checksPassed = 0;
  int checksFailed = 0;
  int checksSuppressed = 0;
  String review = '';
  List<String> gapKinds = [];
  bool constraintDegraded = false;

  Map<String, dynamic> toJson() => {
        'preset': preset,
        'verdict': verdict,
        'mutations': mutations,
        'checks_passed': checksPassed,
        'checks_failed': checksFailed,
        'checks_suppressed': checksSuppressed,
        'review': review,
        if (gapKinds.isNotEmpty) 'gap_kinds': gapKinds,
        'constraint_degraded': constraintDegraded,
      };
}

class WireWorkspaceChanged {
  WireWorkspaceRevision revisions = WireWorkspaceRevision();
  List<WireWorkspacePathChange> changes = [];
  bool allPaths = false;
  String source = '';
  String watchState = '';

  Map<String, dynamic> toJson() => {
        'revisions': revisions.toJson(),
        'changes': changes.map((c) => c.toJson()).toList(),
        'allPaths': allPaths,
        'source': source,
        'watchState': watchState,
      };
}

class WireWorkspaceRevision {
  int content = 0;
  int tree = 0;
  int workingTree = 0;
  int gitMeta = 0;
  int session = 0;

  Map<String, dynamic> toJson() => {
        'content': content,
        'tree': tree,
        'workingTree': workingTree,
        'gitMeta': gitMeta,
        'session': session,
      };
}

class WireWorkspacePathChange {
  String path = '';
  String oldPath = '';
  String op = '';

  Map<String, dynamic> toJson() => {
        'path': path,
        if (oldPath.isNotEmpty) 'oldPath': oldPath,
        'op': op,
      };
}

class WireStreamAttempt {
  String id = '';
  String action = '';
  int attempt = 0;
  int max = 0;
  String reason = '';

  Map<String, dynamic> toJson() => {
        'id': id,
        'action': action,
        if (attempt != 0) 'attempt': attempt,
        if (max != 0) 'max': max,
        if (reason.isNotEmpty) 'reason': reason,
      };
}

/// Converts a typed runtime event into the shared frontend JSON contract.
WireEvent toWire(event.Event e) {
  final w = WireEvent()
    ..kind = kindName(e.kind) ?? ''
    ..text = e.text
    ..detail = e.detail
    ..reasoning = e.reasoning
    ..itemId = e.itemId;
  if (e.memoryCitations.isNotEmpty) {
    w.memoryCitations = toWireMemoryCitations(e.memoryCitations);
  }
  switch (e.kind) {
    case event.Kind.notice:
      w.code = e.code;
      if (e.decisionReceipt != null) {
        w.decisionReceipt = toWireDecisionReceipt(e.decisionReceipt);
      }
      w.level = e.level == event.Level.warn ? 'warn' : 'info';
      break;
    case event.Kind.toolDispatch:
    case event.Kind.toolResult:
    case event.Kind.toolProgress:
    case event.Kind.toolResultPreview:
      final t = e.tool;
      final wt = WireTool()
        ..id = t.id
        ..name = t.name
        ..args = t.args
        ..resolvedName = t.resolvedName
        ..capabilityId = t.capabilityId
        ..output = t.output
        ..err = t.err
        ..readOnly = t.readOnly
        ..truncated = t.truncated
        ..durationMs = t.durationMs
        ..partial = t.partial
        ..startedAt = t.startedAt
        ..endedAt = t.endedAt
        ..argChars = t.argChars
        ..refreshed = t.refreshed
        ..parentId = t.parentId
        ..attemptId = t.attemptId
        ..diff = t.diff
        ..added = t.added
        ..removed = t.removed;
      if (t.profile != null) {
        wt.profile =
            WireProfile(model: t.profile!.model, effort: t.profile!.effort);
      }
      wt.execution = toWireShellExecution(t.execution);
      w.tool = wt;
      break;
    case event.Kind.workspaceChanged:
      final ws = e.workspace ?? event.WorkspaceChangedPayload();
      w.workspace = WireWorkspaceChanged()
        ..revisions = WireWorkspaceRevision()
        ..content = ws.revisions.content
        ..tree = ws.revisions.tree
        ..workingTree = ws.revisions.workingTree
        ..gitMeta = ws.revisions.gitMeta
        ..session = ws.revisions.session
        ..changes = ws.changes
            .map((c) => WireWorkspacePathChange()
              ..path = c.path
              ..oldPath = c.oldPath
              ..op = c.op)
            .toList()
        ..allPaths = ws.allPaths
        ..source = ws.source
        ..watchState = event.workspaceWatchStateValue(ws.watchState);
      break;
    case event.Kind.usage:
      w.usage = _toWireUsage(e);
      break;
    case event.Kind.approvalRequest:
      w.approval = _toWireApproval(e.approval);
      break;
    case event.Kind.askRequest:
      w.ask = toWireAsk(e.ask);
      break;
    case event.Kind.compactionStarted:
    case event.Kind.compactionDone:
      w.compaction = WireCompaction()
        ..trigger = e.compaction.trigger
        ..messages = e.compaction.messages
        ..summary = e.compaction.summary
        ..archive = e.compaction.archive;
      break;
    case event.Kind.contextMaintenanceEvent:
      final m = e.maintenance;
      if (m != null) {
        w.maintenance = WireContextMaintenance()
          ..status = m.status
          ..action = m.action
          ..trigger = m.trigger
          ..operationId = m.operationId
          ..inputTokens = m.inputTokens
          ..resultTokens = m.resultTokens
          ..savedTokens = m.savedTokens
          ..affectedToolResults = m.affectedToolResults
          ..projectionVersion = m.projectionVersion
          ..cacheBreak = m.cacheBreak
          ..reason = m.reason;
      }
      break;
    case event.Kind.guardianAssessment:
      w.guardian = toWireGuardian(e.guardian);
      break;
    case event.Kind.extensionSurface:
    case event.Kind.extensionStatus:
      w.extension = toWireExtensionSurface(e.extension);
      break;
    case event.Kind.turnDone:
      w.outcome = e.outcome;
      w.checkpointTurn = e.checkpointTurn;
      w.receipt = _completionReceiptWire(e.receipt);
      if (e.readiness != null) {
        w.readiness = WireFinalReadiness()
          ..attempts = e.readiness!.attempts
          ..missing = List.of(e.readiness!.missing);
      }
      if (e.err != null) {
        w.err = e.err.toString();
      }
      break;
    case event.Kind.retrying:
      w.retryAttempt = e.retryAttempt;
      w.retryMax = e.retryMax;
      if (e.retryScope != null) {
        w.retryScope = event.retryScopeValue(e.retryScope!);
      }
      break;
    case event.Kind.streamAttempt:
      w.streamAttempt = WireStreamAttempt()
        ..id = e.streamAttempt.id
        ..action = event.streamAttemptActionValue(e.streamAttempt.action)
        ..attempt = e.streamAttempt.attempt
        ..max = e.streamAttempt.max
        ..reason = e.streamAttempt.reason;
      break;
    case event.Kind.turnPhase:
      w.phase = event.turnPhaseNameValue(e.phaseName);
      if (w.phase.isEmpty) {
        w.phase = e.text;
      }
      break;
    case event.Kind.completionSummary:
      final c = e.completion;
      if (c != null) {
        w.completion = WireCompletionSummary()
          ..preset = c.preset
          ..verdict = c.verdict
          ..mutations = c.mutations
          ..checksPassed = c.checksPassed
          ..checksFailed = c.checksFailed
          ..checksSuppressed = c.checksSuppressed
          ..review = c.review
          ..gapKinds = List.of(c.gapKinds)
          ..constraintDegraded = c.constraintDegraded;
      }
      break;
    default:
      break;
  }
  return w;
}

WireUsage? _toWireUsage(event.Event e) {
  final u = e.usage;
  if (u == null) return null;
  final wire = WireUsage()
    ..promptTokens = u.promptTokens
    ..completionTokens = u.completionTokens
    ..totalTokens = u.totalTokens
    ..cacheHitTokens = u.cacheHitTokens ?? 0
    ..cacheMissTokens = u.cacheMissTokens ?? 0
    ..reasoningTokens = u.reasoningTokens
    ..estimated = u.estimated
    ..source = e.usageSource
    ..contextPromptTokens = u.contextPromptTokens
    ..contextCompletionTokens = u.contextCompletionTokens
    ..contextReasoningTokens = u.contextReasoningTokens
    ..contextCacheHitTokens = u.contextCacheHitTokens
    ..contextCacheMissTokens = u.contextCacheMissTokens
    ..sessionCacheHitTokens = e.sessionHit
    ..sessionCacheMissTokens = e.sessionMiss;
  if (e.cacheDiagnostics != null) {
    wire.cacheDiagnostics = toWireCacheDiagnostics(e.cacheDiagnostics!);
  }
  var quote = e.costQuote;
  if (quote == null && e.pricing != null) {
    quote = event.ensureCostQuote(e, null);
  }
  if (quote != null) {
    wire.costQuote = quote;
    wire.costComplete = quote.costComplete;
    wire.displayComplete = quote.displayComplete;
    wire.displayStatus = quote.displayStatus;
    wire.aggregateMode = quote.aggregateMode;
    wire.originalTotals = List.of(quote.originalTotals);
    if (quote.selected != null) {
      wire.cost = quote.selected!.float64();
      wire.currency = quote.legacyCurrencySymbol();
      wire.costUSD = wire.cost;
      wire.currencyCode = quote.legacyCurrencyCode();
    }
  }
  return wire;
}

class WireDecisionReceipt {
  String id = '';
  String kind = '';
  String tool = '';
  String subject = '';
  String outcome = '';

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        if (tool.isNotEmpty) 'tool': tool,
        if (subject.isNotEmpty) 'subject': subject,
        'outcome': outcome,
      };
}

WireDecisionReceipt? toWireDecisionReceipt(provider.DecisionReceipt? in_) {
  if (in_ == null) return null;
  return WireDecisionReceipt()
    ..id = in_.id
    ..kind = in_.kind
    ..tool = in_.tool
    ..subject = in_.subject
    ..outcome = in_.outcome;
}

class WireFinalReadiness {
  int attempts = 0;
  List<String> missing = [];

  Map<String, dynamic> toJson() => {
        if (attempts != 0) 'attempts': attempts,
        if (missing.isNotEmpty) 'missing': missing,
      };
}

class WireMemoryCitation {
  String id = '';
  String source = '';
  int lineStart = 0;
  int lineEnd = 0;
  String note = '';
  String kind = '';

  Map<String, dynamic> toJson() => {
        if (id.isNotEmpty) 'id': id,
        'source': source,
        if (lineStart != 0) 'lineStart': lineStart,
        if (lineEnd != 0) 'lineEnd': lineEnd,
        if (note.isNotEmpty) 'note': note,
        if (kind.isNotEmpty) 'kind': kind,
      };
}

List<WireMemoryCitation> toWireMemoryCitations(
    List<provider_usage.MemoryCitation> in_) {
  final out = <WireMemoryCitation>[];
  for (final c in in_) {
    if (c.source.isEmpty && c.id.isEmpty && c.note.isEmpty) {
      continue;
    }
    out.add(WireMemoryCitation()
      ..id = c.id
      ..source = c.source
      ..lineStart = c.lineStart
      ..lineEnd = c.lineEnd
      ..note = c.note
      ..kind = c.kind);
  }
  return out;
}

class WireCompaction {
  String trigger = '';
  int messages = 0;
  String summary = '';
  String archive = '';

  Map<String, dynamic> toJson() => {
        if (trigger.isNotEmpty) 'trigger': trigger,
        if (messages != 0) 'messages': messages,
        if (summary.isNotEmpty) 'summary': summary,
        if (archive.isNotEmpty) 'archive': archive,
      };
}

class WireAskOption {
  String label = '';
  String description = '';

  Map<String, dynamic> toJson() => {
        'label': label,
        if (description.isNotEmpty) 'description': description,
      };
}

class WireAskQuestion {
  String id = '';
  String header = '';
  String prompt = '';
  List<WireAskOption> options = [];
  bool multi = false;

  Map<String, dynamic> toJson() => {
        'id': id,
        if (header.isNotEmpty) 'header': header,
        'prompt': prompt,
        'options': options.map((o) => o.toJson()).toList(),
        if (multi) 'multi': multi,
      };
}

class WireAsk {
  String id = '';
  List<WireAskQuestion> questions = [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'questions': questions.map((q) => q.toJson()).toList(),
      };
}

WireAsk? toWireAsk(event.Ask a) {
  final qs = <WireAskQuestion>[];
  for (final q in a.questions) {
    final opts = <WireAskOption>[];
    for (final o in q.options) {
      opts.add(WireAskOption()
        ..label = o.label
        ..description = o.description);
    }
    qs.add(WireAskQuestion()
      ..id = q.id
      ..header = q.header
      ..prompt = q.prompt
      ..options = opts
      ..multi = q.multi);
  }
  return WireAsk()
    ..id = a.id
    ..questions = qs;
}

class WireProfile {
  String model = '';
  String effort = '';

  WireProfile({this.model = '', this.effort = ''});

  Map<String, dynamic> toJson() => {
        if (model.isNotEmpty) 'model': model,
        if (effort.isNotEmpty) 'effort': effort,
      };
}

class WireTool {
  String id = '';
  String name = '';
  String args = '';
  String resolvedName = '';
  String capabilityId = '';
  String output = '';
  String err = '';
  bool readOnly = false;
  bool truncated = false;
  int durationMs = 0;
  int startedAt = 0;
  int endedAt = 0;
  bool partial = false;
  int argChars = 0;
  bool refreshed = false;
  String parentId = '';
  String attemptId = '';
  String diff = '';
  int added = 0;
  int removed = 0;
  WireProfile? profile;
  WireShellExecution? execution;

  Map<String, dynamic> toJson() => {
        if (id.isNotEmpty) 'id': id,
        'name': name,
        if (args.isNotEmpty) 'args': args,
        if (resolvedName.isNotEmpty) 'resolvedName': resolvedName,
        if (capabilityId.isNotEmpty) 'capabilityId': capabilityId,
        if (output.isNotEmpty) 'output': output,
        if (err.isNotEmpty) 'err': err,
        'readOnly': readOnly,
        if (truncated) 'truncated': truncated,
        if (durationMs != 0) 'durationMs': durationMs,
        if (startedAt != 0) 'startedAt': startedAt,
        if (endedAt != 0) 'endedAt': endedAt,
        if (partial) 'partial': partial,
        if (argChars != 0) 'argChars': argChars,
        if (refreshed) 'refreshed': refreshed,
        if (parentId.isNotEmpty) 'parentId': parentId,
        if (attemptId.isNotEmpty) 'attemptId': attemptId,
        if (diff.isNotEmpty) 'diff': diff,
        if (added != 0) 'added': added,
        if (removed != 0) 'removed': removed,
        if (profile != null) 'profile': profile!.toJson(),
        if (execution != null) 'execution': execution!.toJson(),
      };
}

class WireShellExecution {
  String kind = '';
  String shell = '';
  String shellVersion = '';
  String platform = '';
  bool supportsAndAnd = false;
  String state = '';
  String failurePhase = '';
  int? exitCode;
  String outputTail = '';
  String mutationRisk = '';
  String verification = '';
  int durationMs = 0;

  Map<String, dynamic> toJson() => {
        if (kind.isNotEmpty) 'kind': kind,
        if (shell.isNotEmpty) 'shell': shell,
        if (shellVersion.isNotEmpty) 'shellVersion': shellVersion,
        if (platform.isNotEmpty) 'platform': platform,
        'supportsAndAnd': supportsAndAnd,
        if (state.isNotEmpty) 'state': state,
        if (failurePhase.isNotEmpty) 'failurePhase': failurePhase,
        if (exitCode != null) 'exitCode': exitCode,
        if (outputTail.isNotEmpty) 'outputTail': outputTail,
        if (mutationRisk.isNotEmpty) 'mutationRisk': mutationRisk,
        if (verification.isNotEmpty) 'verification': verification,
        if (durationMs != 0) 'durationMs': durationMs,
      };
}

WireShellExecution? toWireShellExecution(event.ShellExecution? in_) {
  if (in_ == null) return null;
  return WireShellExecution()
    ..kind = in_.kind
    ..shell = in_.shell
    ..shellVersion = in_.shellVersion
    ..platform = in_.platform
    ..supportsAndAnd = in_.supportsAndAnd
    ..state = in_.state
    ..failurePhase = in_.failurePhase
    ..exitCode = in_.exitCode
    ..outputTail = in_.outputTail
    ..mutationRisk = in_.mutationRisk
    ..verification = in_.verification
    ..durationMs = in_.durationMs;
}

class WireUsage {
  int promptTokens = 0;
  int completionTokens = 0;
  int totalTokens = 0;
  int cacheHitTokens = 0;
  int cacheMissTokens = 0;
  int reasoningTokens = 0;
  bool estimated = false;
  String source = '';
  WireCacheDiagnostics? cacheDiagnostics;
  int sessionCacheHitTokens = 0;
  int sessionCacheMissTokens = 0;
  int contextPromptTokens = 0;
  int contextCompletionTokens = 0;
  int contextReasoningTokens = 0;
  int contextCacheHitTokens = 0;
  int contextCacheMissTokens = 0;
  double cost = 0.0;
  String currency = '';
  String currencyCode = '';
  double costUSD = 0.0;
  billing.CostQuote? costQuote;
  bool costComplete = false;
  bool displayComplete = false;
  String displayStatus = '';
  String aggregateMode = '';
  List<String> originalTotals = [];

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'promptTokens': promptTokens,
      'completionTokens': completionTokens,
      'totalTokens': totalTokens,
      'cacheHitTokens': cacheHitTokens,
      'cacheMissTokens': cacheMissTokens,
      if (reasoningTokens != 0) 'reasoningTokens': reasoningTokens,
      if (estimated) 'estimated': estimated,
      if (source.isNotEmpty) 'source': source,
      if (cacheDiagnostics != null)
        'cacheDiagnostics': cacheDiagnostics!.toJson(),
      'sessionCacheHitTokens': sessionCacheHitTokens,
      'sessionCacheMissTokens': sessionCacheMissTokens,
      if (contextPromptTokens != 0) 'contextPromptTokens': contextPromptTokens,
      if (contextCompletionTokens != 0)
        'contextCompletionTokens': contextCompletionTokens,
      if (contextReasoningTokens != 0)
        'contextReasoningTokens': contextReasoningTokens,
      if (contextCacheHitTokens != 0)
        'contextCacheHitTokens': contextCacheHitTokens,
      if (contextCacheMissTokens != 0)
        'contextCacheMissTokens': contextCacheMissTokens,
      if (cost != 0) 'cost': cost,
      if (currency.isNotEmpty) 'currency': currency,
      if (currencyCode.isNotEmpty) 'currencyCode': currencyCode,
      if (costUSD != 0) 'costUsd': costUSD,
      if (costQuote != null) 'costQuote': _costQuoteToJson(costQuote!),
      if (costComplete) 'costComplete': costComplete,
      if (displayComplete) 'displayComplete': displayComplete,
      if (displayStatus.isNotEmpty) 'displayStatus': displayStatus,
      if (aggregateMode.isNotEmpty) 'aggregateMode': aggregateMode,
      if (originalTotals.isNotEmpty) 'originalTotals': originalTotals,
    };
    return m;
  }
}

class WireCacheDiagnostics {
  String prefixHash = '';
  bool prefixChanged = false;
  List<String> prefixChangeReasons = [];
  String systemHash = '';
  String toolsHash = '';
  int logRewriteVersion = 0;
  int toolSchemaTokens = 0;
  int cacheMissTokens = 0;
  int cacheHitTokens = 0;

  Map<String, dynamic> toJson() => {
        'prefixHash': prefixHash,
        'prefixChanged': prefixChanged,
        if (prefixChangeReasons.isNotEmpty)
          'prefixChangeReasons': prefixChangeReasons,
        'systemHash': systemHash,
        'toolsHash': toolsHash,
        'logRewriteVersion': logRewriteVersion,
        'toolSchemaTokens': toolSchemaTokens,
        'cacheMissTokens': cacheMissTokens,
        'cacheHitTokens': cacheHitTokens,
      };
}

WireCacheDiagnostics toWireCacheDiagnostics(event.CacheDiagnostics d) {
  return WireCacheDiagnostics()
    ..prefixHash = d.prefixHash
    ..prefixChanged = d.prefixChanged
    ..prefixChangeReasons = List.of(d.prefixChangeReasons)
    ..systemHash = d.systemHash
    ..toolsHash = d.toolsHash
    ..logRewriteVersion = d.logRewriteVersion
    ..toolSchemaTokens = d.toolSchemaTokens
    ..cacheMissTokens = d.cacheMissTokens
    ..cacheHitTokens = d.cacheHitTokens;
}

class WireGuardian {
  String id = '';
  String tool = '';
  String subject = '';
  String outcome = '';
  String riskLevel = '';
  String userAuthorization = '';
  String rationale = '';
  int durationMs = 0;
  WireUsage? usage;

  Map<String, dynamic> toJson() => {
        'id': id,
        'tool': tool,
        'subject': subject,
        'outcome': outcome,
        if (riskLevel.isNotEmpty) 'risk_level': riskLevel,
        if (userAuthorization.isNotEmpty)
          'user_authorization': userAuthorization,
        if (rationale.isNotEmpty) 'rationale': rationale,
        if (durationMs != 0) 'duration_ms': durationMs,
        if (usage != null) 'usage': usage!.toJson(),
      };
}

WireGuardian? toWireGuardian(event.GuardianResult g) {
  final out = WireGuardian()
    ..id = g.id
    ..tool = g.tool
    ..subject = g.subject
    ..outcome = g.outcome
    ..riskLevel = g.riskLevel
    ..userAuthorization = g.userAuthorization
    ..rationale = g.rationale
    ..durationMs = g.durationMs;
  if (g.usage != null) {
    final u = g.usage!;
    out.usage = WireUsage()
      ..promptTokens = u.promptTokens
      ..completionTokens = u.completionTokens
      ..totalTokens = u.totalTokens
      ..cacheHitTokens = u.cacheHitTokens ?? 0
      ..cacheMissTokens = u.cacheMissTokens ?? 0
      ..reasoningTokens = u.reasoningTokens
      ..estimated = u.estimated;
    if (g.pricing != null) {
      final q = event.ensureCostQuote(
          event.Event()
            ..kind = event.Kind.usage
            ..usage = u
            ..pricing = g.pricing,
          null);
      if (q != null) {
        out.usage!.costQuote = q;
        out.usage!.cost = q.cost;
        out.usage!.currency = q.legacyCurrencySymbol();
        out.usage!.costUSD = out.usage!.cost;
        out.usage!.currencyCode = q.legacyCurrencyCode();
      }
    }
  }
  return out;
}

class WireContextMaintenance {
  String status = '';
  String action = '';
  String trigger = '';
  String operationId = '';
  int inputTokens = 0;
  int resultTokens = 0;
  int savedTokens = 0;
  int affectedToolResults = 0;
  int projectionVersion = 0;
  bool cacheBreak = false;
  String reason = '';

  Map<String, dynamic> toJson() => {
        if (status.isNotEmpty) 'status': status,
        if (action.isNotEmpty) 'action': action,
        if (trigger.isNotEmpty) 'trigger': trigger,
        if (operationId.isNotEmpty) 'operationId': operationId,
        if (inputTokens != 0) 'inputTokens': inputTokens,
        if (resultTokens != 0) 'resultTokens': resultTokens,
        if (savedTokens != 0) 'savedTokens': savedTokens,
        if (affectedToolResults != 0)
          'affectedToolResults': affectedToolResults,
        if (projectionVersion != 0) 'projectionVersion': projectionVersion,
        if (cacheBreak) 'cacheBreak': cacheBreak,
        if (reason.isNotEmpty) 'reason': reason,
      };
}

class WireExtensionSurface {
  String pluginId = '';
  String surfaceId = '';
  String sessionId = '';
  int generation = 0;
  String kind = '';
  WireExtensionStatus? status;
  WireExtensionCard? card;
  WireExtensionForm? form;
  WireExtensionNotification? notification;

  Map<String, dynamic> toJson() => {
        'pluginId': pluginId,
        'surfaceId': surfaceId,
        if (sessionId.isNotEmpty) 'sessionId': sessionId,
        if (generation != 0) 'generation': generation,
        'kind': kind,
        if (status != null) 'status': status!.toJson(),
        if (card != null) 'card': card!.toJson(),
        if (form != null) 'form': form!.toJson(),
        if (notification != null) 'notification': notification!.toJson(),
      };
}

class WireExtensionStatus {
  String label = '';
  String detail = '';
  String severity = '';
  double? progress;

  Map<String, dynamic> toJson() => {
        'label': label,
        if (detail.isNotEmpty) 'detail': detail,
        if (severity.isNotEmpty) 'severity': severity,
        if (progress != null) 'progress': progress,
      };
}

class WireExtensionKeyValue {
  String key = '';
  String value = '';

  Map<String, dynamic> toJson() => {'key': key, 'value': value};
}

class WireExtensionActionRef {
  String actionId = '';
  String label = '';

  Map<String, dynamic> toJson() => {'actionId': actionId, 'label': label};
}

class WireExtensionCard {
  String title = '';
  String markdown = '';
  String text = '';
  List<WireExtensionKeyValue> fields = [];
  double? progress;
  List<WireExtensionActionRef> actions = [];

  Map<String, dynamic> toJson() => {
        if (title.isNotEmpty) 'title': title,
        if (markdown.isNotEmpty) 'markdown': markdown,
        if (text.isNotEmpty) 'text': text,
        if (fields.isNotEmpty) 'fields': fields.map((f) => f.toJson()).toList(),
        if (progress != null) 'progress': progress,
        if (actions.isNotEmpty)
          'actions': actions.map((a) => a.toJson()).toList(),
      };
}

class WireExtensionFormField {
  String key = '';
  String label = '';
  String kind = '';
  List<String> options = [];
  String? defaultJson; // raw JSON text, mirroring Go's json.RawMessage
  bool required = false;

  Map<String, dynamic> toJson() => {
        'key': key,
        if (label.isNotEmpty) 'label': label,
        if (kind.isNotEmpty) 'kind': kind,
        if (options.isNotEmpty) 'options': options,
        if (defaultJson != null) 'default': jsonDecode(defaultJson!),
        if (required) 'required': required,
      };
}

class WireExtensionForm {
  String title = '';
  String message = '';
  List<WireExtensionFormField> fields = [];

  Map<String, dynamic> toJson() => {
        if (title.isNotEmpty) 'title': title,
        if (message.isNotEmpty) 'message': message,
        'fields': fields.map((f) => f.toJson()).toList(),
      };
}

class WireExtensionNotification {
  String title = '';
  String body = '';
  String severity = '';

  Map<String, dynamic> toJson() => {
        'title': title,
        if (body.isNotEmpty) 'body': body,
        if (severity.isNotEmpty) 'severity': severity,
      };
}

WireExtensionSurface? toWireExtensionSurface(event.ExtensionSurfacePayload? p) {
  if (p == null) return null;
  final out = WireExtensionSurface()
    ..pluginId = p.pluginId
    ..surfaceId = p.surfaceId
    ..sessionId = p.sessionId
    ..generation = p.generation
    ..kind = p.kind;
  final s = p.status;
  if (s != null) {
    out.status = WireExtensionStatus()
      ..label = s.label
      ..detail = s.detail
      ..severity = s.severity
      ..progress = s.progress;
  }
  final c = p.card;
  if (c != null) {
    final card = WireExtensionCard()
      ..title = c.title
      ..markdown = c.markdown
      ..text = c.text
      ..progress = c.progress;
    if (c.fields.isNotEmpty) {
      card.fields = c.fields
          .map((f) => WireExtensionKeyValue()
            ..key = f.key
            ..value = f.value)
          .toList();
    }
    if (c.actions.isNotEmpty) {
      card.actions = c.actions
          .map((a) => WireExtensionActionRef()
            ..actionId = a.actionId
            ..label = a.label)
          .toList();
    }
    out.card = card;
  }
  final f = p.form;
  if (f != null) {
    final form = WireExtensionForm()
      ..title = f.title
      ..message = f.message;
    if (f.fields.isNotEmpty) {
      form.fields = [];
      for (final field in f.fields) {
        final wireField = WireExtensionFormField()
          ..key = field.key
          ..label = field.label
          ..kind = field.kind
          ..options = List.of(field.options)
          ..required = field.required;
        if (field.$default != null) {
          // The value arrived as protocol-validated JSON; mirror Go's
          // marshal-or-drop-default behavior.
          try {
            wireField.defaultJson = jsonEncode(field.$default);
          } catch (_) {
            // pathological in-memory value: drop the default
          }
        }
        form.fields.add(wireField);
      }
    }
    out.form = form;
  }
  final n = p.notification;
  if (n != null) {
    out.notification = WireExtensionNotification()
      ..title = n.title
      ..body = n.body
      ..severity = n.severity;
  }
  return out;
}

// ═══════ Approval wire ═══════

class WireApproval {
  String id = '';
  String tool = '';
  String subject = '';
  String reason = '';
  bool fresh = false;
  String kind = '';
  WireRecoveryApproval? recovery;
  WireWriteAccessApproval? writeAccess;

  Map<String, dynamic> toJson() => {
        'id': id,
        'tool': tool,
        'subject': subject,
        if (reason.isNotEmpty) 'reason': reason,
        if (fresh) 'fresh': fresh,
        if (kind.isNotEmpty) 'kind': kind,
        if (recovery != null) 'recovery': recovery!.toJson(),
        if (writeAccess != null) 'write_access': writeAccess!.toJson(),
      };
}

class WireWriteAccessApproval {
  List<String> directories = [];
  List<String> displayDirectories = [];
  String justification = '';
  bool broadHomeAccess = false;
  bool ordinaryPermissionNeeded = false;
  bool persistAllowed = false;

  Map<String, dynamic> toJson() => {
        'directories': directories,
        'display_directories': displayDirectories,
        if (justification.isNotEmpty) 'justification': justification,
        if (broadHomeAccess) 'broad_home_access': broadHomeAccess,
        if (ordinaryPermissionNeeded)
          'ordinary_permission_needed': ordinaryPermissionNeeded,
        if (persistAllowed) 'persist_allowed': persistAllowed,
      };
}

class WireRecoveryApproval {
  String sourceAgent = '';
  String failedTool = '';
  String failedSummary = '';
  String diagnosis = '';
  String nextTool = '';
  String nextAction = '';
  String changeKind = '';
  String changeRationale = '';
  String reviewRationale = '';
  String planBefore = '';
  String planAfter = '';
  bool canGrantTask = false;
  String taskGrantScope = '';

  Map<String, dynamic> toJson() => {
        if (sourceAgent.isNotEmpty) 'source_agent': sourceAgent,
        if (failedTool.isNotEmpty) 'failed_tool': failedTool,
        if (failedSummary.isNotEmpty) 'failed_summary': failedSummary,
        if (diagnosis.isNotEmpty) 'diagnosis': diagnosis,
        if (nextTool.isNotEmpty) 'next_tool': nextTool,
        if (nextAction.isNotEmpty) 'next_action': nextAction,
        if (changeKind.isNotEmpty) 'change_kind': changeKind,
        if (changeRationale.isNotEmpty) 'change_rationale': changeRationale,
        if (reviewRationale.isNotEmpty) 'review_rationale': reviewRationale,
        if (planBefore.isNotEmpty) 'plan_before': planBefore,
        if (planAfter.isNotEmpty) 'plan_after': planAfter,
        if (canGrantTask) 'can_grant_task': canGrantTask,
        if (taskGrantScope.isNotEmpty) 'task_grant_scope': taskGrantScope,
      };
}

WireApproval? _toWireApproval(event.Approval a) {
  final w = WireApproval()
    ..id = a.id
    ..tool = a.tool
    ..subject = a.subject
    ..reason = a.reason
    ..fresh = a.fresh
    ..kind = a.kind;
  final wa = event.normalizeWriteAccessApproval(a.writeAccess);
  if (wa != null) {
    w.writeAccess = WireWriteAccessApproval()
      ..directories = List.of(wa.directories)
      ..displayDirectories = List.of(wa.displayDirectories)
      ..justification = wa.justification
      ..broadHomeAccess = wa.broadHomeAccess
      ..ordinaryPermissionNeeded = wa.ordinaryPermissionNeeded
      ..persistAllowed = wa.persistAllowed;
  }
  final r = a.recovery;
  if (r != null) {
    w.recovery = WireRecoveryApproval()
      ..sourceAgent = r.sourceAgent
      ..failedTool = r.failedTool
      ..failedSummary = r.failedSummary
      ..diagnosis = r.diagnosis
      ..nextTool = r.nextTool
      ..nextAction = r.nextAction
      ..changeKind = r.changeKind
      ..changeRationale = r.changeRationale
      ..reviewRationale = r.reviewRationale
      ..planBefore = r.planBefore
      ..planAfter = r.planAfter
      ..canGrantTask = r.canGrantTask
      ..taskGrantScope = r.taskGrantScope;
  }
  return w;
}

// ═══════ Completion receipt wire ═══════

class WireCompletionReceipt {
  String verdict = '';
  List<WireReceiptChange> changes = [];
  List<WireReceiptVerification> verifications = [];
  List<WireReceiptGap> gaps = [];
  List<String> risks = [];

  Map<String, dynamic> toJson() => {
        'verdict': verdict,
        if (changes.isNotEmpty)
          'changes': changes.map((c) => c.toJson()).toList(),
        if (verifications.isNotEmpty)
          'verifications': verifications.map((v) => v.toJson()).toList(),
        if (gaps.isNotEmpty) 'gaps': gaps.map((g) => g.toJson()).toList(),
        if (risks.isNotEmpty) 'risks': risks,
      };
}

class WireReceiptChange {
  String path = '';
  bool reviewed = false;

  Map<String, dynamic> toJson() => {'path': path, 'reviewed': reviewed};
}

class WireReceiptVerification {
  String command = '';
  bool passed = false;
  bool stale = false;

  Map<String, dynamic> toJson() => {
        'command': command,
        'passed': passed,
        if (stale) 'stale': stale,
      };
}

class WireReceiptGap {
  String kind = '';
  String detail = '';

  Map<String, dynamic> toJson() => {
        'kind': kind,
        if (detail.isNotEmpty) 'detail': detail,
      };
}

WireCompletionReceipt? _completionReceiptWire(event.CompletionReceipt? r) {
  if (r == null) return null;
  final out = WireCompletionReceipt()
    ..verdict = r.verdict
    ..risks = List.of(r.risks);
  for (final c in r.changes) {
    out.changes.add(WireReceiptChange()
      ..path = c.path
      ..reviewed = c.reviewed);
  }
  for (final v in r.verifications) {
    out.verifications.add(WireReceiptVerification()
      ..command = v.command
      ..passed = v.passed
      ..stale = v.stale);
  }
  for (final g in r.gaps) {
    out.gaps.add(WireReceiptGap()
      ..kind = g.kind
      ..detail = g.detail);
  }
  return out;
}

// ═══════ CostQuote JSON (wire subset) ═══════

Map<String, dynamic> _costQuoteToJson(billing.CostQuote q) {
  return {
    'original': _moneyToJson(q.original),
    if (q.originalTotals.isNotEmpty) 'originalTotals': q.originalTotals,
    'valuations': q.valuations.map((k, v) => MapEntry(k, _valuationToJson(v))),
    if (q.selected != null) 'selected': _moneyToJson(q.selected!),
    if (q.billingMode.isNotEmpty) 'billingMode': q.billingMode,
    'estimated': q.estimated,
    'costComplete': q.costComplete,
    'displayComplete': q.displayComplete,
    'complete': q.complete,
    if (q.displayStatus.isNotEmpty) 'displayStatus': q.displayStatus,
    if (q.aggregateMode.isNotEmpty) 'aggregateMode': q.aggregateMode,
    if (q.modelRef.isNotEmpty) 'modelRef': q.modelRef,
    if (q.usageSource.isNotEmpty) 'usageSource': q.usageSource,
    if (q.pricingFingerprint.isNotEmpty)
      'pricingFingerprint': q.pricingFingerprint,
    if (q.rateDate.isNotEmpty) 'rateDate': q.rateDate,
    if (q.incompleteReason.isNotEmpty) 'incompleteReason': q.incompleteReason,
    if (q.legacyEstimate) 'legacyEstimate': q.legacyEstimate,
    if (q.catalogSource.isNotEmpty) 'catalogSource': q.catalogSource,
  };
}

Map<String, dynamic> _moneyToJson(billing.Money m) => {
      'value': m.value,
      'currency': m.currency,
    };

Map<String, dynamic> _valuationToJson(billing.Valuation v) => {
      'money': _moneyToJson(v.money),
      'basis': v.basis,
      if (v.source.isNotEmpty) 'source': v.source,
      if (v.asOf.isNotEmpty) 'asOf': v.asOf,
      if (v.stale) 'stale': v.stale,
    };
