/// ThemeHttpServer 6 端点全量测试。
library;

import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';

import '../theme_descriptor.dart';
import '../theme_store.dart';
import '../theme_http_server.dart';

// ═══════ helpers ═══════

ThemeStore _populatedStore() {
  final store = ThemeStore();
  store.register(const ThemeDescriptor(
    id: 'light',
    name: '浅色',
    semanticTokens: {'primary': '#1677FF', 'background': '#FFFFFF'},
    componentTokens: {
      'sidebar': {'bg': '#F2F3F5', 'text': '#1A1D21'},
      'button': {'primary': '#1677FF', 'text': '#FFFFFF'},
    },
  ));
  store.register(const ThemeDescriptor(
    id: 'dark',
    name: '深色',
    semanticTokens: {'primary': '#4096FF', 'background': '#0D1117'},
    componentTokens: {
      'sidebar': {'bg': '#161B22', 'text': '#E6EDF3'},
    },
  ));
  store.activeTheme = store.findById('light');
  return store;
}

Future<Map<String, dynamic>> _get(HttpClient client, int port, String path) async {
  final req = await client.getUrl(Uri.parse('http://127.0.0.1:$port$path'));
  final resp = await req.close();
  final body = await utf8.decodeStream(resp);
  return {
    'status': resp.statusCode,
    'body': body.isEmpty ? {} : jsonDecode(body) as Map<String, dynamic>,
  };
}

Future<Map<String, dynamic>> _post(HttpClient client, int port, String path,
    Map<String, dynamic> data) async {
  final req = await client.postUrl(Uri.parse('http://127.0.0.1:$port$path'));
  req.headers.contentType = ContentType.json;
  req.write(jsonEncode(data));
  final resp = await req.close();
  final body = await utf8.decodeStream(resp);
  return {
    'status': resp.statusCode,
    'body': body.isEmpty ? {} : jsonDecode(body) as Map<String, dynamic>,
  };
}

// ═══════ tests ═══════

void main() {
  late ThemeHttpServer server;
  late int port;
  late ThemeStore store;
  late HttpClient client;

  setUp(() async {
    store = _populatedStore();
    server = ThemeHttpServer(store);
    port = await server.start();
    client = HttpClient();
  });

  tearDown(() async {
    client.close();
    await server.stop();
  });

  group('ThemeHttpServer', () {
    // ── 1: health ──
    test('GET /theme/health → 200', () async {
      final r = await _get(client, port, '/theme/health');
      expect(r['status'], 200);
      expect(r['body']['status'], 'ok');
      expect(r['body']['themeCount'], 2);
    });

    // ── 2: list themes ──
    test('GET /theme/themes → 200', () async {
      final r = await _get(client, port, '/theme/themes');
      expect(r['status'], 200);
      final themes = r['body']['themes'] as List;
      expect(themes.length, 2);
      expect(themes[0]['id'], isIn(['light', 'dark']));
    });

    // ── 3: get theme by id ──
    test('GET /theme/themes/:id → 200 存在', () async {
      final r = await _get(client, port, '/theme/themes/light');
      expect(r['status'], 200);
      expect(r['body']['id'], 'light');
    });

    test('GET /theme/themes/:id → 404 不存在', () async {
      final r = await _get(client, port, '/theme/themes/nonexistent');
      expect(r['status'], 404);
    });

    // ── 4: get active ──
    test('GET /theme/active → 200', () async {
      final r = await _get(client, port, '/theme/active');
      expect(r['status'], 200);
      expect(r['body']['id'], 'light');
    });

    // ── 5: set active ──
    test('POST /theme/active → 200 切换成功', () async {
      final r = await _post(client, port, '/theme/active', {'id': 'dark'});
      expect(r['status'], 200);
      expect(r['body']['active'], 'dark');

      // 验证切换生效
      final r2 = await _get(client, port, '/theme/active');
      expect(r2['body']['id'], 'dark');
    });

    test('POST /theme/active → 404 id 不存在', () async {
      final r = await _post(client, port, '/theme/active', {'id': 'ghost'});
      expect(r['status'], 404);
    });

    test('POST /theme/active → 400 缺少 id', () async {
      final r = await _post(client, port, '/theme/active', {});
      expect(r['status'], 400);
    });

    test('POST /theme/active → 400 空 body', () async {
      final req = await client.postUrl(Uri.parse('http://127.0.0.1:$port/theme/active'));
      req.headers.contentType = ContentType.json;
      final resp = await req.close();
      final body = await utf8.decodeStream(resp);
      final data = jsonDecode(body) as Map<String, dynamic>;
      expect(resp.statusCode, 400);
      expect(data['error'], contains('id'));
    });

    // ── 6: token query ──
    test('GET /theme/token?component=sidebar&token=bg → 200', () async {
      final r = await _get(client, port, '/theme/token?component=sidebar&token=bg');
      expect(r['status'], 200);
      expect(r['body']['color'], '#F2F3F5');
      expect(r['body']['component'], 'sidebar');
      expect(r['body']['token'], 'bg');
      expect(r['body']['themeId'], 'light');
    });

    test('GET /theme/token → 400 缺少参数', () async {
      final r = await _get(client, port, '/theme/token');
      expect(r['status'], 400);
    });

    test('GET /theme/token → 400 缺 component', () async {
      final r = await _get(client, port, '/theme/token?token=bg');
      expect(r['status'], 400);
    });

    test('GET /theme/token → 404 未找到', () async {
      final r = await _get(client, port, '/theme/token?component=sidebar&token=nonexistent');
      expect(r['status'], 404);
    });

    // ── general ──
    test('GET 不存在路径 → 404', () async {
      final r = await _get(client, port, '/theme/ghost');
      expect(r['status'], 404);
    });

    test('isRunning / port', () {
      expect(server.isRunning, isTrue);
      expect(server.port, greaterThan(0));
    });

    test('stop → isRunning = false', () async {
      await server.stop();
      expect(server.isRunning, isFalse);
    });
  });
}
