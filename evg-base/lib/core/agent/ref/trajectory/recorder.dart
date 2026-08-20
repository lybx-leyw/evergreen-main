/// Port of reasonix/internal/trajectory/recorder.dart.
///
/// Appends a run's typed event stream to a JSONL file so the sequence,
/// timing, and decisions can be replayed and analyzed offline. Records reuse
/// the eventwire JSON contract and include content (prompts, tool arguments,
/// reasoning) — the file is as sensitive as a session transcript.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../event/event.dart' as event;
import '../eventwire/wire.dart' as eventwire;
import '../evidence/delegation_audit.dart' as evidence_delegation;
import '../evidence/outcome_sample.dart' as evidence;
import '../evidence/readiness_audit.dart' as evidence_readiness;

/// Identifies the record layout; bump on breaking changes.
const int schemaVersion = 1;

/// One observed occurrence. Exactly one payload field is set; [seq] orders
/// them and [ts] is the unix-millisecond observation time at the recorder.
class Record {
  int schemaVersion = 0;
  int seq = 0;
  int ts = 0;
  eventwire.WireEvent? event;
  ReadinessAudit? readinessAudit;
  String protocolRecovery = '';
  bool turnCompletion = false;
  ContractShadowAudit? contractShadow;
  CompletionReport? completionReport;
  OutcomeProgress? outcomeProgress;
  DelegationAdmission? delegationAdmission;
  MemoryRecall? memoryRecall;

  Record();

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'schema_version': schemaVersion,
      'seq': seq,
      'ts': ts,
    };
    void put(String key, Object? v) {
      if (v != null && v != '' && v != false && v != const []) {
        m[key] = v;
      }
    }

    put('event', event?.toJson());
    put('readiness_audit', readinessAudit?.toJson());
    put('protocol_recovery', protocolRecovery);
    put('turn_completion', turnCompletion);
    put('contract_shadow', contractShadow?.toJson());
    put('completion_report', completionReport?.toJson());
    put('outcome_progress', outcomeProgress?.toJson());
    put('delegation_admission', delegationAdmission?.toJson());
    put('memory_recall', memoryRecall?.toJson());
    return m;
  }

  factory Record.fromJson(Map<String, dynamic> m) {
    final r = Record()
      ..schemaVersion = m['schema_version'] as int? ?? 0
      ..seq = m['seq'] as int? ?? 0
      ..ts = m['ts'] as int? ?? 0;
    final ev = m['event'];
    if (ev is Map<String, dynamic>) r.event = _wireEventFromJson(ev);
    final ra = m['readiness_audit'];
    if (ra is Map<String, dynamic>) {
      r.readinessAudit = ReadinessAudit.fromJson(ra);
    }
    r.protocolRecovery = m['protocol_recovery'] as String? ?? '';
    r.turnCompletion = m['turn_completion'] as bool? ?? false;
    final cs = m['contract_shadow'];
    if (cs is Map<String, dynamic>)
      r.contractShadow = ContractShadowAudit.fromJson(cs);
    final cr = m['completion_report'];
    if (cr is Map<String, dynamic>)
      r.completionReport = CompletionReport.fromJson(cr);
    final op = m['outcome_progress'];
    if (op is Map<String, dynamic>)
      r.outcomeProgress = OutcomeProgress.fromJson(op);
    final da = m['delegation_admission'];
    if (da is Map<String, dynamic>)
      r.delegationAdmission = DelegationAdmission.fromJson(da);
    final mr = m['memory_recall'];
    if (mr is Map<String, dynamic>) r.memoryRecall = MemoryRecall.fromJson(mr);
    return r;
  }
}

/// Mirrors event.MemoryRecallAudit with stable snake_case keys.
class MemoryRecall {
  List<MemoryRecallHit> hits = [];
  int usedChars = 0;
  int omitted = 0;
  String suppressed = '';
  List<MemoryRecallHit> shadowHits = [];

  Map<String, dynamic> toJson() => {
        if (hits.isNotEmpty) 'hits': hits.map((h) => h.toJson()).toList(),
        if (usedChars != 0) 'used_chars': usedChars,
        if (omitted != 0) 'omitted': omitted,
        if (suppressed.isNotEmpty) 'suppressed': suppressed,
        if (shadowHits.isNotEmpty)
          'shadow_hits': shadowHits.map((h) => h.toJson()).toList(),
      };

  factory MemoryRecall.fromJson(Map<String, dynamic> m) {
    final out = MemoryRecall()
      ..usedChars = m['used_chars'] as int? ?? 0
      ..omitted = m['omitted'] as int? ?? 0
      ..suppressed = m['suppressed'] as String? ?? '';
    final hits = m['hits'];
    if (hits is List) {
      out.hits = hits
          .whereType<Map<String, dynamic>>()
          .map(MemoryRecallHit.fromJson)
          .toList();
    }
    final shadow = m['shadow_hits'];
    if (shadow is List) {
      out.shadowHits = shadow
          .whereType<Map<String, dynamic>>()
          .map(MemoryRecallHit.fromJson)
          .toList();
    }
    return out;
  }
}

/// One recalled fact's content-free fingerprint.
class MemoryRecallHit {
  String id = '';
  int revision = 0;
  String scope = '';
  String type = '';
  String freshness = '';
  double score = 0.0;

  Map<String, dynamic> toJson() => {
        'id': id,
        if (revision != 0) 'revision': revision,
        if (scope.isNotEmpty) 'scope': scope,
        if (type.isNotEmpty) 'type': type,
        if (freshness.isNotEmpty) 'freshness': freshness,
        if (score != 0) 'score': score,
      };

  factory MemoryRecallHit.fromJson(Map<String, dynamic> m) => MemoryRecallHit()
    ..id = m['id'] as String? ?? ''
    ..revision = m['revision'] as int? ?? 0
    ..scope = m['scope'] as String? ?? ''
    ..type = m['type'] as String? ?? ''
    ..freshness = m['freshness'] as String? ?? ''
    ..score = (m['score'] as num?)?.toDouble() ?? 0.0;
}

/// Mirrors event.DelegationAdmissionAudit with stable keys.
class DelegationAdmission {
  String tool = '';
  String verdict = '';
  String reason = '';
  String intent = '';

  Map<String, dynamic> toJson() => {
        'tool': tool,
        'verdict': verdict,
        if (reason.isNotEmpty) 'reason': reason,
        if (intent.isNotEmpty) 'intent': intent,
      };

  factory DelegationAdmission.fromJson(Map<String, dynamic> m) =>
      DelegationAdmission()
        ..tool = m['tool'] as String? ?? ''
        ..verdict = m['verdict'] as String? ?? ''
        ..reason = m['reason'] as String? ?? ''
        ..intent = m['intent'] as String? ?? '';
}

/// Mirrors evidence.OutcomeSample with stable snake_case keys.
class OutcomeProgress {
  int round = 0;
  int exploration = 0;
  int verification = 0;
  int objective = 0;
  int regression = 0;
  int churn = 0;
  int legacyGain = 0;
  int discriminating = 0;
  int debtAge = 0;
  int blindMutations = 0;
  bool ebmEligible = false;
  bool ebmFired = false;
  bool localExecSeen = false;
  bool governorEligible = false;
  bool governorEngaged = false;

  Map<String, dynamic> toJson() => {
        'round': round,
        if (exploration != 0) 'exploration': exploration,
        if (verification != 0) 'verification': verification,
        if (objective != 0) 'objective': objective,
        if (regression != 0) 'regression': regression,
        if (churn != 0) 'churn': churn,
        if (legacyGain != 0) 'legacy_gain': legacyGain,
        if (discriminating != 0) 'discriminating': discriminating,
        if (debtAge != 0) 'debt_age': debtAge,
        if (blindMutations != 0) 'blind_mutations': blindMutations,
        if (ebmEligible) 'ebm_eligible': ebmEligible,
        if (ebmFired) 'ebm_fired': ebmFired,
        if (localExecSeen) 'local_exec_seen': localExecSeen,
        if (governorEligible) 'governor_eligible': governorEligible,
        if (governorEngaged) 'governor_engaged': governorEngaged,
      };

  factory OutcomeProgress.fromJson(Map<String, dynamic> m) => OutcomeProgress()
    ..round = m['round'] as int? ?? 0
    ..exploration = m['exploration'] as int? ?? 0
    ..verification = m['verification'] as int? ?? 0
    ..objective = m['objective'] as int? ?? 0
    ..regression = m['regression'] as int? ?? 0
    ..churn = m['churn'] as int? ?? 0
    ..legacyGain = m['legacy_gain'] as int? ?? 0
    ..discriminating = m['discriminating'] as int? ?? 0
    ..debtAge = m['debt_age'] as int? ?? 0
    ..blindMutations = m['blind_mutations'] as int? ?? 0
    ..ebmEligible = m['ebm_eligible'] as bool? ?? false
    ..ebmFired = m['ebm_fired'] as bool? ?? false
    ..localExecSeen = m['local_exec_seen'] as bool? ?? false
    ..governorEligible = m['governor_eligible'] as bool? ?? false
    ..governorEngaged = m['governor_engaged'] as bool? ?? false;
}

/// Mirrors event.ContractShadowAudit with stable keys.
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

  Map<String, dynamic> toJson() => {
        'intent': intent,
        if (requirements != 0) 'requirements': requirements,
        if (requirementsSatisfied != 0)
          'requirements_satisfied': requirementsSatisfied,
        if (checks != 0) 'checks': checks,
        if (checksSatisfied != 0) 'checks_satisfied': checksSatisfied,
        if (epoch != 0) 'epoch': epoch,
        'verdict': verdict,
        if (complete) 'complete': complete,
        if (readyToFinalize) 'ready_to_finalize': readyToFinalize,
      };

  factory ContractShadowAudit.fromJson(Map<String, dynamic> m) =>
      ContractShadowAudit()
        ..intent = m['intent'] as String? ?? ''
        ..requirements = m['requirements'] as int? ?? 0
        ..requirementsSatisfied = m['requirements_satisfied'] as int? ?? 0
        ..checks = m['checks'] as int? ?? 0
        ..checksSatisfied = m['checks_satisfied'] as int? ?? 0
        ..epoch = m['epoch'] as int? ?? 0
        ..verdict = m['verdict'] as String? ?? ''
        ..complete = m['complete'] as bool? ?? false
        ..readyToFinalize = m['ready_to_finalize'] as bool? ?? false;
}

/// Mirrors event.CompletionReportAudit with stable keys.
class CompletionReport {
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

  Map<String, dynamic> toJson() => {
        'verdict': verdict,
        if (risk.isNotEmpty) 'risk': risk,
        if (criteria != 0) 'criteria': criteria,
        if (criteriaSatisfied != 0) 'criteria_satisfied': criteriaSatisfied,
        if (changes != 0) 'changes': changes,
        if (changesUnreviewed != 0) 'changes_unreviewed': changesUnreviewed,
        if (verifications != 0) 'verifications': verifications,
        if (verificationsFailed != 0)
          'verifications_failed': verificationsFailed,
        if (verificationsStale != 0) 'verifications_stale': verificationsStale,
        if (gaps != 0) 'gaps': gaps,
        if (gapKinds.isNotEmpty) 'gap_kinds': gapKinds,
        if (claimsVerified != 0) 'claims_verified': claimsVerified,
        if (claimsUnbacked != 0) 'claims_unbacked': claimsUnbacked,
      };

  factory CompletionReport.fromJson(Map<String, dynamic> m) =>
      CompletionReport()
        ..verdict = m['verdict'] as String? ?? ''
        ..risk = m['risk'] as String? ?? ''
        ..criteria = m['criteria'] as int? ?? 0
        ..criteriaSatisfied = m['criteria_satisfied'] as int? ?? 0
        ..changes = m['changes'] as int? ?? 0
        ..changesUnreviewed = m['changes_unreviewed'] as int? ?? 0
        ..verifications = m['verifications'] as int? ?? 0
        ..verificationsFailed = m['verifications_failed'] as int? ?? 0
        ..verificationsStale = m['verifications_stale'] as int? ?? 0
        ..gaps = m['gaps'] as int? ?? 0
        ..gapKinds =
            (m['gap_kinds'] as List? ?? const []).whereType<String>().toList()
        ..claimsVerified = m['claims_verified'] as int? ?? 0
        ..claimsUnbacked = m['claims_unbacked'] as int? ?? 0;
}

/// Mirrors evidence.ReadinessAudit with stable snake_case keys.
class ReadinessAudit {
  String result = '';
  bool recovered = false;
  int missingProjectChecks = 0;
  int incompleteTodos = 0;
  int commandMismatchMissing = 0;
  int missingAcceptanceCriteria = 0;
  int missingVerification = 0;
  int missingReview = 0;
  int missingSignoff = 0;
  int missingActionEvidence = 0;
  int missingMutation = 0;
  int missingCapabilities = 0;

  Map<String, dynamic> toJson() => {
        'result': result,
        if (recovered) 'recovered': recovered,
        if (missingProjectChecks != 0)
          'missing_project_checks': missingProjectChecks,
        if (incompleteTodos != 0) 'incomplete_todos': incompleteTodos,
        if (commandMismatchMissing != 0)
          'command_mismatch_missing': commandMismatchMissing,
        if (missingAcceptanceCriteria != 0)
          'missing_acceptance_criteria': missingAcceptanceCriteria,
        if (missingVerification != 0)
          'missing_verification': missingVerification,
        if (missingReview != 0) 'missing_review': missingReview,
        if (missingSignoff != 0) 'missing_signoff': missingSignoff,
        if (missingActionEvidence != 0)
          'missing_action_evidence': missingActionEvidence,
        if (missingMutation != 0) 'missing_mutation': missingMutation,
        if (missingCapabilities != 0)
          'missing_capabilities': missingCapabilities,
      };

  factory ReadinessAudit.fromJson(Map<String, dynamic> m) => ReadinessAudit()
    ..result = m['result'] as String? ?? ''
    ..recovered = m['recovered'] as bool? ?? false
    ..missingProjectChecks = m['missing_project_checks'] as int? ?? 0
    ..incompleteTodos = m['incomplete_todos'] as int? ?? 0
    ..commandMismatchMissing = m['command_mismatch_missing'] as int? ?? 0
    ..missingAcceptanceCriteria = m['missing_acceptance_criteria'] as int? ?? 0
    ..missingVerification = m['missing_verification'] as int? ?? 0
    ..missingReview = m['missing_review'] as int? ?? 0
    ..missingSignoff = m['missing_signoff'] as int? ?? 0
    ..missingActionEvidence = m['missing_action_evidence'] as int? ?? 0
    ..missingMutation = m['missing_mutation'] as int? ?? 0
    ..missingCapabilities = m['missing_capabilities'] as int? ?? 0;
}

/// An event.Sink decorator: every event (and optional-capability audit) is
/// appended as one JSONL record, then forwarded to the inner sink. Recording
/// failures never block forwarding — the first error is kept and returned by
/// [close].
class Recorder
    implements
        event.Sink,
        event.ReadinessAuditSink,
        event.ProtocolRecoveryAuditSink,
        event.TurnCompletionSink,
        event.OutcomeProgressSink,
        event.ContractShadowAuditSink,
        event.CompletionReportAuditSink,
        event.MemoryRecallSink,
        event.DelegationAdmissionSink,
        event.DelegationAuditSink {
  final event.Sink? inner;
  final DateTime Function() _clock;
  final IOSink _sink;
  final String path;
  int _seq = 0;
  Object? _error;
  bool _closed = false;

  Recorder._(this.inner, this._sink, this.path, DateTime Function() clock)
      : _clock = clock;

  /// Opens (or truncates) [path] and returns a recorder forwarding to [inner].
  /// A null [clock] means [DateTime.now].
  static Future<Recorder> open(
    event.Sink? inner,
    String path, {
    DateTime Function()? clock,
  }) async {
    final parent = File(path).parent;
    if (!parent.existsSync()) {
      throw FileSystemException('trajectory: cannot create file', path);
    }
    final sink = File(path).openWrite(mode: FileMode.write);
    return Recorder._(inner, sink, path, clock ?? DateTime.now);
  }

  void _append(Record rec) {
    if (_closed || _error != null) return;
    _seq++;
    rec
      ..schemaVersion = schemaVersion
      ..seq = _seq
      ..ts = _clock().millisecondsSinceEpoch;
    try {
      _sink.write('${jsonEncode(rec.toJson())}\n');
      // Flush per record so a killed run still leaves every completed line.
      unawaited(_sink.flush().catchError((Object e) {
        _error ??= e;
      }));
    } catch (e) {
      _error ??= e;
    }
  }

  @override
  void emit(event.Event e) {
    _append(Record()..event = eventwire.toWire(e));
    inner?.emit(e);
  }

  /// Delegation receipts are forwarded without persisting; the trajectory
  /// schema stays unchanged (same as Go's RecordDelegationAudit).
  @override
  void recordDelegationAudit(evidence_delegation.DelegationAudit a) {
    if (inner != null) event.recordDelegationAudit(inner, a);
  }

  @override
  void recordDelegationAdmission(event.DelegationAdmissionAudit a) {
    _append(Record()
      ..delegationAdmission = DelegationAdmission()
      ..tool = a.tool
      ..verdict = a.verdict
      ..reason = a.reason
      ..intent = a.intent);
    if (inner != null) event.recordDelegationAdmission(inner, a);
  }

  @override
  void recordReadinessAudit(evidence_readiness.ReadinessAudit a) {
    _append(Record()
      ..readinessAudit = ReadinessAudit()
      ..result = a.result
      ..recovered = a.recovered
      ..missingProjectChecks = a.missingProjectChecks
      ..incompleteTodos = a.incompleteTodos
      ..commandMismatchMissing = a.commandMismatchMissing
      ..missingAcceptanceCriteria = a.missingAcceptanceCriteria
      ..missingVerification = a.missingVerification
      ..missingReview = a.missingReview
      ..missingSignoff = a.missingSignoff
      ..missingActionEvidence = a.missingActionEvidence
      ..missingMutation = a.missingMutation
      ..missingCapabilities = a.missingCapabilities);
    if (inner != null) event.recordReadinessAudit(inner, a);
  }

  @override
  void recordContractShadow(event.ContractShadowAudit a) {
    _append(Record()
      ..contractShadow = ContractShadowAudit()
      ..intent = a.intent
      ..requirements = a.requirements
      ..requirementsSatisfied = a.requirementsSatisfied
      ..checks = a.checks
      ..checksSatisfied = a.checksSatisfied
      ..epoch = a.epoch
      ..verdict = a.verdict
      ..complete = a.complete
      ..readyToFinalize = a.readyToFinalize);
    if (inner != null) event.recordContractShadow(inner, a);
  }

  @override
  void recordCompletionReport(event.CompletionReportAudit a) {
    _append(Record()
      ..completionReport = CompletionReport()
      ..verdict = a.verdict
      ..risk = a.risk
      ..criteria = a.criteria
      ..criteriaSatisfied = a.criteriaSatisfied
      ..changes = a.changes
      ..changesUnreviewed = a.changesUnreviewed
      ..verifications = a.verifications
      ..verificationsFailed = a.verificationsFailed
      ..verificationsStale = a.verificationsStale
      ..gaps = a.gaps
      ..gapKinds = List.of(a.gapKinds)
      ..claimsVerified = a.claimsVerified
      ..claimsUnbacked = a.claimsUnbacked);
    if (inner != null) event.recordCompletionReport(inner, a);
  }

  @override
  void recordOutcomeProgress(evidence.OutcomeSample sample) {
    _append(Record()
      ..outcomeProgress = OutcomeProgress()
      ..round = sample.round
      ..exploration = sample.exploration
      ..verification = sample.verification
      ..objective = sample.objective
      ..regression = sample.regression
      ..churn = sample.churn
      ..legacyGain = sample.legacyGain
      ..discriminating = sample.discriminating
      ..debtAge = sample.debtAge
      ..blindMutations = sample.blindMutations
      ..ebmEligible = sample.ebmEligible
      ..ebmFired = sample.ebmFired
      ..localExecSeen = sample.localExecSeen
      ..governorEligible = sample.governorEligible
      ..governorEngaged = sample.governorEngaged);
    if (inner != null) event.recordOutcomeProgress(inner, sample);
  }

  @override
  void recordMemoryRecall(event.MemoryRecallAudit a) {
    final rec = MemoryRecall()
      ..usedChars = a.usedChars
      ..omitted = a.omitted
      ..suppressed = a.suppressed;
    for (final hit in a.hits) {
      rec.hits.add(MemoryRecallHit()
        ..id = hit.id
        ..revision = hit.revision
        ..scope = hit.scope
        ..type = hit.type
        ..freshness = hit.freshness
        ..score = hit.score);
    }
    for (final hit in a.shadow) {
      rec.shadowHits.add(MemoryRecallHit()
        ..id = hit.id
        ..score = hit.score);
    }
    _append(Record()..memoryRecall = rec);
    if (inner != null) event.recordMemoryRecall(inner, a);
  }

  @override
  void recordProtocolRecovery(event.ProtocolRecoveryAudit a) {
    _append(
        Record()..protocolRecovery = event.protocolRecoveryKindValue(a.kind));
    if (inner != null) event.recordProtocolRecovery(inner, a);
  }

  @override
  void recordTurnCompletion() {
    _append(Record()..turnCompletion = true);
    if (inner != null) event.recordTurnCompletion(inner);
  }

  /// Flushes and closes the file, returning the first error seen. Events
  /// arriving after [close] (late background jobs) are forwarded but not
  /// recorded.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _sink.flush();
      await _sink.close();
    } catch (e) {
      _error ??= e;
    }
    final error = _error;
    if (error != null) {
      throw error;
    }
  }
}

/// Reads the JSONL records from [path] for tests and offline tooling.
List<Record> readRecords(String path) {
  final lines = File(path).readAsStringSync().trim().split('\n');
  final out = <Record>[];
  for (final line in lines) {
    if (line.trim().isEmpty) continue;
    out.add(Record.fromJson(jsonDecode(line) as Map<String, dynamic>));
  }
  return out;
}

eventwire.WireEvent? _wireEventFromJson(Map<String, dynamic> m) {
  final w = eventwire.WireEvent()
    ..kind = m['kind'] as String? ?? ''
    ..text = m['text'] as String? ?? ''
    ..detail = m['detail'] as String? ?? ''
    ..reasoning = m['reasoning'] as String? ?? ''
    ..itemId = m['itemId'] as String? ?? '';
  final tool = m['tool'];
  if (tool is Map<String, dynamic>) {
    final wt = eventwire.WireTool()
      ..id = tool['id'] as String? ?? ''
      ..name = tool['name'] as String? ?? ''
      ..output = tool['output'] as String? ?? ''
      ..durationMs = tool['durationMs'] as int? ?? 0
      ..startedAt = tool['startedAt'] as int? ?? 0
      ..endedAt = tool['endedAt'] as int? ?? 0;
    w.tool = wt;
  }
  return w;
}
