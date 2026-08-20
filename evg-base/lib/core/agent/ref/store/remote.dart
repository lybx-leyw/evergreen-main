/// Port of reasonix/internal/store/remote.go.
library;

import 'dart:convert';

// import 'package:crypto/crypto.dart';

const remoteDirName = 'remote';
const remoteBinDirName = 'bin';

String remoteWorkspaceSlug(String remotePath) {
  var clean = remotePath;
  if (clean.endsWith('/')) {
    clean = clean.substring(0, clean.length - 1);
  }
  var stem = clean.replaceAll('/', '-').replaceAll(':', '-');
  stem = stem.replaceAll(RegExp(r'^-+|\-+$'), '');
  if (stem.isEmpty) stem = 'root';
  final hash = fnv1a64(utf8.encode(clean));
  final sum = hash.toRadixString(16).padLeft(16, '0');
  stem = _boundRemoteComponent(stem, 180);
  return '$stem-$sum';
}

String remoteServeStateName(String slug) => 'serve-$slug.json';
String remoteServeTokenName(String slug) => 'serve-$slug.token';
String remoteServeLogName(String slug) => 'serve-$slug.log';
String remoteServePortName(String slug) => 'serve-$slug.port';
String remoteServePidName(String slug) => 'serve-$slug.pid';
String remoteServeLockName(String slug) => 'serve-$slug.lock';

String _boundRemoteComponent(String s, int maxLen) {
  if (maxLen <= 0 || s.length <= maxLen) return s;
  final hash = fnv1a64(utf8.encode(s));
  final sum = hash.toRadixString(16).padLeft(16, '0');
  final budget = maxLen - 17;
  if (budget <= 0) return sum;
  var prefix = s.substring(0, budget);
  while (prefix.isNotEmpty && !utf8.decode(prefix.codeUnits, allowMalformed: true).contains(prefix)) {
    // Truncate to last valid UTF-8 boundary using rune-safe trim.
    prefix = prefix.substring(0, prefix.length - 1);
  }
  return '$prefix-$sum';
}

/// FNV-1a 64-bit hash.
int fnv1a64(List<int> bytes) {
  const basis = 0xcbf29ce484222325;
  const prime = 0x100000001b3;
  var hash = basis;
  for (final b in bytes) {
    hash ^= b;
    hash = (hash * prime) & 0xFFFFFFFFFFFFFFFF;
  }
  return hash;
}
