/// Port of reasonix/internal/netclient/netclient.go.
///
/// Builds HTTP clients and proxy resolvers that share the user-facing proxy
/// settings. The Go implementation returns `*http.Client` / `*http.Transport`;
/// the Dart port keeps the pure proxy-resolution core ([proxyFunc],
/// [customProxyUrl], [summary], ...) and models the client/transport as a
/// thin config ([Transport]) so callers can wire their own HTTP stack.
library;

import 'dart:io' show Platform;

import 'package:evergreen_base/core/agent/ref/sysproxy/sysproxy.dart'
    as sysproxy;

/// Proxy mode constants (mirror of Go's `ModeAuto/Env/Custom/Off`).
const String modeAuto = 'auto';
const String modeEnv = 'env';
const String modeCustom = 'custom';
const String modeOff = 'off';

/// Resolves the proxy URL for a request URL; `null` means direct.
typedef ProxyResolver = Uri? Function(Uri request);

/// The resolved proxy configuration used by network clients. [url] is an
/// advanced override; otherwise [type]/[server]/[port]/[username]/[password]
/// are composed into a proxy URL. [noProxy] is honored for custom proxies.
/// [directHosts] always bypass the proxy in every mode.
class ProxySpec {
  final String mode;
  final String url;
  final String noProxy;
  final String type;
  final String server;
  final int port;
  final String username;
  final String password;
  final List<String> directHosts;

  const ProxySpec({
    this.mode = modeAuto,
    this.url = '',
    this.noProxy = '',
    this.type = '',
    this.server = '',
    this.port = 0,
    this.username = '',
    this.password = '',
    this.directHosts = const [],
  });
}

/// Timeout knobs for the transport. Durations of zero mean "keep the default"
/// (mirror of Go's zero-valued `time.Duration` fields).
class TransportOptions {
  final Duration dialTimeout;
  final Duration keepAlive;
  final Duration tlsHandshakeTimeout;
  final Duration responseHeaderTimeout;
  final bool forceIPv4;

  const TransportOptions({
    this.dialTimeout = Duration.zero,
    this.keepAlive = Duration.zero,
    this.tlsHandshakeTimeout = Duration.zero,
    this.responseHeaderTimeout = Duration.zero,
    this.forceIPv4 = false,
  });
}

/// Maps empty and unknown modes to auto, preserving a fail-open default for
/// older configs.
String normalizeMode(String mode) {
  switch (mode.trim().toLowerCase()) {
    case modeEnv:
      return modeEnv;
    case modeCustom:
      return modeCustom;
    case modeOff:
      return modeOff;
    default:
      return modeAuto;
  }
}

/// Reports whether [spec] can be used. Non-custom modes have no required
/// fields; custom needs either a complete URL or a structured server+port.
String? validate(ProxySpec spec) {
  try {
    proxyFunc(spec);
    return null;
  } on ProxyConfigException catch (e) {
    return e.message;
  }
}

/// Returns the per-request proxy resolver for [spec], or null when the mode is
/// off (direct). Throws [ProxyConfigException] on invalid custom config.
ProxyResolver? proxyFunc(ProxySpec spec, {Map<String, String>? environment}) {
  final base = baseProxyFunc(spec, environment: environment);
  return withDirectHosts(base, spec.directHosts);
}

/// Builds a proxy resolver from [spec] without applying DirectHosts.
ProxyResolver? baseProxyFunc(ProxySpec spec,
    {Map<String, String>? environment}) {
  switch (normalizeMode(spec.mode)) {
    case modeOff:
      return null;
    case modeCustom:
      final u = customProxyUrl(spec);
      final noProxy = spec.noProxy.trim();
      return (Uri request) => _noProxyMatches(request, noProxy) ? null : u;
    case modeEnv:
      return environmentProxyFunc(environment: environment);
    default:
      return autoProxyFunc(environment: environment);
  }
}

/// Makes the listed hosts (and their subdomains) bypass the proxy in every
/// mode.
ProxyResolver? withDirectHosts(ProxyResolver? pf, List<String> hosts) {
  if (pf == null || hosts.isEmpty) return pf;
  final norm = <String>[];
  for (final h in hosts) {
    final t = h.trim().toLowerCase();
    if (t.isNotEmpty) norm.add(t);
  }
  return (Uri request) {
    final host = request.host.toLowerCase();
    for (final h in norm) {
      if (host == h || host.endsWith('.$h')) return null;
    }
    return pf(request);
  };
}

/// Resolver from HTTP(S)_PROXY / NO_PROXY environment variables. [environment]
/// defaults to [Platform.environment] and can be injected in tests.
ProxyResolver environmentProxyFunc({Map<String, String>? environment}) {
  final env = environment ?? Platform.environment;
  String? pick(String upper, String lower) {
    final v = env[upper] ?? env[lower];
    if (v == null || v.trim().isEmpty) return null;
    return v;
  }

  final httpProxy = pick('HTTP_PROXY', 'http_proxy');
  final httpsProxy = pick('HTTPS_PROXY', 'https_proxy');
  final noProxy = pick('NO_PROXY', 'no_proxy') ?? '';
  return (Uri request) {
    if (_noProxyMatches(request, noProxy)) return null;
    final scheme = request.scheme.toLowerCase();
    final raw = scheme == 'https' ? httpsProxy : httpProxy;
    if (raw == null || raw.isEmpty) return null;
    return Uri.tryParse(raw);
  };
}

/// Resolver that honors environment proxy vars first, then falls back to the
/// OS system proxy so corporate Windows machines work without manual
/// HTTP_PROXY setup. Non-Windows resolves to env-only.
ProxyResolver autoProxyFunc({Map<String, String>? environment}) {
  final fromEnv = environmentProxyFunc(environment: environment);
  return (Uri request) {
    final u = fromEnv(request);
    if (u != null) return u;
    return sysproxy.forUrl(request);
  };
}

/// Composes the custom proxy URL from [spec]: either the full [url] override
/// or type/server/port/credentials.
Uri customProxyUrl(ProxySpec spec) {
  final raw = spec.url.trim();
  if (raw.isNotEmpty) {
    final u = Uri.tryParse(raw);
    if (u == null) {
      throw ProxyConfigException('network proxy_url: $raw');
    }
    validateProxyUrl(u);
    return u;
  }
  var typ = spec.type.trim().toLowerCase();
  if (typ.isEmpty) typ = 'http';
  if (!const {'http', 'https', 'socks5', 'socks5h'}.contains(typ)) {
    throw ProxyConfigException(
        'network proxy type "${spec.type}": must be http|https|socks5|socks5h');
  }
  final server = spec.server.trim();
  if (server.isEmpty) {
    throw ProxyConfigException(
        'network proxy server is required when proxy_mode = custom');
  }
  if (spec.port <= 0 || spec.port > 65535) {
    throw ProxyConfigException('network proxy port must be 1..65535');
  }
  var host = server;
  if (host.startsWith('[') && host.endsWith(']')) {
    host = host.substring(1, host.length - 1);
  }
  final user = spec.username.isEmpty
      ? null
      : (spec.password.isEmpty
          ? spec.username
          : '${spec.username}:${spec.password}');
  return Uri(scheme: typ, host: host, port: spec.port, userInfo: user ?? '');
}

/// Validates a proxy URL's scheme and host.
void validateProxyUrl(Uri u) {
  if (!const {'http', 'https', 'socks5', 'socks5h'}
      .contains(u.scheme.toLowerCase())) {
    throw ProxyConfigException(
        'network proxy_url scheme "${u.scheme}": must be http|https|socks5|socks5h');
  }
  if (u.host.isEmpty) {
    throw ProxyConfigException('network proxy_url host is required');
  }
}

/// Returns a redacted, user-facing description for diagnostics.
String summary(ProxySpec spec) {
  switch (normalizeMode(spec.mode)) {
    case modeOff:
      return 'off (direct)';
    case modeEnv:
      return 'env';
    case modeCustom:
      try {
        return 'custom (${redactUrl(customProxyUrl(spec))})';
      } on ProxyConfigException {
        return 'custom (invalid)';
      }
    default:
      return 'auto (env)';
  }
}

/// Redacts the password from a proxy URL, keeping the username if present.
String redactUrl(Uri u) {
  if (u.userInfo.isEmpty) return u.toString();
  final name = u.userInfo.split(':').first;
  if (name.isEmpty) return u.replace(userInfo: '').toString();
  return u.replace(userInfo: name).toString();
}

/// Models the transport configuration: the resolved proxy plus timeout knobs.
/// Callers wire their own HTTP stack on top (adapter for Go's `*http.Transport`).
class Transport {
  final ProxyResolver? proxy;
  final TransportOptions options;

  const Transport(this.proxy, this.options);
}

/// Returns a transport config with the proxy behavior for [spec] applied.
Transport newTransport(ProxySpec spec, TransportOptions options) {
  final resolver = proxyFunc(spec);
  return Transport(resolver, options);
}

/// Adapter for Go's `NewHTTPClient`: returns a transport config the caller
/// wraps in its own HTTP client. Pure proxy resolution is identical.
Transport newHttpClient(ProxySpec spec, TransportOptions options) {
  return newTransport(spec, options);
}

/// Thrown for invalid proxy configuration (mirror of Go's `error` returns).
class ProxyConfigException implements Exception {
  final String message;
  ProxyConfigException(this.message);

  @override
  String toString() => message;
}

/// Simplified no_proxy matching (host, .domain suffix, *, <local>).
bool _noProxyMatches(Uri request, String noProxy) {
  if (noProxy.trim().isEmpty) return false;
  final host = request.host.toLowerCase();
  for (final raw in noProxy.split(',')) {
    var entry = raw.trim().toLowerCase();
    if (entry.isEmpty) continue;
    if (entry == '*') return true;
    if (entry == '<local>') {
      if (!host.contains('.')) return true;
      continue;
    }
    if (entry.startsWith('.')) entry = entry.substring(1);
    if (host == entry || host.endsWith('.$entry')) return true;
  }
  return false;
}
