/// Port of reasonix/internal/fileutil/atomicwrite.go.
library;

import 'dart:async';
import 'dart:io';

/// Optional crash-consistency fault-injection hook.
void Function(String op, String path)? crashPoint;

void crash(String op, String path) {
  crashPoint?.call(op, path);
}

Future<void> atomicWriteFile(String path, List<int> data, int perm) async {
  return _atomicWriteFile(path, data, perm, true);
}

Future<void> atomicWriteFileStrict(String path, List<int> data, int perm) async {
  return _atomicWriteFile(path, data, perm, false);
}

Future<void> _atomicWriteFile(
    String path, List<int> data, int perm, bool allowCrossDeviceCopy) async {
  crash('atomic-write', path);
  final tmpPath = await _writeAtomicTemp(path, data, perm);
  try {
    await _replaceFile(tmpPath, path, allowCrossDeviceCopy);
  } catch (e) {
    try {
      File(tmpPath).deleteSync();
    } on FileSystemException {
      // ignore
    }
    rethrow;
  }
  if (!allowCrossDeviceCopy) {
    // Best-effort parent-dir sync is ignored in Dart portable code.
    await _syncParentDir(path);
  }
}

Future<String> _writeAtomicTemp(String path, List<int> data, int perm) async {
  final dir = File(path).parent.path;
  final dirPerm = (perm & 0x077) == 0 ? 0o700 : 0o755;
  await Directory(dir).create(recursive: true);
  final tmp = File('${dir}${Platform.pathSeparator}.atomic-${DateTime.now().microsecondsSinceEpoch}.tmp');
  final raf = await tmp.open(mode: FileMode.write);
  try {
    await raf.writeFrom(data);
    await raf.flush();
    await raf.close();
    await tmp.setLastAccessed(DateTime.now()); // no chmod in Dart; best effort
  } catch (e) {
    await raf.close();
    rethrow;
  }
  return tmp.path;
}

Future<void> _replaceFile(String tmp, String dest, bool allowCrossDeviceCopy) async {
  const maxRetries = 12;
  const baseDelay = Duration(milliseconds: 20);
  for (var attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      await File(tmp).rename(dest);
      return;
    } on FileSystemException catch (e) {
      if (_renameCrossesDevice(e)) {
        if (!allowCrossDeviceCopy) rethrow;
        try {
          await File(tmp).copy(dest);
          await File(tmp).delete();
          return;
        } on FileSystemException {
          rethrow;
        }
      }
      if (attempt == maxRetries || !File(tmp).existsSync()) {
        rethrow;
      }
      await Future.delayed(baseDelay * (attempt + 1));
    }
  }
}

bool _renameCrossesDevice(FileSystemException e) {
  final msg = e.osError?.message ?? e.message;
  return msg.toLowerCase().contains('cross-device') ||
      msg.toLowerCase().contains('not same device') ||
      msg.toLowerCase().contains('exdev');
}

Future<void> _syncParentDir(String path) async {
  final dir = File(path).parent;
  try {
    final raf = await dir.open();
    await raf.flush();
    await raf.close();
  } on FileSystemException {
    // ignore unsupported platform errors
  }
}

Future<void> atomicCreateFile(String path, List<int> data, int perm) async {
  final tmpPath = await _writeAtomicTemp(path, data, perm);
  try {
    await File(tmpPath).rename(path);
  } catch (e) {
    try {
      File(tmpPath).deleteSync();
    } on FileSystemException {
      // ignore
    }
    rethrow;
  }
}

Future<void> atomicOverwriteFile(String path, List<int> data, int defaultPerm) async {
  var target = path;
  try {
    final resolved = await Link(path).target();
    if (resolved != null) target = resolved;
  } on FileSystemException {
    // not a symlink
  }
  var perm = defaultPerm;
  try {
    final info = await File(target).stat();
    if (info.type == FileSystemEntityType.file) {
      // Dart does not expose mode bits; keep defaultPerm.
    }
  } on FileSystemException {
    // file absent
  }
  return atomicWriteFile(target, data, perm);
}

Future<void> replaceFile(String tmp, String dest) async {
  crash('replace', dest);
  return _replaceFile(tmp, dest, true);
}

Future<void> claimRename(String src, String dst) async {
  return _replaceFile(src, dst, false);
}
