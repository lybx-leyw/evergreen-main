part of 'stats.dart';

/// One day's token usage and turn count in a trend series.
class DailyTokens {
  String day = ''; // "2026-08-02"
  int total = 0;
  Map<String, int> byModel = {}; // model ref -> tokens
  Map<String, int> byProvider = {}; // provider name -> tokens
  int requests = 0; // provider API requests
  int turns = 0; // completed turns
  int cacheHit = 0; // cached input tokens that day
  int cacheMiss = 0; // uncached input tokens that day

  Map<String, dynamic> toJson() => {
        'day': day,
        'total': total,
        'byModel': byModel,
        'byProvider': byProvider,
        'requests': requests,
        'turns': turns,
        'cacheHit': cacheHit,
        'cacheMiss': cacheMiss,
      };
}

/// One model's aggregate within the range.
class ModelUsage {
  String model = '';
  String provider = '';
  int tokens = 0;
  double percent = 0.0; // 0..100

  Map<String, dynamic> toJson() => {
        'model': model,
        'provider': provider,
        'tokens': tokens,
        'percent': percent,
      };
}

/// One provider's aggregate within the range (each provider may serve
/// several models).
class ProviderUsage {
  String provider = '';
  int tokens = 0;
  double percent = 0.0;

  Map<String, dynamic> toJson() => {
        'provider': provider,
        'tokens': tokens,
        'percent': percent,
      };
}

/// The full aggregate the settings panel renders for one time range and
/// source filter.
class RangeStats {
  String from = ''; // inclusive
  String to = ''; // inclusive
  // Totals
  int tokens = 0;
  int requests = 0; // provider API requests
  int turns = 0; // completed turns
  int cacheHit = 0;
  int cacheMiss = 0;
  // Derived
  int activeDays = 0;
  String topModel = '';
  String topProvider = '';
  // Series
  List<DailyTokens> daily = [];
  List<ModelUsage> models = [];
  List<ProviderUsage> providers = [];

  Map<String, dynamic> toJson() => {
        'from': from,
        'to': to,
        'tokens': tokens,
        'requests': requests,
        'turns': turns,
        'cache_hit': cacheHit,
        'cache_miss': cacheMiss,
        'active_days': activeDays,
        'top_model': topModel,
        'top_provider': topProvider,
        'daily': daily.map((d) => d.toJson()).toList(),
        'models': models.map((m) => m.toJson()).toList(),
        'providers': providers.map((p) => p.toJson()).toList(),
      };
}

/// Selects which source labels to aggregate; "" or "all" includes every
/// source.
class SourceFilter {
  final String source;
  final DateTime from;
  final DateTime to;

  SourceFilter({this.source = '', required this.from, required this.to});
}

/// Aggregates the daily stats files intersecting [from, to]. Missing days
/// yield zero entries. When [SourceFilter.source] is set, only records whose
/// source matches are counted.
Future<RangeStats> queryStats(Writer w, SourceFilter f) async {
  // The usage catalog projection (P11) is a fast path only; with no catalog
  // loaded we always fall back to the JSONL aggregation (Go's fallback path).
  return queryJSONL(w, f);
}

Future<RangeStats> queryJSONL(Writer w, SourceFilter f) async {
  final out = RangeStats()
    ..from = dayLayout(f.from)
    ..to = dayLayout(f.to)
    ..daily = []
    ..models = []
    ..providers = [];
  if (w == null || w.disabled) return out;
  final days = daysInRange(f.from, f.to);
  final recordsByDay = await w.readDailyRange(days);
  final modelTotals = <String, int>{};
  final providerTotals = <String, int>{};
  final active = <String, bool>{};

  for (final day in days) {
    final recs = recordsByDay[day] ?? const <StatsRecord>[];
    final dayTotals = <String, int>{};
    var dayTurns = 0;
    var dayRequests = 0;
    var dayCacheHit = 0;
    var dayCacheMiss = 0;
    var dayActive = false;
    for (final rec in recs) {
      if (!matchesSource(rec.source, f.source)) continue;
      if (rec.turn) {
        dayTurns++;
        continue;
      }
      final t = rec.total;
      // Tokens keeps the provider's TotalTokens value as-is; the cache
      // hit-rate is derived only from the input side (CacheHit+CacheMiss), so
      // the two denominators never mix.
      out.tokens += t;
      out.cacheHit += rec.cacheHit;
      out.cacheMiss += rec.cacheMiss;
      dayCacheHit += rec.cacheHit;
      dayCacheMiss += rec.cacheMiss;
      var requests = rec.requests;
      if (rec.total > 0 && requests <= 0) {
        // Rows written before request accounting existed represented one
        // successful provider call.
        requests = 1;
      }
      if (requests > 0) {
        out.requests += requests;
        dayRequests += requests;
      }
      if (rec.total > 0) {
        var model = rec.modelRef;
        if (model.isEmpty) model = '(unknown)';
        modelTotals[model] = (modelTotals[model] ?? 0) + t;
        final prov = providerOf(model);
        providerTotals[prov] = (providerTotals[prov] ?? 0) + t;
        dayTotals[model] = (dayTotals[model] ?? 0) + t;
      }
      dayActive = dayActive || rec.total > 0 || requests > 0;
    }
    if (dayActive) active[day] = true;
    out.turns += dayTurns;
    final byProvider = <String, int>{};
    for (final e in dayTotals.entries) {
      final prov = providerOf(e.key);
      byProvider[prov] = (byProvider[prov] ?? 0) + e.value;
    }
    out.daily.add(DailyTokens()
      ..day = day
      ..total = sum(dayTotals)
      ..byModel = Map.of(dayTotals)
      ..byProvider = byProvider
      ..requests = dayRequests
      ..turns = dayTurns
      ..cacheHit = dayCacheHit
      ..cacheMiss = dayCacheMiss);
  }
  out.activeDays = active.length;
  out.models = modelsSorted(modelTotals);
  out.providers = providersSorted(providerTotals);
  if (out.models.isNotEmpty) out.topModel = out.models[0].model;
  if (out.providers.isNotEmpty) out.topProvider = out.providers[0].provider;
  if (out.tokens > 0) {
    for (var i = 0; i < out.models.length; i++) {
      out.models[i].percent = out.models[i].tokens / out.tokens * 100;
    }
    for (var i = 0; i < out.providers.length; i++) {
      out.providers[i].percent = out.providers[i].tokens / out.tokens * 100;
    }
  }
  out.daily.sort((a, b) => a.day.compareTo(b.day));
  return out;
}

/// Reports whether a record's source label passes the filter. An empty
/// filter or "all" matches every source.
bool matchesSource(String recSource, String filter) {
  if (filter.isEmpty || filter == 'all') return true;
  return recSource == filter;
}

String providerOf(String modelRef) {
  // model refs are "provider/model"; a bare model name has no slash and is
  // attributed to provider "default".
  final i = modelRef.indexOf('/');
  if (i > 0) return modelRef.substring(0, i);
  return 'default';
}

int sum(Map<String, int> m) {
  var s = 0;
  for (final v in m.values) {
    s += v;
  }
  return s;
}

List<ModelUsage> modelsSorted(Map<String, int> totals) {
  final out = <ModelUsage>[];
  totals.forEach((model, t) {
    out.add(ModelUsage()
      ..model = model
      ..provider = providerOf(model)
      ..tokens = t);
  });
  out.sort((a, b) {
    if (a.tokens == b.tokens) return a.model.compareTo(b.model);
    return b.tokens.compareTo(a.tokens);
  });
  return out;
}

List<ProviderUsage> providersSorted(Map<String, int> totals) {
  final out = <ProviderUsage>[];
  totals.forEach((prov, t) {
    out.add(ProviderUsage()
      ..provider = prov
      ..tokens = t);
  });
  out.sort((a, b) {
    if (a.tokens == b.tokens) return a.provider.compareTo(b.provider);
    return b.tokens.compareTo(a.tokens);
  });
  return out;
}
