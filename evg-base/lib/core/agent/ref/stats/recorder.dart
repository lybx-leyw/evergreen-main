part of 'stats.dart';

/// A passthrough event.Sink that snapshots token usage (event.Usage) and
/// completed turns (event.TurnDone) into the daily stats files. It observes
/// only; it never alters the event stream.
class Recorder implements event.Sink {
  final event.Sink? inner;
  final Writer writer;
  final RecordDispatcher? dispatcher;
  final String source;

  Recorder(
      {required this.inner,
      required this.writer,
      this.dispatcher,
      required this.source});

  /// Forwards user-visible events unchanged, then queues any usage/turn
  /// record without waiting for filesystem I/O. Request-only usage is
  /// internal accounting for failed provider calls, so it is persisted
  /// without surfacing a zero-token receipt in the wrapped frontend.
  @override
  void emit(event.Event e) {
    final requestOnly = e.kind == event.Kind.usage &&
        e.usage != null &&
        e.usage!.totalTokens <= 0 &&
        e.usage!.requestCount > 0;
    if (inner != null && !requestOnly) {
      inner!.emit(e);
    }
    if (e.kind == event.Kind.usage) {
      _recordUsage(e);
    } else if (e.kind == event.Kind.guardianAssessment &&
        e.guardian.usage != null) {
      _recordProviderUsage(e.modelRef, e.guardian.usage, null, '');
    } else if (e.kind == event.Kind.turnDone) {
      recordTurnCompletion();
    }
  }

  /// Records synchronous controller runs that deliberately do not emit
  /// TurnDone into the UI event stream.
  void recordTurnCompletion() {
    dispatcher?.enqueue(StatsRecord()
      ..timestamp = DateTime.now()
      ..source = source
      ..turn = true);
  }

  /// Waits until records already accepted by this recorder's shared queue
  /// have been written. Production event paths never call this; it exists for
  /// shutdown/verification boundaries that can explicitly tolerate waiting.
  Future<void> flush() async {
    await dispatcher?.flush();
    final catalog = writer.usage?.catalog;
    if (catalog != null) {
      await catalog.flush();
    }
  }

  void _recordUsage(event.Event e) {
    _recordProviderUsage(e.modelRef, e.usage, e.costQuote, e.usageSource);
  }

  void _recordProviderUsage(String modelRef, provider.Usage? usage,
      billing.CostQuote? quote, String usageSource) {
    if (usage == null || (usage.totalTokens <= 0 && usage.requestCount <= 0)) {
      return;
    }
    // Recording is best-effort: a stats file failure (disk full, permissions)
    // must never interrupt the event stream.
    final rec = StatsRecord()
      ..timestamp = DateTime.now()
      ..modelRef = modelRef
      ..source = source
      ..prompt = usage.promptTokens
      ..completion = usage.completionTokens
      ..reasoning = usage.reasoningTokens
      ..cacheHit = usage.cacheHitTokens ?? 0
      ..cacheMiss = usage.cacheMissTokens ?? 0
      ..total = usage.totalTokens
      ..requests = usageRequestCount(usage)
      ..usageSource = usageSource.trim();
    if (quote != null) {
      rec.costAmount = quote.original.amount;
      rec.costCurrency = quote.original.currency;
      rec.pricingFingerprint = quote.pricingFingerprint;
      rec.rateDate = quote.rateDate;
      rec.incompleteReason = quote.incompleteReason;
      rec.billingMode = quote.billingMode;
      rec.costEstimated = quote.estimated;
      rec.legacyEstimate = quote.legacyEstimate;
      rec.costComplete = quote.costComplete;
      rec.displayComplete = quote.displayComplete;
      rec.displayStatus = quote.displayStatus;
      rec.aggregateMode = quote.aggregateMode;
      for (final total in quote.originalTotals) {
        rec.originalTotals.add('${total.currency}:${total.amount}');
      }
      if (quote.selected != null) {
        rec.selectedAmount = quote.selected!.amount;
        rec.selectedCurrency = quote.selected!.currency;
        rec.selectedCost = quote.selected!.float64();
      }
      final cny = quote.valuations['CNY'];
      if (cny != null) rec.valuationCNY = cny.money.amount;
      final usd = quote.valuations['USD'];
      if (usd != null) rec.valuationUSD = usd.money.amount;
    }
    dispatcher?.enqueue(rec);
  }
}

int usageRequestCount(provider.Usage? usage) {
  if (usage != null && usage.requestCount > 0) return usage.requestCount;
  return 1;
}

/// Keeps filesystem latency off provider/UI event goroutines. Dispatchers are
/// shared per state directory, so controller rebuilds do not create one
/// dispatcher per recorder instance. Statistics are observational: a full
/// queue may lose a record, but it must never apply backpressure.
class RecordDispatcher {
  static const queueSize = 2048;
  final Writer writer;
  final _Queue<StatsRecord> queue = _Queue<StatsRecord>(queueSize);
  bool _draining = false;

  RecordDispatcher(this.writer);

  static final Map<String, RecordDispatcher> _byDir = {};

  static RecordDispatcher? forDir(String dir) {
    final trimmed = dir.trim();
    if (trimmed.isEmpty) return null;
    return _byDir.putIfAbsent(trimmed, () => RecordDispatcher(Writer(trimmed)));
  }

  static RecordDispatcher? existing(String dir) {
    final trimmed = dir.trim();
    if (trimmed.isEmpty) return null;
    return _byDir[trimmed];
  }

  void enqueue(StatsRecord rec) {
    queue.add(rec);
    _drain();
  }

  Future<void> flush() async {
    await queue.flush();
  }

  void _drain() {
    if (_draining) return;
    _draining = true;
    while (queue.hasPending()) {
      final rec = queue.take();
      if (rec != null) {
        // Best-effort: append failures never surface to the event path.
        writer.append(rec).catchError((_) {});
      }
    }
    _draining = false;
  }
}

/// Minimal bounded async queue: pending records buffer; a full queue drops
/// the newest record (no backpressure), and flush() waits for draining.
class _Queue<T> {
  final int capacity;
  final List<T> _items = [];
  Completer<void>? _drainCompleter;

  _Queue(this.capacity);

  bool get hasPending => _items.isNotEmpty;

  void add(T item) {
    if (_items.length >= capacity) {
      _items.removeAt(0); // drop oldest under pressure
    }
    _items.add(item);
    _drainCompleter ??= Completer<void>();
  }

  T? take() => _items.isEmpty ? null : _items.removeAt(0);

  Future<void> flush() async {
    final completer = _drainCompleter;
    _drainCompleter = null;
    if (completer != null) {
      // Wait for the currently pending batch to be appended.
      await Future<void>.delayed(Duration.zero);
    }
  }
}

/// usageEntry builds the projection entry for a newly appended record.
usagecatalog.Entry usageEntry(String day, StatsRecord r) {
  return usagecatalog.Entry(
    day: day,
    source: r.source,
    modelRef: r.modelRef,
    provider: providerOf(r.modelRef),
    prompt: r.prompt,
    completion: r.completion,
    reasoning: r.reasoning,
    cacheHit: r.cacheHit,
    cacheMiss: r.cacheMiss,
    total: r.total,
    requests: r.requests,
    turns: r.turn ? 1 : 0,
  );
}
