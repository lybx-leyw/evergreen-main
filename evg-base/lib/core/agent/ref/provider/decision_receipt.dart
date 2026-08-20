/// Minimal port of reasonix/internal/provider DecisionReceipt.
library;

class DecisionReceipt {
  final String id;
  final String kind;
  final String tool;
  final String subject;
  final String outcome;

  const DecisionReceipt({
    this.id = '',
    this.kind = '',
    this.tool = '',
    this.subject = '',
    this.outcome = '',
  });
}
