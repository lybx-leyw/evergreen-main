part of 'event.dart';

class RunBudgetTotals {
  int rounds = 0;
  int requests = 0;
  int promptTokens = 0;
  int outputTokens = 0;
  double cost = 0.0;
  bool priced = false;
  int elapsedMs = 0;
}

class RunBudgetSample {
  final RunBudgetTotals turn = RunBudgetTotals();
  final RunBudgetTotals task = RunBudgetTotals();
  String currency = '';
}

void recordRunBudget(Sink s, RunBudgetSample sample) {
  if (nilutil.isNil(s)) return;
  if (s is RunBudgetSink) s.recordRunBudget(sample);
}
