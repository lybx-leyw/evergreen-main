/// Port of reasonix/internal/event.
///
/// This library mirrors the Go package: all event kinds, payloads, sink
/// interfaces, and helper emitters live here. Dependent types from provider,
/// evidence, and billing are imported as minimal stubs; they will be expanded
/// when those packages are fully ported.
library;

import 'dart:async';
import 'dart:collection';

import '../nilutil/nil.dart' as nilutil;
import '../provider/usage.dart' as provider;
import '../provider/pricing.dart' as provider;
import '../provider/memory_citation.dart' as provider;
import '../provider/decision_receipt.dart' as provider;
import '../evidence/readiness_audit.dart' as evidence;
import '../evidence/outcome_sample.dart' as evidence;
import '../evidence/delegation_audit.dart' as evidence;
import '../billing/cost_quote.dart' as billing;

part 'approval.dart';
part 'receipt.dart';
part 'run_budget.dart';
part 'subagent_progress.dart';
part 'workspace_mutation.dart';
part 'fanout.dart';
part 'coalesce.dart';
part 'costquote_sink.dart';
part 'audit_forwarder.dart';
part 'sync.dart';

// ═══════ Kind ═══════

enum Kind {
  turnStarted,
  reasoning,
  text,
  message,
  toolDispatch,
  toolResult,
  usage,
  notice,
  phase,
  approvalRequest,
  askRequest,
  turnDone,
  compactionStarted,
  compactionDone,
  toolProgress,
  mcpSurfaceReady,
  retrying,
  steer,
  guardianAssessment,
  extensionSurface,
  extensionStatus,
  streamAttempt,
  contextMaintenanceEvent,
  workspaceChanged,
  turnPhase,
  completionSummary,
  toolResultPreview,
}

// ═══════ Supporting enums / structs ═══════

enum Level { info, warn }

enum NoticeAudience { $default, operator }

/// Wire value of a [NoticeAudience]: the empty string is the backward-
/// compatible default (ordinary delivery); "operator" marks local runtime
/// maintenance that must not be forwarded as end-user chat messages.
String noticeAudienceValue(NoticeAudience a) {
  switch (a) {
    case NoticeAudience.operator:
      return 'operator';
    case NoticeAudience.$default:
      return '';
  }
}

NoticeAudience noticeAudienceFromWire(String value) {
  if (value == 'operator') return NoticeAudience.operator;
  return NoticeAudience.$default;
}

enum TurnPhaseName { working, checking, verifying, reviewing }

String turnPhaseNameValue(TurnPhaseName p) => p.name;

TurnPhaseName turnPhaseNameFromWire(String value) {
  for (final p in TurnPhaseName.values) {
    if (p.name == value) return p;
  }
  return TurnPhaseName.working;
}

enum RetryScope { headers, stream }

String retryScopeValue(RetryScope s) => s.name;

enum StreamAttemptAction { begin, discard, commit }

String streamAttemptActionValue(StreamAttemptAction a) => a.name;

class Profile {
  final String model;
  final String effort;

  const Profile({this.model = '', this.effort = ''});
}

class Tool {
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
  Profile? profile;
  ShellExecution? execution;
  bool workspaceMutation = false;
  List<String> workspacePaths = [];
  bool workspaceAllPaths = false;
}

class ShellExecution {
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
}

class AskOption {
  final String label;
  final String description;

  const AskOption({required this.label, this.description = ''});
}

class AskQuestion {
  final String id;
  final String header;
  final String prompt;
  final List<AskOption> options;
  final bool multi;

  const AskQuestion({
    required this.id,
    this.header = '',
    required this.prompt,
    this.options = const [],
    this.multi = false,
  });
}

class Ask {
  final String id;
  final List<AskQuestion> questions;

  const Ask({required this.id, required this.questions});
}

/// The user's reply to one [AskQuestion]: the chosen option label(s)
/// (a free-typed answer is carried as a single selected entry).
class AskAnswer {
  final String questionId;
  final List<String> selected;

  const AskAnswer({required this.questionId, this.selected = const []});
}

class Compaction {
  String trigger = '';
  int messages = 0;
  String summary = '';
  String archive = '';
}

class ContextMaintenance {
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
}

class GuardianResult {
  String id = '';
  String tool = '';
  String subject = '';
  String outcome = '';
  String riskLevel = '';
  String userAuthorization = '';
  String rationale = '';
  int durationMs = 0;
  provider.Usage? usage;
  provider.Pricing? pricing;
}

class CacheDiagnostics {
  String prefixHash = '';
  bool prefixChanged = false;
  List<String> prefixChangeReasons = [];
  String systemHash = '';
  String toolsHash = '';
  int logRewriteVersion = 0;
  int toolSchemaTokens = 0;
  int cacheMissTokens = 0;
  int cacheHitTokens = 0;
}

class FinalReadiness {
  int attempts = 0;
  List<String> missing = [];
}

class WorkspaceRevision {
  int content = 0;
  int tree = 0;
  int workingTree = 0;
  int gitMeta = 0;
  int session = 0;
}

class WorkspacePathChange {
  String path = '';
  String oldPath = '';
  String op = '';
}

class WorkspaceChangedPayload {
  WorkspaceRevision revisions = WorkspaceRevision();
  List<WorkspacePathChange> changes = [];
  bool allPaths = false;
  String source = '';
  WorkspaceWatchState watchState = WorkspaceWatchState.active;
}

enum WorkspaceWatchState { active, degraded, unavailable }

String workspaceWatchStateValue(WorkspaceWatchState s) => s.name;

class CompletionSummaryInfo {
  String preset = '';
  String verdict = '';
  int mutations = 0;
  int checksPassed = 0;
  int checksFailed = 0;
  int checksSuppressed = 0;
  String review = '';
  List<String> gapKinds = [];
  bool constraintDegraded = false;
}

class StreamAttemptInfo {
  String id = '';
  StreamAttemptAction action = StreamAttemptAction.begin;
  int attempt = 0;
  int max = 0;
  String reason = '';
}

class MemoryRecallAudit {
  List<MemoryRecallHit> hits = [];
  List<MemoryRecallHit> shadow = [];
  int usedChars = 0;
  int omitted = 0;
  String suppressed = '';
}

class MemoryRecallHit {
  String id = '';
  int revision = 0;
  String scope = '';
  String type = '';
  String freshness = '';
  double score = 0.0;
}

class DelegationAdmissionAudit {
  String tool = '';
  String verdict = '';
  String reason = '';
  String intent = '';
}

class ContractShadowAudit {
  String intent = '';
  int requirements = 0;
  int requirementsSatisfied = 0;
  int checks = 0;
  int checksSatisfied = 0;
  int epoch = 0;
  String verdict = '';
  bool complete = false;
  bool readyToFinalize = false;
}

class CompletionReportAudit {
  String verdict = '';
  String risk = '';
  int criteria = 0;
  int criteriaSatisfied = 0;
  int changes = 0;
  int changesUnreviewed = 0;
  int verifications = 0;
  int verificationsFailed = 0;
  int verificationsStale = 0;
  int gaps = 0;
  List<String> gapKinds = [];
  int claimsVerified = 0;
  int claimsUnbacked = 0;
}

enum ProtocolRecoveryKind {
  missingReasoningDetected,
  missingReasoningRetryAttempted,
  missingReasoningRetryRecovered,
  missingReasoningRetryReplaced,
  missingReasoningRetrySuppressed,
  missingReasoningFallback,
  reasoningOverflowDetected,
  clientToolRejected,
  serverSearchSalvaged,
  historyRepaired,
}

class ProtocolRecoveryAudit {
  final ProtocolRecoveryKind kind;

  ProtocolRecoveryAudit({required this.kind});
}

/// Stable wire value of a [ProtocolRecoveryKind], matching the Go constants.
String protocolRecoveryKindValue(ProtocolRecoveryKind k) {
  switch (k) {
    case ProtocolRecoveryKind.missingReasoningDetected:
      return 'missing_reasoning_detected';
    case ProtocolRecoveryKind.missingReasoningRetryAttempted:
      return 'missing_reasoning_retry_attempted';
    case ProtocolRecoveryKind.missingReasoningRetryRecovered:
      return 'missing_reasoning_retry_recovered';
    case ProtocolRecoveryKind.missingReasoningRetryReplaced:
      return 'missing_reasoning_retry_replaced_response';
    case ProtocolRecoveryKind.missingReasoningRetrySuppressed:
      return 'missing_reasoning_retry_suppressed';
    case ProtocolRecoveryKind.missingReasoningFallback:
      return 'missing_reasoning_fallback_used';
    case ProtocolRecoveryKind.reasoningOverflowDetected:
      return 'reasoning_overflow_detected';
    case ProtocolRecoveryKind.clientToolRejected:
      return 'client_tool_rejected_unreplayable_reasoning';
    case ProtocolRecoveryKind.serverSearchSalvaged:
      return 'server_search_history_salvaged';
    case ProtocolRecoveryKind.historyRepaired:
      return 'unreplayable_history_repaired';
  }
}

// ═══════ Event ═══════

class Event {
  Kind kind = Kind.turnStarted;
  String text = '';
  String modelRef = '';
  String detail = '';
  String code = '';
  String reasoning = '';
  List<provider.MemoryCitation> memoryCitations = [];
  Tool tool = Tool();
  provider.Usage? usage;
  provider.Pricing? pricing;
  billing.CostQuote? costQuote;
  String source = '';
  String usageSource = '';
  CacheDiagnostics? cacheDiagnostics;
  int sessionHit = 0;
  int sessionMiss = 0;
  Level level = Level.info;
  NoticeAudience audience = NoticeAudience.$default;
  Approval approval = Approval();
  Ask ask = Ask(id: '', questions: []);
  Compaction compaction = Compaction();
  ContextMaintenance? maintenance;
  GuardianResult guardian = GuardianResult();
  provider.DecisionReceipt? decisionReceipt;
  ExtensionSurfacePayload? extension;
  Object? err;
  bool cancelled = false;
  String outcome = '';
  FinalReadiness? readiness;
  CompletionReceipt? receipt;
  int? checkpointTurn;
  int retryAttempt = 0;
  int retryMax = 0;
  RetryScope? retryScope;
  StreamAttemptInfo streamAttempt = StreamAttemptInfo();
  String itemId = '';
  WorkspaceChangedPayload? workspace;
  TurnPhaseName phaseName = TurnPhaseName.working;
  CompletionSummaryInfo? completion;
}

// ═══════ Extension surfaces ═══════

class ExtensionSurfacePayload {
  String pluginId = '';
  String surfaceId = '';
  String sessionId = '';
  int generation = 0;
  String kind = '';
  ExtensionStatusView? status;
  ExtensionCardView? card;
  ExtensionFormView? form;
  ExtensionNotificationView? notification;
}

class ExtensionStatusView {
  String label = '';
  String detail = '';
  String severity = '';
  double? progress;
}

class ExtensionKeyValue {
  String key = '';
  String value = '';
}

class ExtensionActionRef {
  String actionId = '';
  String label = '';
}

class ExtensionCardView {
  String title = '';
  String markdown = '';
  String text = '';
  List<ExtensionKeyValue> fields = [];
  double? progress;
  List<ExtensionActionRef> actions = [];
}

class ExtensionFormField {
  String key = '';
  String label = '';
  String kind = '';
  List<String> options = [];
  Object? $default;
  bool required = false;
}

class ExtensionFormView {
  String title = '';
  String message = '';
  List<ExtensionFormField> fields = [];
}

class ExtensionNotificationView {
  String title = '';
  String body = '';
  String severity = '';
}

// ═══════ Notice codes ═══════

const noticeCodeFinalReadiness = 'final_readiness';
const noticeCodeEmptyFinal = 'empty_final';
const noticeCodeExecutorHandoff = 'executor_handoff';
const noticeCodeToolBudget = 'tool_budget';
const noticeCodePromptQueued = 'prompt_queued';
const noticeCodeLoopGuard = 'loop_guard';
const noticeCodeProgressGuard = 'progress_guard';
const noticeCodeEvidenceNudge = 'evidence_nudge';
const noticeCodeReasoningGovernor = 'reasoning_governor';
const noticeCodeWorkspaceLease = 'workspace_lease';
const noticeCodeCancelledTurn = 'cancelled_turn_display';
const noticeCodeUnappliedSteer = 'unapplied_steer';
const noticeCodeSessionRecoveryForked = 'session_recovery_forked';
const noticeCodeSessionRecoveryAdopted = 'session_recovery_adopted';
const noticeCodeSessionRecoveryAdoptedCovered =
    'session_recovery_adopted_covered';
const noticeCodeSessionRecoveryDepthCap = 'session_recovery_depth_cap';
const noticeCodeSessionShutdownRecoveryForked =
    'session_shutdown_recovery_forked';
const noticeCodeDecisionReceipt = 'decision_receipt';
const noticeCodeContextEditingFallback = 'context_editing_fallback';

const usageSourceExecutor = 'executor';
const usageSourcePlanner = 'planner';
const usageSourceSubagent = 'subagent';
const usageSourceCompaction = 'compaction';
const usageSourceClassifier = 'classifier';
const usageSourceTitle = 'title';
const usageSourceCapabilityRouter = 'capability-router';
const usageSourceRecoveryReviewer = 'recovery-reviewer';
const usageSourceGoalEvaluator = 'goal-evaluator';

const turnOutcomeFinalReadiness = 'final_readiness';
const turnOutcomeRecoveryPaused = 'recovery_paused';

const extensionSurfaceStatus = 'status';
const extensionSurfaceCard = 'card';
const extensionSurfaceForm = 'form';
const extensionSurfaceNotification = 'notification';
const extensionSurfaceRequest = 'request';

// ═══════ Sink ═══════

abstract class Sink {
  void emit(Event e);
}

/// Adapts a plain function to a [Sink]. A null function is a no-op,
/// mirroring Go's `FuncSink` nil check.
class FuncSink implements Sink {
  final void Function(Event)? _fn;

  FuncSink([void Function(Event)? fn]) : _fn = fn;

  @override
  void emit(Event e) {
    _fn?.call(e);
  }
}

class DiscardSink implements Sink {
  @override
  void emit(Event e) {}
}

final Sink discard = DiscardSink();

// ═══════ Optional sink capabilities ═══════

abstract class ReadinessAuditSink {
  void recordReadinessAudit(evidence.ReadinessAudit a);
}

abstract class TurnCompletionSink {
  void recordTurnCompletion();
}

abstract class ProtocolRecoveryAuditSink {
  void recordProtocolRecovery(ProtocolRecoveryAudit a);
}

abstract class ContractShadowAuditSink {
  void recordContractShadow(ContractShadowAudit a);
}

abstract class CompletionReportAuditSink {
  void recordCompletionReport(CompletionReportAudit a);
}

abstract class OutcomeProgressSink {
  void recordOutcomeProgress(evidence.OutcomeSample sample);
}

abstract class MemoryRecallSink {
  void recordMemoryRecall(MemoryRecallAudit a);
}

abstract class DelegationAdmissionSink {
  void recordDelegationAdmission(DelegationAdmissionAudit a);
}

/// Optional sink capability for shadow delegation audit receipts
/// (evidence.DelegationAudit).
abstract class DelegationAuditSink {
  void recordDelegationAudit(evidence.DelegationAudit a);
}

void recordDelegationAudit(Sink s, evidence.DelegationAudit a) {
  if (nilutil.isNil(s)) return;
  if (s is DelegationAuditSink) s.recordDelegationAudit(a);
}

abstract class RunBudgetSink {
  void recordRunBudget(RunBudgetSample sample);
}

// ═══════ Forwarder helpers ═══════

void recordTurnCompletion(Sink s) {
  if (nilutil.isNil(s)) return;
  if (s is TurnCompletionSink) s.recordTurnCompletion();
}

void recordReadinessAudit(Sink s, evidence.ReadinessAudit a) {
  if (nilutil.isNil(s)) return;
  if (s is ReadinessAuditSink) s.recordReadinessAudit(a);
}

void recordProtocolRecovery(Sink s, ProtocolRecoveryAudit a) {
  if (nilutil.isNil(s)) return;
  if (s is ProtocolRecoveryAuditSink) s.recordProtocolRecovery(a);
}

void recordContractShadow(Sink s, ContractShadowAudit a) {
  if (nilutil.isNil(s)) return;
  if (s is ContractShadowAuditSink) s.recordContractShadow(a);
}

void recordCompletionReport(Sink s, CompletionReportAudit a) {
  if (nilutil.isNil(s)) return;
  if (s is CompletionReportAuditSink) s.recordCompletionReport(a);
}

void recordOutcomeProgress(Sink s, evidence.OutcomeSample sample) {
  if (nilutil.isNil(s)) return;
  if (s is OutcomeProgressSink) s.recordOutcomeProgress(sample);
}

void recordMemoryRecall(Sink s, MemoryRecallAudit a) {
  if (nilutil.isNil(s)) return;
  if (s is MemoryRecallSink) s.recordMemoryRecall(a);
}

void recordDelegationAdmission(Sink s, DelegationAdmissionAudit a) {
  if (nilutil.isNil(s)) return;
  if (s is DelegationAdmissionSink) s.recordDelegationAdmission(a);
}
