part of 'stats.dart';

/// Manages the optional usage projection for one stats directory. The
/// catalog itself is a P11 target; this mirrors the Go lifecycle (generation
/// fencing, close fences in-flight opens, restart after close) so the
/// surrounding stats logic is complete and the lifecycle test translates
/// faithfully. Without a loaded catalog every query uses the JSONL fallback.
class UsageManager {
  usagecatalog.Catalog? catalog;
  bool _opening = false;
  Future<void>? _openDone;
  bool _cancelled = false;
  int _generation = 0;
  final String dir;

  /// Injectable open seam (mirrors Go's `open func(context.Context, string)`).
  Future<usagecatalog.Catalog> Function(String path)? open;

  UsageManager(this.dir);

  /// Whether this directory is the authoritative stats directory. Without a
  /// config layer (P10), the placeholder accepts any non-empty directory.
  static bool sameUsageDirectory(String left, String right) {
    final l = _absClean(left);
    final r = _absClean(right);
    return l != null && r != null && l == r;
  }

  static String? _absClean(String s) {
    try {
      return p.normalize(p.absolute(s));
    } catch (_) {
      return null;
    }
  }

  /// Starts the projection open in the background. A catalog already loaded
  /// (or an open in flight) is left alone; a close bumps the generation so a
  /// stale open never publishes.
  void start() {
    if (catalog != null || _opening) return;
    _generation++;
    final generation = _generation;
    _opening = true;
    _cancelled = false;
    final openCatalog = open ?? (path) => usagecatalog.Catalog.open(path);
    _openDone = _openGeneration(generation, dir, openCatalog);
  }

  Future<void> _openGeneration(int generation, String dir,
      Future<usagecatalog.Catalog> Function(String) openCatalog) async {
    usagecatalog.Catalog? loaded;
    Object? err;
    try {
      loaded = await openCatalog('');
    } catch (e) {
      err = e;
    }
    var stale = generation != _generation || _cancelled;
    if (loaded != null) {
      if (err == null && !stale) {
        catalog = loaded;
        await loaded.reconcileDir(dir);
      } else {
        await loaded.close();
      }
    }
    _opening = false;
    _openDone = null;
  }

  Future<void> close() async {
    _generation++;
    _cancelled = true;
    final openDone = _openDone;
    final existing = catalog;
    catalog = null;
    // Match Go's close: a close fences an in-flight open and waits for it to
    // exit before returning, so a stale catalog can never be published after
    // shutdown.
    if (openDone != null) {
      await openDone;
    }
    if (existing != null) {
      await existing.close();
    }
  }
}

final Map<String, UsageManager> _usageManagers = {};

/// Returns the process-local usage manager for [dir] if it is the
/// authoritative stats directory, starting its background open.
UsageManager? managerForUsage(String dir) {
  final trimmed = dir.trim();
  if (trimmed.isEmpty) return null;
  return _usageManagers.putIfAbsent(trimmed, () => UsageManager(trimmed))
    ..start();
}

/// Returns an already-started manager without creating background work.
UsageManager? existingUsageManager(String dir) {
  final trimmed = dir.trim();
  if (trimmed.isEmpty) return null;
  return _usageManagers[trimmed];
}

/// Closes every process-local usage projection. Desktop shutdown and test
/// isolation call this so temp-dir catalog files can be deleted.
Future<void> closeUsageCatalogs() async {
  final managers = List.of(_usageManagers.values);
  _usageManagers.clear();
  for (final m in managers) {
    await m.close();
  }
}
