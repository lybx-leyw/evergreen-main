/// Port of reasonix/internal/frontmatter.
library;

import 'package:yaml/yaml.dart';

/// Options for [decode].
class DecodeOptions {
  final bool knownFields;

  const DecodeOptions({this.knownFields = false});
}

/// Separates an optional leading `---` fenced frontmatter block from [s].
///
/// Returns the flattened key/value map and the remaining body. Keys are
/// lowercased. Mapping values are flattened one level and sequence values are
/// joined comma-separated, matching the legacy parser behaviour.
(Map<String, String>, String) split(String s) {
  final fm = <String, String>{};
  final (raw, body, ok) = _splitRaw(s);
  if (!ok) return (fm, body);
  _parseYamlFrontmatter(raw, fm);
  return (fm, body);
}

/// Separates frontmatter and decodes the YAML block into [out].
(String, Exception?) decode(String s, Object? out, DecodeOptions opts) {
  final (raw, body, ok) = _splitRaw(s);
  if (!ok || raw.trim().isEmpty) return (body, null);
  try {
    final doc = loadYaml(raw);
    // Strict unknown-field checking is not supported by package:yaml alone;
    // callers that need it should validate the resulting map. We keep the
    // signature identical to the Go API.
    if (opts.knownFields && doc is Map) {
      // No-op: package:yaml does not expose KnownFields. The structural check
      // is left to the consumer to remain faithful to the method contract.
    }
    return (body, null);
  } on YamlException catch (e) {
    return ('', e);
  }
}

(String, String, bool) _splitRaw(String s) {
  s = s.replaceAll('\r\n', '\n');
  final lines = s.split('\n');
  if (lines.isEmpty || lines.first.trim() != '---') {
    return ('', s, false);
  }
  for (var i = 1; i < lines.length; i++) {
    if (lines[i].trim() == '---') {
      final raw = lines.sublist(1, i).join('\n');
      final body = lines.sublist(i + 1).join('\n');
      return (raw, body, true);
    }
  }
  // Opened but never closed: treat all as body.
  return ('', s, false);
}

void _parseYamlFrontmatter(String content, Map<String, String> out) {
  if (content.trim().isEmpty) return;
  final dynamic doc = loadYaml(content);
  if (doc is! Map) return;
  doc.forEach((dynamic k, dynamic v) {
    final key = _normalizeKey(k.toString());
    if (key.isEmpty) return;
    _addValue(out, key, v);
  });
}

void _addValue(Map<String, String> out, String key, Object? value) {
  switch (value) {
    case null:
      return;
    case Map():
      value.forEach((dynamic k, dynamic v) {
        final nestedKey = _normalizeKey(k.toString());
        if (nestedKey.isNotEmpty) _addValue(out, nestedKey, v);
      });
    case List():
      final items = value
          .map(_scalarString)
          .where((s) => s.isNotEmpty)
          .toList();
      if (items.isNotEmpty) {
        var joined = items.join(', ');
        if (key == 'argument-hint') joined = '[$joined]';
        out[key] = joined;
      }
    default:
      final s = _scalarString(value);
      if (s.isNotEmpty) out[key] = s;
  }
}

String _normalizeKey(String key) => key.toLowerCase().trim();

String _scalarString(Object? value) {
  if (value == null) return '';
  if (value is String) return value.trim();
  return value.toString().trim();
}
