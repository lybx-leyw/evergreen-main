part of 'event.dart';

class AuditForwarder
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

  AuditForwarder(this.inner);

  @override
  void emit(Event e) => inner.emit(e);

  @override
  void recordDelegationAudit(evidence.DelegationAudit a) =>
      recordDelegationAudit(inner, a);
  @override
  void recordReadinessAudit(evidence.ReadinessAudit a) =>
      recordReadinessAudit(inner, a);
  @override
  void recordTurnCompletion() => recordTurnCompletion(inner);
  @override
  void recordContractShadow(ContractShadowAudit a) =>
      recordContractShadow(inner, a);
  @override
  void recordCompletionReport(CompletionReportAudit a) =>
      recordCompletionReport(inner, a);
  @override
  void recordMemoryRecall(MemoryRecallAudit a) => recordMemoryRecall(inner, a);
  @override
  void recordDelegationAdmission(DelegationAdmissionAudit a) =>
      recordDelegationAdmission(inner, a);
  @override
  void recordOutcomeProgress(evidence.OutcomeSample sample) =>
      recordOutcomeProgress(inner, sample);
  @override
  void recordProtocolRecovery(ProtocolRecoveryAudit a) =>
      recordProtocolRecovery(inner, a);
  @override
  void recordRunBudget(RunBudgetSample sample) =>
      recordRunBudget(inner, sample);
  @override
  void recordWorkspaceMutation(WorkspaceMutation m) =>
      recordWorkspaceMutation(inner, m);
}
