part of 'stats.dart';

/// Names one stats file per UTC-free local day, e.g. 2026-08-02.jsonl.
String dayLayout(DateTime d) => d.toIso8601String().substring(0, 10);

const appendLockTimeout = Duration(seconds: 2);

/// One line in a daily stats file. [turn] marks a completed turn so per-day
/// turn counts are available without touching session files.
class StatsRecord {
  DateTime timestamp = DateTime.now();
  String modelRef = '';
  String source = '';
  int prompt = 0;
  int completion = 0;
  int reasoning = 0;
  int cacheHit = 0;
  int cacheMiss = 0;
  int total = 0;
  int requests = 0; // provider requests represented by this row
  bool turn = false; // true for TurnDone marker rows
  // Cost quote fields (additive; older readers ignore them).
  String usageSource = '';
  String costAmount = '';
  String costCurrency = '';
  String selectedAmount = '';
  String selectedCurrency = '';
  bool? costComplete;
  bool? displayComplete;
  String displayStatus = '';
  String aggregateMode = '';
  List<String> originalTotals = [];
  bool costEstimated = false;
  bool legacyEstimate = false;
  String pricingFingerprint = '';
  String rateDate = '';
  String incompleteReason = '';
  String billingMode = '';
  String valuationCNY = '';
  String valuationUSD = '';
  double selectedCost = 0.0;

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'ts': timestamp.toIso8601String(),
    };
    void put(String key, Object? v) {
      if (v != null && v != '' && v != 0 && v != false && v != const []) {
        m[key] = v;
      }
    }

    put('model', modelRef);
    put('source', source);
    put('prompt', prompt);
    put('completion', completion);
    put('reasoning', reasoning);
    put('cache_hit', cacheHit);
    put('cache_miss', cacheMiss);
    put('total', total);
    put('requests', requests);
    put('turn', turn);
    put('usage_source', usageSource);
    put('cost_amount', costAmount);
    put('cost_currency', costCurrency);
    put('selected_amount', selectedAmount);
    put('selected_currency', selectedCurrency);
    put('cost_complete', costComplete);
    put('display_complete', displayComplete);
    put('display_status', displayStatus);
    put('aggregate_mode', aggregateMode);
    put('original_totals', originalTotals);
    put('cost_estimated', costEstimated);
    put('legacy_estimate', legacyEstimate);
    put('pricing_fingerprint', pricingFingerprint);
    put('rate_date', rateDate);
    put('incomplete_reason', incompleteReason);
    put('billing_mode', billingMode);
    put('valuation_cny', valuationCNY);
    put('valuation_usd', valuationUSD);
    put('selected_cost', selectedCost);
    return m;
  }
}

/// Appends records to the daily stats file for a given stats dir.
class Writer {
  final String dir;
  UsageManager? usage;

  Writer(this.dir);

  /// An empty dir disables recording (query-only usage).
  bool get disabled => dir.trim().isEmpty;

  /// Appends one record to the daily file (O_APPEND semantics) under the
  /// cross-process append lock so concurrent turns never overwrite each
  /// other. Each record is a single JSON line; a crash mid-line leaves at
  /// most one torn trailing line, which [decodeRecords] tolerates.
  Future<void> append(StatsRecord r) async {
    if (disabled) return;
    final day = dayLayout(r.timestamp);
    final path = p.join(dir, '$day.jsonl');
    final bytes = utf8.encode(jsonEncode(r.toJson()));
    await Directory(dir).create(recursive: true);
    final release = await _acquireLock(dir);
    if (release == null) {
      throw FileSystemException('stats: append lock timeout', path);
    }
    var released = false;
    try {
      final f = await File(path).open(mode: FileMode.append);
      try {
        await _ensureRecordBoundary(f);
        final offset = await f.length();
        final line = [...bytes, 0x0A];
        await f.writeFrom(line);
        await f.flush();
        if (usage != null) {
          final catalog = usage!.catalog;
          if (catalog != null) {
            catalog.enqueue(
                usagecatalog.AppendReceipt(
                    path: path,
                    day: day,
                    offset: offset,
                    length: line.length,
                    lineHash: _sha256Hex(bytes)),
                usageEntry(day, r));
          }
        }
      } finally {
        await f.close();
      }
      released = true;
    } finally {
      await release();
    }
  }

  Future<filelock.FileLock?> _acquireLock(String dir) =>
      filelock.FileLock.acquire(p.join(dir, '.append.lock'),
          timeout: appendLockTimeout);

  /// Separates a torn trailing JSON object from the next append. The caller
  /// holds the cross-process append lock, so checking the last byte and
  /// repairing it cannot race another writer.
  Future<void> _ensureRecordBoundary(RandomAccessFile f) async {
    final len = await f.length();
    if (len == 0) return;
    await f.setPosition(len - 1);
    final tail = await f.readByte();
    if (tail == 0x0A) return;
    await f.setPosition(len);
    await f.writeByte(0x0A);
  }

  /// Loads one daily file into records. Missing files yield null, null.
  Future<List<StatsRecord>?> readDaily(String day) async {
    if (dir.trim().isEmpty) return null;
    final f = File(p.join(dir, '$day.jsonl'));
    if (!await f.exists()) return null;
    return decodeRecords(await f.readAsString());
  }

  /// Snapshots the available daily files with one directory scan, then reads
  /// only dates requested by the query. Long custom ranges are often mostly
  /// empty; avoiding one failed open per absent day keeps their cost
  /// proportional to the data that actually exists.
  Future<Map<String, List<StatsRecord>>> readDailyRange(
      List<String> days) async {
    final out = <String, List<StatsRecord>>{};
    if (dir.trim().isEmpty || days.isEmpty) return out;
    final wanted = days.toSet();
    final entries = Directory(dir).listSync(followLinks: false);
    for (final entry in entries) {
      if (entry is! File) continue;
      final name = entry.uri.pathSegments.last;
      if (!name.endsWith('.jsonl')) continue;
      final day = name.substring(0, name.length - '.jsonl'.length);
      if (!wanted.contains(day)) continue;
      final records = await readDaily(day);
      if (records != null) out[day] = records;
    }
    return out;
  }
}

/// Decodes a daily file's records. Malformed lines (a crash mid-write or a
/// manual edit) are skipped rather than failing the whole day's aggregation.
List<StatsRecord> decodeRecords(String text) {
  final out = <StatsRecord>[];
  for (final rawLine in text.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    final rec = _decodeRecordLine(line);
    if (rec != null) out.add(rec);
  }
  return out;
}

StatsRecord? _decodeRecordLine(String line) {
  try {
    final m = jsonDecode(line) as Map<String, dynamic>;
    final rec = StatsRecord();
    final ts = m['ts'];
    if (ts is String) {
      rec.timestamp = DateTime.parse(ts);
    }
    rec.modelRef = m['model'] as String? ?? '';
    rec.source = m['source'] as String? ?? '';
    rec.prompt = m['prompt'] as int? ?? 0;
    rec.completion = m['completion'] as int? ?? 0;
    rec.reasoning = m['reasoning'] as int? ?? 0;
    rec.cacheHit = m['cache_hit'] as int? ?? 0;
    rec.cacheMiss = m['cache_miss'] as int? ?? 0;
    rec.total = m['total'] as int? ?? 0;
    rec.requests = m['requests'] as int? ?? 0;
    rec.turn = m['turn'] as bool? ?? false;
    rec.usageSource = m['usage_source'] as String? ?? '';
    rec.costAmount = m['cost_amount'] as String? ?? '';
    rec.costCurrency = m['cost_currency'] as String? ?? '';
    rec.selectedAmount = m['selected_amount'] as String? ?? '';
    rec.selectedCurrency = m['selected_currency'] as String? ?? '';
    rec.costComplete = m['cost_complete'] as bool?;
    rec.displayComplete = m['display_complete'] as bool?;
    rec.displayStatus = m['display_status'] as String? ?? '';
    rec.aggregateMode = m['aggregate_mode'] as String? ?? '';
    final totals = m['original_totals'];
    if (totals is List) {
      rec.originalTotals = totals.whereType<String>().toList();
    }
    rec.costEstimated = m['cost_estimated'] as bool? ?? false;
    rec.legacyEstimate = m['legacy_estimate'] as bool? ?? false;
    rec.pricingFingerprint = m['pricing_fingerprint'] as String? ?? '';
    rec.rateDate = m['rate_date'] as String? ?? '';
    rec.incompleteReason = m['incomplete_reason'] as String? ?? '';
    rec.billingMode = m['billing_mode'] as String? ?? '';
    rec.valuationCNY = m['valuation_cny'] as String? ?? '';
    rec.valuationUSD = m['valuation_usd'] as String? ?? '';
    rec.selectedCost = (m['selected_cost'] as num?)?.toDouble() ?? 0.0;
    return rec;
  } catch (_) {
    return null;
  }
}

/// Lists the daily file names (without extension) whose timestamps intersect
/// [from, to], inclusive.
List<String> daysInRange(DateTime from, DateTime to) {
  final f = dayStart(from);
  final t = dayStart(to);
  if (t.isBefore(f)) return const [];
  final days = <String>[];
  var d = f;
  while (!d.isAfter(t)) {
    days.add(dayLayout(d));
    d = DateTime(d.year, d.month, d.day + 1);
  }
  return days;
}

DateTime dayStart(DateTime t) => DateTime(t.year, t.month, t.day);

String _sha256Hex(List<int> bytes) {
  // NOTE: placeholder digest for the usage-catalog receipt. The real SHA-256
  // (crypto package) is ported with the P11 usagecatalog backend; the
  // placeholder catalog ignores receipts, so no caller observes this value
  // during P1.
  var hash = 0x811c9dc5;
  for (final b in bytes) {
    hash ^= b;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}
