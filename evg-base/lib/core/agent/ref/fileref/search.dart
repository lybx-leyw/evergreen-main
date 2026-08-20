/// Port of reasonix/internal/fileref.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

const _skipEntryNames = {
  '.codex',
  '.DS_Store',
  '.git',
  '.npm',
  '.pnpm-store',
  'node_modules',
  'Thumbs.db',
};

const _skipDirNames = {
  'build',
  'dist',
  'target',
  '__pycache__',
  'venv',
  '.venv',
  '.gradle',
  '.next',
  '.nuxt',
  '.svelte-kit',
  '.pytest_cache',
  '.mypy_cache',
  '.tox',
  '.terraform',
  '.dart_tool',
};

const _skipDirPaths = {
  'bin',
  'desktop/frontend/wailsjs',
  'npm/.stage',
  'site/.astro',
  'stage',
  'tmp',
};

const _minQueryLen = 2;
const _maxWalkEntries = 10000;
const _dirQuota = 5;

class SearchResult {
  final String path;
  final bool isDir;

  const SearchResult({required this.path, this.isDir = false});
}

bool skipEntry(String rel, String name, bool isDir) {
  if (_skipEntryNames.contains(name)) return true;
  if (!isDir) return false;
  return _skipDirNames.contains(name) || _skipDirPaths.contains(rel);
}

/// Searches [root] for paths matching [query].
///
/// Returns at most [limit] results, prioritising directory matches, then
/// basename matches, then path-segment matches. Generated/vendor directories
/// are skipped.
List<SearchResult> search(String root, String query, int limit) {
  query = query.trim().toLowerCase();
  if (query.length < _minQueryLen ||
      query.contains('/') ||
      query.contains(r'\') ||
      limit <= 0) {
    return <SearchResult>[];
  }

  final showHidden = query.startsWith('.');
  final basenameHits = <SearchResult>[];
  final segmentHits = <SearchResult>[];
  final dirHits = <SearchResult>[];
  var visited = 0;

  void walk(Directory dir, String rel) {
    if (visited > _maxWalkEntries) return;
    try {
      for (final entity in dir.listSync(followLinks: false)) {
        if (visited > _maxWalkEntries) return;
        visited++;
        final name = p.basename(entity.path);
        final entityRel = rel.isEmpty ? name : '$rel/$name';

        if (entity is Directory) {
          if (skipEntry(entityRel, name, true)) continue;
          if (!showHidden && name.startsWith('.')) continue;
          if (name.toLowerCase().contains(query)) {
            dirHits.add(SearchResult(path: entityRel, isDir: true));
          }
          walk(entity, entityRel);
        } else if (entity is File) {
          if (_skipEntryNames.contains(name)) continue;
          if (!showHidden && name.startsWith('.')) continue;
          final nameLower = name.toLowerCase();
          if (nameLower.contains(query)) {
            basenameHits.add(SearchResult(path: entityRel));
          } else if (_pathSegmentContains(entityRel, query)) {
            segmentHits.add(SearchResult(path: entityRel));
          }
        }
      }
    } on FileSystemException {
      // skip unreadable directories
    }
  }

  walk(Directory(root), '');

  basenameHits.sort((a, b) => a.path.compareTo(b.path));
  segmentHits.sort((a, b) => a.path.compareTo(b.path));
  dirHits.sort((a, b) => a.path.compareTo(b.path));

  final out = <SearchResult>[];
  final nDirs = dirHits.length > _dirQuota ? _dirQuota : dirHits.length;
  out.addAll(dirHits.sublist(0, nDirs));
  var remaining = limit - out.length;
  if (remaining > 0) {
    final take = basenameHits.length > remaining ? remaining : basenameHits.length;
    out.addAll(basenameHits.sublist(0, take));
    remaining = limit - out.length;
  }
  if (remaining > 0) {
    final take = segmentHits.length > remaining ? remaining : segmentHits.length;
    out.addAll(segmentHits.sublist(0, take));
  }
  return out;
}

bool _pathSegmentContains(String relSlash, String queryLower) {
  for (final seg in relSlash.split('/')) {
    if (seg.toLowerCase().contains(queryLower)) return true;
  }
  return false;
}
