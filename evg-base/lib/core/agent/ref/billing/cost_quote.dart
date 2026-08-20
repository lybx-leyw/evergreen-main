/// Minimal port of reasonix/internal/billing CostQuote and supporting types.
library;

const displaySourceAuto = 'auto';
const displaySourceExplicit = 'explicit';
const displaySourceWallet = 'wallet';
const displayStatusMatched = 'matched';
const displayStatusFallbackOriginal = 'fallback_original';
const displayStatusBucketed = 'bucketed';
const displayStatusUnavailable = 'unavailable';
const billingModePAYG = 'payg';
const billingModeSubscriptionEquivalent = 'subscription_equivalent';

// Valuation basis values. BasisFX is retained for decoding pre-v6 persisted
// quotes only; new quotes never create FX valuations.
const basisIdentity = 'identity';
const basisOfficialTable = 'official_table';
const basisFX = 'fx';

// Aggregate modes describe how a session/run total was formed.
const aggregateModeSingleCurrency = 'single_currency';
const aggregateModeCommonValuation = 'common_valuation';
const aggregateModeCurrencyBuckets = 'currency_buckets';

class DisplayRequest {
  String currency;
  String source;

  DisplayRequest({this.currency = '', this.source = displaySourceAuto});
}

class RateCard {
  double input = 0.0;
  double output = 0.0;
  double cacheHit = 0.0;
  String currency = '';
}

class UsageTokens {
  int promptTokens = 0;
  int completionTokens = 0;
  int cacheHitTokens = 0;
  int cacheMissTokens = 0;
  int cacheWriteTokens = 0;
  int cacheWriteBilledTokens = 0;
  bool estimated = false;
}

class QuoteInput {
  UsageTokens usage = UsageTokens();
  RateCard rates = RateCard();
  DateTime occurredAt = DateTime.now().toUtc();
  DisplayRequest display = DisplayRequest();
  String billingMode = billingModePAYG;
  String modelRef = '';
  String usageSource = '';
}

class Money {
  /// Decimal amount string on the wire (mirrors Go billing.Money.Amount).
  final String amount;
  final String currency;

  const Money(this.amount, this.currency);

  /// Parses [amount] as a double for legacy float consumers.
  double float64() => double.tryParse(amount) ?? 0.0;
}

/// One currency view of a cost fact. Mirrors Go billing.Valuation.
class Valuation {
  Money money = const Money('0', '');
  String basis = basisIdentity;
  String source = '';
  String asOf = ''; // YYYY-MM-DD
  bool stale = false;

  Valuation(
      {Money? money,
      this.basis = basisIdentity,
      this.source = '',
      this.asOf = '',
      this.stale = false})
      : money = money ?? const Money('0', '');
}

/// An FX observation used for a valuation. Mirrors Go billing.RateSnapshot.
class RateSnapshot {
  String base = '';
  String quote = '';
  double rate = 0.0;
  String source = '';
  String asOf = '';
  bool stale = false;
}

class CostQuote {
  Money original = const Money('0', '');
  List<String> originalTotals = [];
  Map<String, Valuation> valuations = {};
  Money? selected;
  String billingMode = '';
  bool estimated = true;
  bool costComplete = false;
  bool displayComplete = false;
  bool complete = false;
  String displayStatus = displayStatusUnavailable;
  String aggregateMode = '';
  String modelRef = '';
  String usageSource = '';
  String pricingFingerprint = '';
  String rateDate = ''; // YYYY-MM-DD of FX used, if any
  String incompleteReason = '';
  bool legacyEstimate = false;
  String catalogSource = '';

  double get cost => selected?.float64() ?? 0.0;
  String get currencyCode => selected?.currency ?? '';
  String legacyCurrencySymbol() =>
      selected == null ? '' : currencySymbol(selected!.currency);
  String legacyCurrencyCode() =>
      selected == null ? '' : normalizeCurrency(selected!.currency);
}

/// Maps symbols and aliases to ISO-4217 codes when known. Unknown
/// three-letter codes pass through uppercased; empty stays empty.
/// Mirrors Go billing.NormalizeCurrency.
String normalizeCurrency(String currency) {
  final value = currency.trim();
  if (value.isEmpty) return '';
  switch (value.toUpperCase()) {
    case 'CNY':
    case 'RMB':
    case 'CNH':
    case 'YUAN':
    case 'RENMINBI':
      return 'CNY';
    case 'USD':
    case 'US\$':
    case 'DOLLAR':
    case 'DOLLARS':
      return 'USD';
    case 'EUR':
    case 'EURO':
    case 'EUROS':
      return 'EUR';
    case 'GBP':
    case 'POUND':
    case 'POUNDS':
    case 'STERLING':
      return 'GBP';
    case 'JPY':
    case 'YEN':
      return 'JPY';
  }
  switch (value) {
    case '¥':
    case '￥':
      return 'CNY';
    case r'$':
      return 'USD';
    case '€':
      return 'EUR';
    case '£':
      return 'GBP';
  }
  final allAlpha = RegExp(r'^[A-Za-z]{3}$').hasMatch(value);
  if (allAlpha) return value.toUpperCase();
  return value;
}

/// Compact display symbol for an ISO code or symbol. Empty maps to ¥,
/// mirroring Go billing.CurrencySymbol.
String currencySymbol(String currency) {
  switch (normalizeCurrency(currency)) {
    case 'CNY':
    case 'JPY':
      return '¥';
    case 'USD':
      return r'$';
    case 'EUR':
      return '€';
    case 'GBP':
      return '£';
    case '':
      return '¥';
    default:
      final code = normalizeCurrency(currency);
      if (code.length == 3) return '$code ';
      return currency;
  }
}

/// Computes the fixed-point original cost from rates + tokens, mirroring
/// Go billing.OriginalCostAmount.
double originalCostAmount(RateCard rates, UsageTokens u) {
  var hit = u.cacheHitTokens;
  var miss = u.cacheMissTokens;
  if (hit + miss == 0 && u.promptTokens > 0) {
    miss = u.promptTokens;
  } else if (miss == 0 && hit > 0 && u.promptTokens > hit) {
    miss = u.promptTokens - hit;
  }
  var write = u.cacheWriteTokens;
  if (write < 0) write = 0;
  if (write > miss) write = miss;
  var billedWrite = 0.0;
  if (write > 0) {
    billedWrite = u.cacheWriteBilledTokens.toDouble();
    if (billedWrite <= 0) billedWrite = write.toDouble();
  }
  final inputTokenUnits = (miss - write).toDouble() + billedWrite;
  // Combine cached input, uncached input, and output charges per million
  // tokens.
  return (hit.toDouble() * rates.cacheHit +
          inputTokenUnits * rates.input +
          u.completionTokens.toDouble() * rates.output) /
      1e6;
}

/// Formats a float cost as the decimal string used on the wire
/// (Go: Amount.String with 1e9 fixed-point; a trimmed decimal is sufficient
/// for the legacy float path).
String _fmtAmount(double cost) {
  var s = cost.toStringAsFixed(9);
  s = s.replaceFirst(RegExp(r'0+$'), '');
  s = s.replaceFirst(RegExp(r'\.$'), '');
  if (s.isEmpty || s == '-') s = '0';
  return s;
}

CostQuote buildQuote(QuoteInput input) {
  final q = CostQuote()
    ..modelRef = input.modelRef
    ..usageSource = input.usageSource
    ..billingMode = input.billingMode
    ..displayStatus = displayStatusUnavailable
    ..incompleteReason = 'no_price';
  // Go: an empty rate-card currency defaults to CNY; a missing display
  // request defaults to the original currency. Without the official price
  // book / FX table (ported in the billing phase) only the identity
  // valuation is produced — no runtime FX valuation is ever fabricated.
  final rates = input.rates;
  final selectedCurrency = rates.currency.isEmpty ? 'CNY' : rates.currency;
  final cost = originalCostAmount(rates, input.usage);
  q.original = Money(_fmtAmount(cost), selectedCurrency);
  q.valuations[selectedCurrency] = Valuation(
    money: Money(_fmtAmount(cost), selectedCurrency),
    basis: basisIdentity,
    source: 'rate_card',
  );
  q.selected = Money(_fmtAmount(cost), selectedCurrency);
  q.costComplete = rates.input > 0 || rates.output > 0;
  final display = input.display.currency.isEmpty
      ? selectedCurrency
      : input.display.currency;
  q.displayComplete = display == selectedCurrency;
  q.estimated = !q.costComplete;
  q.complete = q.costComplete && q.displayComplete;
  if (q.complete) {
    q.displayStatus = displayStatusMatched;
    q.incompleteReason = '';
  }
  return q;
}
