part of 'event.dart';

class QuoteContext {
  String displayCurrency = '';
  billing.DisplayRequest displayRequest =
      billing.DisplayRequest(source: billing.displaySourceAuto);
  DateTime Function()? now;
  String Function(String modelRef)? billingModeForModel;

  void setDisplay(String currency) {
    displayCurrency = billing.normalizeCurrency(currency);
    displayRequest = billing.DisplayRequest(
      currency: displayCurrency,
      source: billing.displaySourceExplicit,
    );
  }

  void setDisplayRequest(billing.DisplayRequest request) {
    request.currency = billing.normalizeCurrency(request.currency);
    if (request.source.isEmpty) {
      request.source = billing.displaySourceAuto;
    }
    displayRequest = request;
    displayCurrency = request.currency;
  }

  (billing.DisplayRequest, DateTime) snapshot() {
    final request = billing.DisplayRequest(
      currency: displayRequest.currency.isEmpty
          ? displayCurrency
          : displayRequest.currency,
      source: displayRequest.source.isEmpty
          ? (displayCurrency.isEmpty
              ? billing.displaySourceAuto
              : billing.displaySourceExplicit)
          : displayRequest.source,
    );
    final now = (this.now ?? () => DateTime.now().toUtc())();
    return (request, now);
  }

  String billingMode(String modelRef) {
    if (billingModeForModel == null) return '';
    return billingModeForModel!(modelRef).trim();
  }
}

class CostQuoteSink implements Sink {
  final Sink inner;
  final QuoteContext ctx;

  CostQuoteSink({required this.inner, QuoteContext? ctx})
      : ctx = ctx ?? QuoteContext();

  @override
  void emit(Event e) {
    if (e.kind == Kind.usage && e.usage != null && e.costQuote == null) {
      e.costQuote = ensureCostQuote(e, ctx);
    }
    if (inner != null) inner.emit(e);
  }
}

billing.CostQuote? ensureCostQuote(Event e, QuoteContext? ctx) {
  if (e.usage == null) return null;
  final context = ctx ?? QuoteContext();
  final (display, now) = context.snapshot();
  if (e.pricing == null) {
    return billing.CostQuote()
      ..estimated = true
      ..costComplete = false
      ..displayComplete = false
      ..complete = false
      ..displayStatus = billing.displayStatusUnavailable
      ..incompleteReason = 'no_price'
      ..modelRef = e.modelRef
      ..usageSource = _firstUsageSource(e);
  }
  var mode = billing.billingModePAYG;
  final configured = context.billingMode(e.modelRef);
  if (configured.isNotEmpty) {
    mode = configured;
  } else if (e.modelRef.toLowerCase().contains('token-plan') ||
      e.source.toLowerCase().contains('token-plan')) {
    mode = billing.billingModeSubscriptionEquivalent;
  }
  final card = billing.RateCard()
    ..input = e.pricing!.input
    ..output = e.pricing!.output
    ..cacheHit = e.pricing!.cacheHit
    ..currency = billing.normalizeCurrency(e.pricing!.currency);
  return billing.buildQuote(billing.QuoteInput()
    ..usage = _usageTokens(e.usage!)
    ..rates = card
    ..occurredAt = now
    ..display = display
    ..billingMode = mode
    ..modelRef = e.modelRef
    ..usageSource = _firstUsageSource(e));
}

billing.UsageTokens _usageTokens(provider.Usage u) {
  return billing.UsageTokens()
    ..promptTokens = u.promptTokens
    ..completionTokens = u.completionTokens
    ..cacheHitTokens = u.cacheHitTokens ?? 0
    ..cacheMissTokens = u.cacheMissTokens ?? 0
    ..cacheWriteTokens = u.cacheWriteTokens
    ..cacheWriteBilledTokens = u.cacheWriteBilledTokens
    ..estimated = u.estimated;
}

String _firstUsageSource(Event e) {
  if (e.usageSource.trim().isNotEmpty) return e.usageSource.trim();
  if (e.source.trim().isNotEmpty) return e.source.trim();
  return usageSourceExecutor;
}
