/// Minimal placeholder for reasonix/internal/usagecatalog.
///
/// The full SQLite-backed usage rollup projection is a P11 target. This file
/// only defines the API surface stats needs to compile and to exercise its
/// usageManager lifecycle (generation fencing, close semantics). The catalog
/// is never opened in P1; Query falls back to the JSONL path exactly like the
/// Go code when no catalog is loaded.
library;

/// AppendReceipt records where in a daily stats file an entry came from.
class AppendReceipt {
  final String path;
  final String day;
  final int offset;
  final int length;
  final String lineHash;

  const AppendReceipt({
    required this.path,
    required this.day,
    this.offset = 0,
    this.length = 0,
    this.lineHash = '',
  });
}

/// Entry is one aggregated usage row fed into the projection.
class Entry {
  final String day;
  final String source;
  final String modelRef;
  final String provider;
  final int prompt;
  final int completion;
  final int reasoning;
  final int cacheHit;
  final int cacheMiss;
  final int total;
  final int requests;
  final int turns;

  const Entry({
    required this.day,
    this.source = '',
    this.modelRef = '',
    this.provider = '',
    this.prompt = 0,
    this.completion = 0,
    this.reasoning = 0,
    this.cacheHit = 0,
    this.cacheMiss = 0,
    this.total = 0,
    this.requests = 0,
    this.turns = 0,
  });
}

/// Rollup is one per-day aggregated row from the projection.
class Rollup {
  final String day;
  final String source;
  final String modelRef;
  final String provider;
  final int prompt;
  final int completion;
  final int reasoning;
  final int cacheHit;
  final int cacheMiss;
  final int total;
  final int requests;
  final int turns;

  const Rollup({
    required this.day,
    this.source = '',
    this.modelRef = '',
    this.provider = '',
    this.prompt = 0,
    this.completion = 0,
    this.reasoning = 0,
    this.cacheHit = 0,
    this.cacheMiss = 0,
    this.total = 0,
    this.requests = 0,
    this.turns = 0,
  });
}

/// Status describes projection state for diagnostics.
class Status {
  final int version;
  final bool ready;

  const Status({this.version = 0, this.ready = false});
}

/// Catalog is the usage projection handle. P11 will provide the SQLite
/// implementation; this placeholder keeps the stats package's manager
/// lifecycle testable in isolation.
class Catalog {
  const Catalog();

  /// Opens the projection at [path]. Placeholder: throws
  /// UnimplementedError until the P11 SQLite backend is ported.
  static Future<Catalog> open(String path) async {
    throw UnimplementedError(
        'usagecatalog.Catalog.open requires the P11 projection backend');
  }

  Future<void> reconcileDir(String dir) async {}

  Future<bool> ready(String dir, List<String> days) async => false;

  Future<List<Rollup>> query(
      String fromDay, String toDay, String source) async {
    return const [];
  }

  Future<void> requestReconcileDir(String dir) async {}

  void noteFallback() {}

  Future<void> flush() async {}

  Future<void> close() async {}

  void enqueue(AppendReceipt receipt, Entry entry) {}
}
