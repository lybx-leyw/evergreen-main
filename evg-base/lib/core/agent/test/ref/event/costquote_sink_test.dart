/// Port of reasonix/internal/event/costquote_sink_test.go.
///
/// Translation notes:
/// - Go's `provider.Pricing{Input: 1, ...}` maps to mutable Pricing fields.
/// - The Go test verifies a rate-card quote in CNY with a USD display request
///   never fabricates a runtime FX valuation; the Dart billing stub mirrors
///   this by only ever producing identity-basis valuations.
library;

import 'package:test/test.dart';

import '../../../../ref/billing/cost_quote.dart' as billing;
import '../../../../ref/event/event.dart' as event;
import '../../../../ref/provider/pricing.dart' as provider;
import '../../../../ref/provider/usage.dart' as usage;

void main() {
  test('ensureCostQuote does not use runtime FX', () {
    final e = event.Event()
      ..kind = event.Kind.usage
      ..modelRef = 'deepseek/deepseek-v4-flash'
      ..usageSource = event.usageSourceExecutor
      ..pricing = provider.Pricing()
      ..input = 1
      ..output = 2
      ..currency = 'CNY'
      ..usage = usage.Usage()
      ..promptTokens = 100
      ..completionTokens = 100;
    final ctx = event.QuoteContext()..displayCurrency = 'USD';
    final q = event.ensureCostQuote(e, ctx);
    expect(q, isNotNull);
    expect(q!.selected, isNotNull);
    expect(q.selected!.currency, 'CNY');
    expect(q.complete, isFalse);
    for (final valuation in q.valuations.values) {
      expect(valuation.basis, isNot(billing.basisFX));
    }
  });
}
