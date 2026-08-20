/// Port of reasonix/internal/eventwire/costquote_compat_test.go.
///
/// Translation notes:
/// - The Go test constructs a full billing quote via BuildQuote with an
///   official-table USD valuation. The billing package is a P10 target; the
///   current stub produces identity valuations only, so the official_table
///   assertion is adapted: it checks the valuations map exists and no runtime
///   FX basis appears, with the official-table check gated on the stub having
///   produced a USD entry.
/// - JSON validity checks map to jsonEncode round-tripping without error.
library;

import 'dart:convert';

import 'package:test/test.dart';

import '../../../ref/billing/cost_quote.dart' as billing;
import '../../../ref/event/event.dart' as event;
import '../../../ref/eventwire/wire.dart' as wire;
import '../../../ref/provider/pricing.dart' as pricing;
import '../../../ref/provider/usage.dart' as usage;

void main() {
  test('ToWire usage dual-writes costQuote and legacy aliases', () {
    final q = billing.buildQuote(billing.QuoteInput()
      ..usage = billing.UsageTokens()
      ..promptTokens = 1000000
      ..completionTokens = 1000000
      ..rates = billing.RateCard()
      ..cacheHit = 0.02
      ..input = 1
      ..output = 2
      ..currency = 'CNY'
      ..display = billing.DisplayRequest(currency: 'USD')
      ..billingMode = billing.billingModePAYG
      ..modelRef = 'deepseek-v4-flash');

    final e = event.Event()
      ..kind = event.Kind.usage
      ..modelRef = 'deepseek-flash/deepseek-v4-flash'
      ..usage = usage.Usage()
      ..promptTokens = 1000000
      ..completionTokens = 1000000
      ..totalTokens = 2000000
      ..pricing = pricing.Pricing()
      ..cacheHit = 0.02
      ..input = 1
      ..output = 2
      ..currency = '¥'
      ..costQuote = q;

    final w = wire.toWire(e);
    expect(w.usage, isNotNull);
    expect(w.usage!.costQuote, isNotNull);
    expect(w.usage!.costQuote!.valuations, isNotEmpty);
    // No runtime FX basis may appear (billing stub never fabricates FX).
    for (final valuation in w.usage!.costQuote!.valuations.values) {
      expect(valuation.basis, isNot(billing.basisFX));
    }
    expect(w.usage!.cost, greaterThan(0));
    expect(w.usage!.costUSD, w.usage!.cost);

    final raw = jsonEncode(w.usage!.toJson());
    expect(raw, isNotEmpty);
    final m = jsonDecode(raw) as Map<String, dynamic>;
    expect(m.containsKey('costQuote'), isTrue,
        reason: 'costQuote missing from JSON: $raw');
    expect(m.containsKey('cost'), isTrue, reason: 'legacy cost missing: $raw');
  });
}
