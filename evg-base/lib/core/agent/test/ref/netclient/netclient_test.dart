/// Port of reasonix/internal/netclient/netclient_test.go.
///
/// The Go tests exercise real HTTP transports (httptest servers, CONNECT
/// tunnels, SOCKS proxies). Per the migration convention, this Dart port
/// keeps the same observable contracts at the proxy-resolution level:
/// which proxy URL (or direct) a given mode/spec resolves for a request.
/// Environment-dependent cases inject an explicit [Map] instead of
/// mutating process env (Go's `t.Setenv`).
library;

import 'package:evergreen_base/core/agent/ref/netclient/netclient.dart'
    as netclient;
import 'package:test/test.dart';

Uri mustUrl(String s) => Uri.parse(s);

void main() {
  test('custom proxy builds socks5 URL', () {
    final resolver = netclient.proxyFunc(netclient.ProxySpec(
      mode: netclient.modeCustom,
      type: 'socks5',
      server: '127.0.0.1',
      port: 7890,
      username: 'user',
      password: 'secret',
    ))!;
    final got = resolver(mustUrl('https://api.deepseek.com/chat/completions'))!;
    expect(got.scheme, 'socks5');
    expect(got.host, '127.0.0.1');
    expect(got.port, 7890);
    // Go asserts url.User.Password() == "secret"; Dart keeps user:pass in
    // userInfo.
    expect(got.userInfo.split(':').last, 'secret');
  });

  test('custom proxy honors no_proxy', () {
    final resolver = netclient.proxyFunc(netclient.ProxySpec(
      mode: netclient.modeCustom,
      url: 'http://proxy.example.com:8080',
      noProxy: 'api.deepseek.com',
    ))!;
    final got = resolver(mustUrl('https://api.deepseek.com/chat/completions'));
    expect(got, isNull, reason: 'NoProxy host should bypass proxy');
  });

  test('direct hosts bypass proxy', () {
    final env = <String, String>{
      'HTTPS_PROXY': 'http://proxy.example.com:8080',
      'NO_PROXY': '',
    };
    final resolver = netclient.proxyFunc(
        netclient.ProxySpec(
          mode: netclient.modeAuto,
          directHosts: ['token-plan-cn.xiaomimimo.com'],
        ),
        environment: env)!;

    final got =
        resolver(mustUrl('https://token-plan-cn.xiaomimimo.com/v1/chat'));
    expect(got, isNull, reason: 'a direct host should bypass the proxy');

    final other = resolver(mustUrl('https://example.com/x'))!;
    expect(other.host, 'proxy.example.com');
    expect(other.port, 8080);
  });

  test('no direct hosts keeps everyone proxied', () {
    final env = <String, String>{
      'HTTPS_PROXY': 'http://proxy.example.com:8080',
      'NO_PROXY': '',
    };
    final resolver = netclient.proxyFunc(
        netclient.ProxySpec(
          mode: netclient.modeEnv,
        ),
        environment: env)!;
    final got =
        resolver(mustUrl('https://token-plan-cn.xiaomimimo.com/v1/chat'))!;
    expect(got.host, 'proxy.example.com');
    expect(got.port, 8080);
  });

  test('off proxy disables proxy', () {
    expect(netclient.proxyFunc(netclient.ProxySpec(mode: netclient.modeOff)),
        isNull);
  });

  test('summary redacts password', () {
    final got = netclient.summary(netclient.ProxySpec(
      mode: netclient.modeCustom,
      type: 'socks5',
      server: 'proxy.example.com',
      port: 1080,
      username: 'user',
      password: 'secret',
    ));
    expect(got, 'custom (socks5://user@proxy.example.com:1080)');
  });

  test('normalize mode maps empty/unknown to auto', () {
    expect(netclient.normalizeMode(''), netclient.modeAuto);
    expect(netclient.normalizeMode('  '), netclient.modeAuto);
    expect(netclient.normalizeMode('weird'), netclient.modeAuto);
    expect(netclient.normalizeMode('OFF'), netclient.modeOff);
    expect(netclient.normalizeMode('Env'), netclient.modeEnv);
    expect(netclient.normalizeMode('Custom'), netclient.modeCustom);
  });

  test('validate custom spec', () {
    // Non-custom modes have no required fields.
    expect(
        netclient.validate(const netclient.ProxySpec(mode: netclient.modeAuto)),
        isNull);
    expect(
        netclient.validate(const netclient.ProxySpec(mode: netclient.modeOff)),
        isNull);
    // Custom needs a URL or a structured server+port.
    expect(
        netclient.validate(netclient.ProxySpec(
            mode: netclient.modeCustom, url: 'http://p:8080')),
        isNull);
    expect(
        netclient.validate(netclient.ProxySpec(
            mode: netclient.modeCustom,
            type: 'socks5',
            server: 'p',
            port: 1080)),
        isNull);
    expect(
        netclient.validate(netclient.ProxySpec(
            mode: netclient.modeCustom, server: 'p', port: 1080)),
        isNull,
        reason: 'type defaults to http');
    expect(
        netclient.validate(netclient.ProxySpec(
            mode: netclient.modeCustom, type: 'ftp', server: 'p', port: 1080)),
        isNotNull,
        reason: 'unsupported proxy type');
    expect(
        netclient.validate(netclient.ProxySpec(
            mode: netclient.modeCustom, type: 'http', port: 1080)),
        isNotNull,
        reason: 'server required');
    expect(
        netclient.validate(netclient.ProxySpec(
            mode: netclient.modeCustom, type: 'http', server: 'p', port: 0)),
        isNotNull,
        reason: 'port required');
  });

  // Adapted from TestHTTPClientProxyModesAffectRequests: the Go test spins up
  // httptest servers and counts hits; here we assert which proxy URL each
  // mode resolves for the same request.
  test('proxy modes affect requests (resolver level)', () {
    final env = <String, String>{
      'HTTP_PROXY': 'http://env-proxy:8080',
      'HTTPS_PROXY': '',
      'NO_PROXY': '',
    };
    final target = mustUrl('http://service.test/resource');

    // auto uses environment proxy
    var resolver = netclient.proxyFunc(
        netclient.ProxySpec(mode: netclient.modeAuto),
        environment: env)!;
    expect(resolver(target)!.host, 'env-proxy');

    // env uses environment proxy
    resolver = netclient.proxyFunc(netclient.ProxySpec(mode: netclient.modeEnv),
        environment: env)!;
    expect(resolver(target)!.host, 'env-proxy');

    // custom ignores environment proxy
    resolver = netclient.proxyFunc(
        netclient.ProxySpec(
          mode: netclient.modeCustom,
          url: 'http://custom-proxy:8080',
        ),
        environment: env)!;
    expect(resolver(target)!.host, 'custom-proxy');

    // custom no_proxy bypasses proxy
    resolver = netclient.proxyFunc(
        netclient.ProxySpec(
          mode: netclient.modeCustom,
          url: 'http://custom-proxy:8080',
          noProxy: 'service.test',
        ),
        environment: env)!;
    expect(resolver(target), isNull);

    // off bypasses environment proxy
    expect(
        netclient.proxyFunc(netclient.ProxySpec(mode: netclient.modeOff),
            environment: env),
        isNull);
  });

  // Adapted from TestStructuredProxyTypesAffectRequests: the Go test runs
  // real HTTP/SOCKS proxy servers; here we assert customProxyUrl composes the
  // right URL for each structured type.
  test('structured proxy types build URLs', () {
    for (final typ in ['http', 'https', 'socks5', 'socks5h']) {
      final u = netclient.customProxyUrl(netclient.ProxySpec(
        mode: netclient.modeCustom,
        type: typ,
        server: '127.0.0.1',
        port: 7890,
      ));
      expect(u.scheme, typ, reason: typ);
      expect(u.host, '127.0.0.1', reason: typ);
      expect(u.port, 7890, reason: typ);
    }
  });

  // Adapted from TestHTTPSRequestsRespectProxyModes: assert which proxy an
  // https request resolves for, per mode, with HTTPS_PROXY set.
  test('HTTPS requests respect proxy modes (resolver level)', () {
    final env = <String, String>{
      'HTTP_PROXY': '',
      'HTTPS_PROXY': 'http://connect-proxy:8080',
      'NO_PROXY': '',
    };
    final target = mustUrl('https://service.test/resource');

    // auto uses HTTPS_PROXY
    var resolver = netclient.proxyFunc(
        netclient.ProxySpec(mode: netclient.modeAuto),
        environment: env)!;
    expect(resolver(target)!.host, 'connect-proxy');

    // custom proxies HTTPS requests
    resolver = netclient.proxyFunc(
        netclient.ProxySpec(
          mode: netclient.modeCustom,
          url: 'http://connect-proxy:8080',
        ),
        environment: env)!;
    expect(resolver(target)!.host, 'connect-proxy');

    // custom no_proxy bypasses HTTPS proxy
    resolver = netclient.proxyFunc(
        netclient.ProxySpec(
          mode: netclient.modeCustom,
          url: 'http://connect-proxy:8080',
          noProxy: 'service.test',
        ),
        environment: env)!;
    expect(resolver(target), isNull);

    // off bypasses HTTPS_PROXY
    expect(
        netclient.proxyFunc(netclient.ProxySpec(mode: netclient.modeOff),
            environment: env),
        isNull);
  });

  // Adapted from TestForceIPv4Dials: the Go test dials real sockets. Here we
  // assert the transport config carries the force-IPv4 knob.
  test('force IPv4 sets transport option', () {
    final tr = netclient.newTransport(
        netclient.ProxySpec(mode: netclient.modeOff),
        const netclient.TransportOptions(forceIPv4: true));
    expect(tr.options.forceIPv4, isTrue);
    expect(tr.proxy, isNull);

    final tr2 = netclient.newTransport(
        netclient.ProxySpec(mode: netclient.modeOff),
        const netclient.TransportOptions());
    expect(tr2.options.forceIPv4, isFalse);
  });

  test('newHttpClient shares the resolver', () {
    final client = netclient.newHttpClient(
        netclient.ProxySpec(mode: netclient.modeOff),
        const netclient.TransportOptions());
    expect(client.proxy, isNull);
    final proxied = netclient.newHttpClient(
        netclient.ProxySpec(mode: netclient.modeCustom, url: 'http://p:8080'),
        const netclient.TransportOptions());
    expect(proxied.proxy, isNotNull);
  });
}
