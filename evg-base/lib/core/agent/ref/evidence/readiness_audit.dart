/// Minimal port of reasonix/internal/evidence ReadinessAudit.
library;

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
}
