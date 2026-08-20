/// Port of reasonix/internal/textutil.
library;

import 'package:characters/characters.dart';

/// Returns the longest prefix that fits [maxBytes] without splitting a grapheme
/// cluster.
///
/// If a single cluster is larger than [maxBytes] the whole cluster is still
/// returned so callers never emit malformed user-visible text.
String fitGraphemeBytes(String text, int maxBytes) {
  if (maxBytes <= 0) return '';

  final it = text.characters.iterator;
  var used = 0;
  var end = 0;
  while (it.moveNext()) {
    final cluster = it.current;
    final size = cluster.length;
    if (used > 0 && used + size > maxBytes) break;
    end += size;
    used += size;
    if (used >= maxBytes) break;
  }
  if (end > 0) return text.substring(0, end);

  // A single cluster is oversized: return it whole rather than return nothing.
  final first = text.characters.iterator;
  if (!first.moveNext()) return '';
  return first.current;
}

/// Truncates [s] to at most [max] grapheme clusters, counting the [suffix]
/// inside the budget when used.
String clipGraphemes(String s, int max, String suffix) {
  if (max < 1) max = 1;
  final clusters = _collectGraphemes(s, max + 1);
  if (clusters.length <= max && clusters.length == _countGraphemes(s)) {
    return s;
  }
  final suffixClusters = _countGraphemes(suffix);
  var keep = max - suffixClusters;
  if (keep < 1) {
    keep = 1;
    suffix = '';
  }
  if (keep > clusters.length) keep = clusters.length;
  return clusters.take(keep).join() + suffix;
}

/// Truncates [s] to at most [max] grapheme clusters, appending [suffix]
/// outside the budget.
String truncateGraphemes(String s, int max, String suffix) {
  if (max < 0) max = 0;
  final clusters = _collectGraphemes(s, max + 1);
  if (clusters.length <= max && clusters.length == _countGraphemes(s)) {
    return s;
  }
  if (max > clusters.length) max = clusters.length;
  return clusters.take(max).join() + suffix;
}

List<String> _collectGraphemes(String s, int limit) {
  if (limit < 1) return <String>[];
  final out = <String>[];
  final it = s.characters.iterator;
  while (it.moveNext()) {
    out.add(it.current);
    if (out.length >= limit) break;
  }
  return out;
}

int _countGraphemes(String s) {
  var count = 0;
  final it = s.characters.iterator;
  while (it.moveNext()) count++;
  return count;
}
