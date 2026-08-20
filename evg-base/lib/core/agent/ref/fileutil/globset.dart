/// Port of reasonix/internal/fileutil/globset.
library;

import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

class GlobSet {
  final List<String> _include;
  final List<String> _exclude;

  GlobSet._(this._include, this._exclude);

  static GlobSet create(List<String> include, List<String> exclude) {
    return GlobSet._(
      _normalizePatterns(include),
      _normalizePatterns(exclude),
    );
  }

  bool match(String path) {
    final normalized = normalizeSlashPath(path);
    var included = _include.isEmpty;
    for (final pattern in _include) {
      if (_matchGlob(normalized, pattern)) {
        included = true;
        break;
      }
    }
    if (!included) return false;
    for (final pattern in _exclude) {
      if (_matchGlob(normalized, pattern)) return false;
    }
    return true;
  }

  bool _matchGlob(String path, String pattern) {
    if (pattern.startsWith('**/')) {
      final tail = pattern.substring(3);
      final glob = Glob(tail, context: p.posix, recursive: false);
      if (glob.matches(path)) return true;
      // Match at any depth.
      final parts = path.split('/');
      for (var i = 0; i < parts.length; i++) {
        final sub = parts.sublist(i).join('/');
        if (Glob(tail, context: p.posix, recursive: false).matches(sub)) {
          return true;
        }
      }
      return false;
    }
    return Glob(pattern, context: p.posix, recursive: false).matches(path);
  }
}

String normalizeSlashPath(String path) {
  return p.posix.normalize(path.replaceAll(r'\', '/'));
}

List<String> _normalizePatterns(List<String> patterns) {
  return patterns
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .map(normalizeSlashPath)
      .toList();
}

bool matchSlashGlob(String path, String pattern) {
  final set = GlobSet.create([pattern], []);
  return set.match(path);
}
