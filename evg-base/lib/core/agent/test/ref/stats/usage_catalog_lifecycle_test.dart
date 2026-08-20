/// Port of reasonix/internal/stats/usage_catalog_lifecycle_test.go.
///
/// Translation notes:
/// - Go uses a real usagecatalog.Catalog (SQLite) opened at a temp path. P1
///   keeps usagecatalog as a minimal placeholder, so this test injects a fake
///   catalog and verifies the same lifecycle contract: close fences an
///   in-flight open, a stale open is never published, and a fresh start after
///   close can publish a new catalog.
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../../ref/stats/stats.dart' as stats;
import '../../../ref/usagecatalog/catalog.dart' as usagecatalog;

void main() {
  test('usage manager close fences open and allows restart', () async {
    final tmp = Directory.systemTemp.createTempSync('stats-lifecycle-');
    addTearDown(() {
      try {
        tmp.deleteSync(recursive: true);
      } on FileSystemException {
        // On Windows an open handle may still be held; test cleanup is best-effort.
      }
    });

    final manager = stats.UsageManager(tmp.path);
    final databasePath = p.join(tmp.path, 'usage.sqlite');
    final started = Completer<void>();
    final release = Completer<void>();
    manager.open = (path) async {
      started.complete();
      await release.future;
      return _FakeCatalog(databasePath);
    };

    manager.start(tmp.path);
    await started.future;

    var closed = false;
    final closing = manager.close().then((_) {
      closed = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse,
        reason: 'close must wait for the in-flight open to exit');
    expect(manager.catalog, isNull);

    release.complete();
    await closing;
    expect(closed, isTrue);
    expect(manager.catalog, isNull,
        reason: 'stale open must not publish a catalog after close');

    final reopened = Completer<void>();
    final second = _FakeCatalog(databasePath);
    manager.open = (path) async {
      reopened.complete();
      return second;
    };
    manager.start(tmp.path);
    await reopened.future;
    await Future<void>.delayed(Duration.zero);
    expect(manager.catalog, same(second),
        reason: 'manager should publish the restarted usage catalog');

    await manager.close();
    expect(second.closed, isTrue);
  });
}

class _FakeCatalog extends usagecatalog.Catalog {
  final String path;
  bool closed = false;

  _FakeCatalog(this.path);

  @override
  Future<void> reconcileDir(String dir) async {}

  @override
  Future<void> close() async {
    closed = true;
  }
}
