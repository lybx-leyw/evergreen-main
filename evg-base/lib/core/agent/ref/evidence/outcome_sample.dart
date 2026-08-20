/// Minimal port of reasonix/internal/evidence OutcomeSample.
library;

class OutcomeSample {
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
}
