import 'dart:io';

import 'package:evergreen_base/core/agent/ref/filelock/filelock.dart' as filelock;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('acquire and release exclusive lock', () async {
    final tmp = Directory.systemTemp.createTempSync('filelock-test-');
    try {
      final lock = await filelock.FileLock.acquire(
          p.join(tmp.path, 'test.lock'));
      expect(lock, isNotNull);
      await lock!.release();
    } finally {
      tmp.deleteSync(recursive: true);
    }
  });

  test('second exclusive lock on same file times out', () async {
    final tmp = Directory.systemTemp.createTempSync('filelock-test-');
    final path = p.join(tmp.path, 'test.lock');
    final first = await filelock.FileLock.acquire(path);
    expect(first, isNotNull);
    final second = await filelock.FileLock.acquire(path,
        timeout: const Duration(milliseconds: 50));
    expect(second, isNull);
    await first!.release();
    tmp.deleteSync(recursive: true);
  });
}
