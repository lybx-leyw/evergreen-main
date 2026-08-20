/// Port of reasonix/internal/netclient/dialer.go.
///
/// Opens a raw TCP stream under the same proxy policy netclient applies to
/// HTTP. Direct dialing is fully implemented on `dart:io` sockets; the
/// SOCKS5 / HTTP-CONNECT tunnel paths are adapter stubs (see notes) because
/// the Dart runtime here does not yet bind the corresponding protocol
/// implementations. Resolution (which proxy applies to which host) is real
/// and shared with [proxyFunc].
library;

import 'dart:io';

import 'package:evergreen_base/core/agent/ref/netclient/netclient.dart';

/// Opens a raw TCP stream to [address] (host:port). [network] mirrors Go's
/// dial network ("tcp"); context cancellation is not modeled — use a
/// [Duration] deadline at the call site if needed.
abstract class StreamDialer {
  Future<Socket> dialContext(String network, String address);
}

/// Adapts a function to [StreamDialer].
typedef DialerFunc = Future<Socket> Function(String network, String address);

class FuncStreamDialer implements StreamDialer {
  final DialerFunc _fn;
  FuncStreamDialer(this._fn);

  @override
  Future<Socket> dialContext(String network, String address) =>
      _fn(network, address);
}

/// Builds a [StreamDialer] for [spec]. Off/env/auto with no applicable proxy
/// dial directly; socks5/socks5h and http/https would dial through the proxy,
/// but those tunnel paths are adapter stubs for now.
StreamDialer newStreamDialer(ProxySpec spec) {
  final resolver = proxyFunc(spec);
  final base = _baseDialer();
  if (resolver == null) return FuncStreamDialer(base);
  return FuncStreamDialer((network, address) async {
    // proxyFunc keys off a request URL; synthesize one for the target so
    // scheme-agnostic TCP dials reuse the exact NoProxy/DirectHosts logic.
    final host = _splitHost(address);
    final probe = Uri(scheme: 'https', host: host);
    final proxyUrl = resolver(probe);
    if (proxyUrl == null) return base(network, address);
    switch (proxyUrl.scheme.toLowerCase()) {
      case 'socks5':
      case 'socks5h':
        throw UnsupportedError(
            'netclient: SOCKS5 stream dial is an adapter stub (dialer.dart)');
      case 'http':
      case 'https':
        throw UnsupportedError(
            'netclient: HTTP CONNECT stream dial is an adapter stub (dialer.dart)');
      default:
        throw StateError(
            'netclient: unsupported proxy scheme "${proxyUrl.scheme}" '
            'for stream dial');
    }
  });
}

/// Direct dialer with the same 30s timeouts as Go's `net.Dialer` base.
DialerFunc _baseDialer() {
  return (network, address) async {
    final (host, port) = _splitHostPort(address);
    return Socket.connect(host, port, timeout: const Duration(seconds: 30));
  };
}

/// Splits "host:port" (with optional IPv6 brackets) into host and port.
(String, int) _splitHostPort(String address) {
  if (address.startsWith('[')) {
    final close = address.indexOf(']');
    if (close > 0) {
      final host = address.substring(1, close);
      final rest = address.substring(close + 1);
      if (rest.startsWith(':')) {
        return (host, int.parse(rest.substring(1)));
      }
    }
    throw ArgumentError('netclient: invalid address "$address"');
  }
  final colon = address.lastIndexOf(':');
  if (colon <= 0) {
    throw ArgumentError('netclient: address "$address" has no port');
  }
  return (address.substring(0, colon), int.parse(address.substring(colon + 1)));
}

/// Returns just the host part of [address] for a synthesized probe URL.
String _splitHost(String address) {
  try {
    return _splitHostPort(address).$1;
  } on ArgumentError {
    return address;
  }
}
