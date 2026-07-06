import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import '../capability.dart';
import '../module_descriptor.dart';
import '../module_http_server.dart';
import '../module_registry.dart';

/// ModuleHttpServer 测试——覆盖 6 个端点、生命周期、错误处理。
void main() {
  // ═══════ 固定数据 ═══════

  ModuleRegistry _seededRegistry() {
    final r = ModuleRegistry();
    r.register(ModuleDescriptor(
      id: 'agent',
      name: 'AI 助手',
      description: '流式对话',
      icon: 0xe3af, // Icons.smart_toy codePoint
      route: '/agent',
      nav: NavObjectDescriptor(
        sidebar: const SidebarDescriptor(section: 'AI 工具', order: 10),
        secondary: const [
          NavDescriptor(
            label: '设置',
            routePath: '/agent/settings',
            section: 'AI 工具',
          ),
        ],
      ),
      pages: [
        PageDescriptor(
          id: 'chat',
          label: '对话',
          layout: LayoutDescriptor(
            type: 'flex',
            slots: {
              'main': SlotDescriptor(
                component: ComponentDescriptor(type: 'chat', config: {}),
              ),
            },
          ),
        ),
      ],
      version: '1.2.0',
    ));
    r.register(ModuleDescriptor(
      id: 'scores',
      name: '成绩单',
      icon: 0xe4a3, // Icons.score codePoint
      route: '/scores',
      nav: NavObjectDescriptor(
        sidebar: const SidebarDescriptor(section: '教育', order: 20),
      ),
      version: '2.0.1',
    ));
    r.setCapabilities('agent', [
      CapabilityDimension.agent,
      CapabilityDimension.module,
      CapabilityDimension.process,
    ]);
    r.setCapabilities('scores', [CapabilityDimension.module]);
    r.seal();
    return r;
  }

  Future<HttpClientResponse> _get(int port, String path) async {
    final client = HttpClient();
    final req = await client.getUrl(Uri.parse('http://localhost:$port$path'));
    final resp = await req.close();
    return resp;
  }

  Future<Map<String, dynamic>> _getJson(int port, String path) async {
    final resp = await _get(port, path);
    final body = await resp.transform(utf8.decoder).join();
    return jsonDecode(body) as Map<String, dynamic>;
  }

  // ═══════════════════════════════════════════════════════════════
  // 启动/停止
  // ═══════════════════════════════════════════════════════════════
  group('生命周期', () {
    test('start 后 isRunning 为 true', () async {
      final registry = _seededRegistry();
      final server = ModuleHttpServer(registry, port: 0); // 自动分配端口
      expect(server.isRunning, isFalse);
      await server.start();
      expect(server.isRunning, isTrue);
      expect(server.port, greaterThan(0)); // 验证端口已分配
      await server.stop();
      expect(server.isRunning, isFalse);
    });

    test('重复 start 不报错', () async {
      final registry = _seededRegistry();
      final server = ModuleHttpServer(registry, port: 0);
      await server.start();
      await server.start(); // 第二次应无操作
      await server.stop();
    });

    test('重复 stop 不报错', () async {
      final registry = _seededRegistry();
      final server = ModuleHttpServer(registry, port: 0);
      await server.start();
      await server.stop();
      await server.stop(); // 第二次应无操作
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 端点
  // ═══════════════════════════════════════════════════════════════
  group('端点', () {
    late ModuleRegistry registry;
    late ModuleHttpServer server;

    setUp(() async {
      registry = _seededRegistry();
      server = ModuleHttpServer(registry, port: 0);
      await server.start();
    });

    tearDown(() async {
      await server.stop();
    });

    // ── GET /module/health ──
    test('health 返回 200 + status ok', () async {
      final json = await _getJson(server.port, '/module/health');
      expect(json['status'], 'ok');
    });

    // ── GET /module/modules ──
    test('modules 列出所有模块摘要', () async {
      final json = await _getJson(server.port, '/module/modules');
      expect(json['count'], 2);
      final modules = json['modules'] as List;
      final ids = modules.map((m) => (m as Map)['id']).toSet();
      expect(ids, contains('agent'));
      expect(ids, contains('scores'));
    });

    // ── GET /module/modules/:id ──
    test('modules/:id 返回完整 ModuleDescriptor', () async {
      final json = await _getJson(server.port, '/module/modules/agent');
      expect(json['id'], 'agent');
      expect(json['name'], 'AI 助手');
      expect(json['version'], '1.2.0');
    });

    test('modules/:id 不存在返回 404', () async {
      final resp = await _get(server.port, '/module/modules/nonexistent');
      expect(resp.statusCode, 404);
    });

    // ── GET /module/search ──
    test('search 无参数返回全部', () async {
      final json = await _getJson(server.port, '/module/search?q=');
      expect(json['count'], 2);
    });

    test('search 按 q 筛选', () async {
      final json = await _getJson(server.port, '/module/search?q=AI');
      expect(json['count'], 1);
      final results = json['results'] as List;
      expect((results.first as Map)['id'], 'agent');
    });

    test('search 按 dim 筛选', () async {
      final json =
          await _getJson(server.port, '/module/search?q=&dim=process');
      expect(json['count'], 1);
      final results = json['results'] as List;
      expect((results.first as Map)['id'], 'agent');
    });

    test('search 按 cat 筛选', () async {
      final json =
          await _getJson(server.port, '/module/search?q=&cat=教育');
      expect(json['count'], 1);
      final results = json['results'] as List;
      expect((results.first as Map)['id'], 'scores');
    });

    test('search 组合筛选', () async {
      final json = await _getJson(server.port,
          '/module/search?q=助手&dim=agent&cat=AI 工具');
      expect(json['count'], 1);
    });

    // ── GET /module/nav ──
    test('nav 返回分组导航', () async {
      final json = await _getJson(server.port, '/module/nav');
      final groups = json['navGroups'] as List;
      expect(groups.length, 2);
      final sections =
          groups.map((g) => (g as Map)['section']).toSet();
      expect(sections, contains('AI 工具'));
      expect(sections, contains('教育'));
    });

    // ── GET /module/routes ──
    test('routes 返回全部路由', () async {
      final json = await _getJson(server.port, '/module/routes');
      final routes = json['routes'] as List;
      expect(routes, contains('/agent'));
      expect(routes, contains('/scores'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 错误处理
  // ═══════════════════════════════════════════════════════════════
  group('错误处理', () {
    late ModuleRegistry registry;
    late ModuleHttpServer server;

    setUp(() async {
      registry = _seededRegistry();
      server = ModuleHttpServer(registry, port: 0);
      await server.start();
    });

    tearDown(() async {
      await server.stop();
    });

    test('未知端点返回 404', () async {
      final resp = await _get(server.port, '/module/unknown');
      expect(resp.statusCode, 404);
    });

    test('POST 请求返回 405', () async {
      final client = HttpClient();
      final req =
          await client.postUrl(Uri.parse('http://localhost:${server.port}/module/health'));
      final resp = await req.close();
      expect(resp.statusCode, 405);
      client.close();
    });
  });
}
