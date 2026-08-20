/// Port of reasonix/internal/sysproxy/sysproxy.go.
///
/// Resolves OS-level proxy strings (WinHTTP/IE format) for a target URL. The
/// pure parsing/helper logic is platform-neutral; the actual OS lookup is
/// provided by the platform adapter exported below.
library;

export 'system_other.dart' show forUrl;

/// Splits a WinHTTP/IE proxy list on separators.
List<String> splitList(String s) {
  final out = <String>[];
  final buf = StringBuffer();
  for (final rune in s.runes) {
    if (rune == 0x3B ||
        rune == 0x20 ||
        rune == 0x09 ||
        rune == 0x0A ||
        rune == 0x0D) {
      if (buf.isNotEmpty) {
        out.add(buf.toString());
        buf.clear();
      }
    } else {
      buf.writeCharCode(rune);
    }
  }
  if (buf.isNotEmpty) out.add(buf.toString());
  return out;
}

/// Picks a proxy from a WinHTTP/IE proxy string for [scheme]. The string is
/// either "host:port" (all protocols) or "http=h:p;https=h:p" form.
Uri? parseProxyList(String list, String scheme) {
  String? fallback;
  for (final f in splitList(list)) {
    final eq = f.indexOf('=');
    if (eq >= 0) {
      final before = f.substring(0, eq);
      final after = f.substring(eq + 1);
      if (before.toLowerCase() == scheme.toLowerCase()) {
        return hostProxyUrl(after);
      }
      continue;
    }
    fallback ??= f;
  }
  if (fallback != null) return hostProxyUrl(fallback);
  return null;
}

Uri? hostProxyUrl(String hostport) {
  hostport = hostport.trim();
  final scheme = hostport.indexOf('://');
  if (scheme >= 0) hostport = hostport.substring(scheme + 3);
  if (hostport.isEmpty) return null;
  return Uri.parse('http://$hostport');
}

/// Reports whether [host] matches a WinINET proxy-bypass entry. `<local>`
/// matches dotless (intranet) hosts; a leading `*` is a suffix wildcard.
bool bypassed(String host, String bypass) {
  host = host.trim().toLowerCase();
  if (host.isEmpty) return false;
  for (var e in splitList(bypass)) {
    e = e.toLowerCase();
    if (e == '<local>') {
      if (!host.contains('.')) return true;
    } else if (e.startsWith('*')) {
      if (host.endsWith(e.substring(1))) return true;
    } else if (host == e) {
      return true;
    }
  }
  return false;
}
