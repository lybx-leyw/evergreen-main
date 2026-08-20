part of 'event.dart';

Sink sync(Sink s) => nilutil.isNil(s) ? discard : _SyncSink(s);

class _SyncSink
    implements
        Sink,
        DelegationAuditSink,
        ReadinessAuditSink,
        TurnCompletionSink,
        ProtocolRecoveryAuditSink,
        ContractShadowAuditSink,
        CompletionReportAuditSink,
        OutcomeProgressSink,
        MemoryRecallSink,
        DelegationAdmissionSink,
        RunBudgetSink,
        WorkspaceMutationSink {
  final Sink inner;
  final _mutex = Queue<Future<void>>();

  _SyncSink(this.inner);

  @override
  void emit(Event e) {
    _runLocked(() => inner.emit(e));
  }

  @override
  void recordDelegationAudit(evidence.DelegationAudit a) =>
      _runLocked(() => recordDelegationAudit(inner, a));
  @override
  void recordReadinessAudit(evidence.ReadinessAudit a) =>
      _runLocked(() => recordReadinessAudit(inner, a));
  @override
  void recordTurnCompletion() => _runLocked(() => recordTurnCompletion(inner));
  @override
  void recordProtocolRecovery(ProtocolRecoveryAudit a) =>
      _runLocked(() => recordProtocolRecovery(inner, a));
  @override
  void recordContractShadow(ContractShadowAudit a) =>
      _runLocked(() => recordContractShadow(inner, a));
  @override
  void recordCompletionReport(CompletionReportAudit a) =>
      _runLocked(() => recordCompletionReport(inner, a));
  @override
  void recordOutcomeProgress(evidence.OutcomeSample sample) =>
      _runLocked(() => recordOutcomeProgress(inner, sample));
  @override
  void recordMemoryRecall(MemoryRecallAudit a) =>
      _runLocked(() => recordMemoryRecall(inner, a));
  @override
  void recordDelegationAdmission(DelegationAdmissionAudit a) =>
      _runLocked(() => recordDelegationAdmission(inner, a));
  @override
  void recordRunBudget(RunBudgetSample sample) =>
      _runLocked(() => recordRunBudget(inner, sample));
  @override
  void recordWorkspaceMutation(WorkspaceMutation m) =>
      _runLocked(() => recordWorkspaceMutation(inner, m));

  void _runLocked(void Function() f) {
    f();
  }
}
