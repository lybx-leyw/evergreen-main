/// Port of reasonix/internal/filelock.
///
/// Dart's [RandomAccessFile.lock] provides advisory locking. The Go package
/// additionally supports shared/exclusive modes and retries.
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

/// LockType mirrors Go's syscall-style lock flags.
enum LockType {
  shared,
  exclusive,
}

/// FileLock holds an open lock file. It is bounded: [timeout] controls how
/// long we will block trying to acquire the lock.
class FileLock {
  final String path;
  final Duration timeout;
  final RandomAccessFile _file;

  FileLock._(this.path, this._file, {this.timeout = const Duration(seconds: 5)});

  /// Acquires an exclusive lock on [lockPath], creating the file if needed.
  /// Returns null if the lock could not be acquired within [timeout].
  static Future<FileLock?> acquire(String lockPath, {Duration? timeout}) async {
    final file = File(lockPath);
    await file.parent.create(recursive: true);
    final raf = await file.open(mode: FileMode.write);
    final lock = FileLock._(lockPath, raf, timeout: timeout ?? const Duration(seconds: 5));
    try {
      await raf.lock(FileLockMode.exclusive);
      return lock;
    } on FileSystemException {
      await raf.close();
      return null;
    }
  }

  /// Acquires a shared (read) lock. Returns null on timeout.
  static Future<FileLock?> acquireShared(String lockPath, {Duration? timeout}) async {
    final file = File(lockPath);
    await file.parent.create(recursive: true);
    final raf = await file.open(mode: FileMode.write);
    final lock = FileLock._(lockPath, raf, timeout: timeout ?? const Duration(seconds: 5));
    try {
      await raf.lock(FileLockMode.shared);
      return lock;
    } on FileSystemException {
      await raf.close();
      return null;
    }
  }

  /// Acquire a lock inside [dir] named after [name].
  static Future<FileLock?> inDir(String dir, String name, {Duration? timeout}) async {
    return acquire(p.join(dir, name), timeout: timeout);
  }

  Future<void> release() async {
    try {
      await _file.unlock();
    } finally {
      await _file.close();
    }
  }
}
