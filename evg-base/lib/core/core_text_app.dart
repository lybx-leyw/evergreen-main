import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/services.dart';
import 'services/plugin_installer.dart';
import 'config/config_http_server.dart';
import 'config/settings.dart';
import 'config/permissions.dart';
import 'data/data_http_server.dart';
import 'data/orchestrator.dart';
import 'data/type.dart';
import 'module/module_http_server.dart';
import 'module/module_registry.dart';
import 'module/module_loader.dart';
import 'module/module_descriptor.dart';
import 'theme/theme_http_server.dart';
import 'theme/theme_store.dart';
import 'theme/theme_loader.dart';
import 'theme/theme_descriptor.dart';
import 'agent/tools/scripted_agent_http_server.dart';

// ═══════ HTTP ═══════

Future<Map<String, dynamic>> _get(int port, String path) async {
  final client = HttpClient();
  try {
    final url = 'http://127.0.0.1:$port$path';
    stderr.writeln('[TextApp] GET $url');
    final req = await client.getUrl(Uri.parse(url));
    final resp = await req.close();
    final body = await resp.transform(utf8.decoder).join();
    stderr.writeln('[TextApp] GET $url → ${resp.statusCode} (${body.length}B)');
    return jsonDecode(body) as Map<String, dynamic>;
  } catch (e) {
    stderr.writeln('[TextApp] GET http://127.0.0.1:$port$path ❌ $e');
    rethrow;
  } finally { client.close(); }
}

Future<Map<String, dynamic>> _post(int port, String path, Map<String, dynamic> body) async {
  final client = HttpClient();
  try {
    final url = 'http://127.0.0.1:$port$path';
    stderr.writeln('[TextApp] POST $url ← $body');
    final req = await client.postUrl(Uri.parse(url));
    req.headers.contentType = ContentType.json;
    final bytes = utf8.encode(jsonEncode(body));
    req.contentLength = bytes.length;
    req.add(bytes);
    final resp = await req.close();
    final respBody = await resp.transform(utf8.decoder).join();
    stderr.writeln('[TextApp] POST $url → ${resp.statusCode}');
    return jsonDecode(respBody) as Map<String, dynamic>;
  } catch (e) {
    stderr.writeln('[TextApp] POST http://127.0.0.1:$port$path ❌ $e');
    rethrow;
  } finally { client.close(); }
}

/// 流式 SSE——每收到一个事件立即回调 [onEvent]，不等待全部完成。
Future<void> _sseStream(int port, String path, Map<String, dynamic> body, void Function(Map<String, dynamic>) onEvent) async {
  final client = HttpClient();
  try {
    final url = 'http://127.0.0.1:$port$path';
    stderr.writeln('[TextApp] SSE POST $url');
    final req = await client.postUrl(Uri.parse(url));
    req.headers.contentType = ContentType.json;
    final bytes = utf8.encode(jsonEncode(body));
    req.contentLength = bytes.length;
    req.add(bytes);
    final resp = await req.close();
    await for (final line in resp.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.startsWith('data: ')) {
        try {
          final e = jsonDecode(line.substring(6)) as Map<String, dynamic>;
          final t = e['type'] as String? ?? '?';
          if (t == 'text') stderr.writeln('[TextApp] SSE text: "${e['text']}"');
          onEvent(e);
        } catch (_) {}
      }
    }
  } catch (e) {
    stderr.writeln('[TextApp] SSE ❌ $e');
  } finally {
    client.close();
  }
}

Future<List<Map<String, dynamic>>> _sse(int port, String path, Map<String, dynamic> body) async {
  final client = HttpClient();
  try {
    final url = 'http://127.0.0.1:$port$path';
    final inputPreview = (body['input']?.toString() ?? '').length > 80 ? '${body['input']?.toString().substring(0, 80)}...' : body['input']?.toString() ?? '';
    stderr.writeln('[TextApp] SSE POST $url ← {input: "$inputPreview"}');
    final req = await client.postUrl(Uri.parse(url));
    req.headers.contentType = ContentType.json;
    final bytes = utf8.encode(jsonEncode(body));
    req.contentLength = bytes.length;
    req.add(bytes);
    final resp = await req.close();
    final events = <Map<String, dynamic>>[];
    await for (final line in resp.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.startsWith('data: ')) {
        try {
          final e = jsonDecode(line.substring(6)) as Map<String, dynamic>;
          events.add(e);
          stderr.writeln('[TextApp] SSE event: ${e['type']}');
        } catch (_) {}
      }
    }
    stderr.writeln('[TextApp] SSE done: ${events.length} events');
    return events;
  } catch (e) {
    stderr.writeln('[TextApp] SSE ❌ $e');
    rethrow;
  } finally { client.close(); }
}

// ═══════ 端口 ═══════

final _ports = <String, int>{};

Future<void> _initServers() async {
  final prefs = await SharedPreferences.getInstance();
  final dio = Dio();
  final installer = PluginInstaller(pluginsDir: '.text_app_plugins', dio: dio);
  final coreServer = CoreHttpServer(installer, UpdateService(dio));
  await initSettings(prefs, pluginDirs: ['builtins/']);
  final configServer = ConfigHttpServer(prefs);
  final orch = DataOrchestrator();
  orch.register(const DataType<Map<String, dynamic>>(name: '课表', category: '教务', displayName: '课程表', ttl: Duration(minutes: 5)),
      () async => [{'name': '高数', 'room': 'B201'}]);
  final dataServer = DataHttpServer(orch);
  final moduleReg = ModuleRegistry()
    ..registerAll(scanModules('builtins/'))
    ..register(const ModuleDescriptor(id: 'agent', name: 'Agent'))
    ..registerAll(scanModules('example/plugins/'));
  moduleReg.seal();
  final moduleServer = ModuleHttpServer(moduleReg, port: 0);
  final themeStore = ThemeStore();
  loadThemes('builtins/', themeStore);
  themeStore.activeTheme = themeStore.findById('light');
  final themeServer = ThemeHttpServer(themeStore);
  final agentServer = ScriptedAgentHttpServer(scenario: ScriptedAgentHttpServer.scenario3());
  final servers = {'Core': coreServer, 'Config': configServer, 'Data': dataServer, 'Module': moduleServer, 'Theme': themeServer, 'Agent': agentServer};
  for (final e in servers.entries) {
    try {
      final r = (e.value as dynamic).start();
      final p = (r is Future) ? ((await r) is int ? await r : (e.value as dynamic).port) : (e.value as dynamic).port;
      _ports[e.key] = p is int ? p : 0;
    } catch (_) {}
  }
}

// ═══════ App ═══════

final _themeMode = ValueNotifier(Brightness.dark);

/// 文本版 Evergreen App——接收 main.dart 传入的服务器端口，不自行初始化。
class EvergreenTextApp extends StatelessWidget {
  final Map<String, int> serverPorts;
  EvergreenTextApp({super.key, required this.serverPorts}) {
    _ports.clear();
    _ports.addAll(serverPorts);
    stderr.writeln('[TextApp] 服务器端口就绪: $_ports');
  }
  @override Widget build(BuildContext c) => ValueListenableBuilder(
    valueListenable: _themeMode,
    builder: (_, brightness, __) => MaterialApp(
      debugShowCheckedModeBanner: false, title: 'Evergreen Base',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal, brightness: brightness),
      home: const HomePage(),
    ),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _index = 0;
  @override Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: const Text('🌲 Evergreen Base — 文本模式')),
    body: IndexedStack(index: _index, children: const [
      WorkbenchPage(), MarketplacePage(), ChatPage(key: ValueKey('chat')), MyPluginsPage(), SettingsPage(),
    ]),
    bottomNavigationBar: NavigationBar(selectedIndex: _index, onDestinationSelected: (i) => setState(() => _index = i), destinations: const [
      NavigationDestination(icon: Icon(Icons.dashboard), label: '工作台'),
      NavigationDestination(icon: Icon(Icons.store), label: '市场'),
      NavigationDestination(icon: Icon(Icons.chat), label: 'AI 对话'),
      NavigationDestination(icon: Icon(Icons.extension), label: '我的插件'),
      NavigationDestination(icon: Icon(Icons.settings), label: '设置'),
    ]),
  );
}

// ═══════ [1] 工作台 ═══════

class WorkbenchPage extends StatelessWidget {
  const WorkbenchPage({super.key});
  @override Widget build(BuildContext c) {
    if (_ports.isEmpty) return const Center(child: CircularProgressIndicator());
    final modPort = _ports['Module'];
    final corePort = _ports['Core'];
    if (modPort == null && corePort == null) return const Center(child: Text('服务未就绪'));
    return FutureBuilder(
      future: _get(modPort ?? corePort!, modPort != null ? '/module/search?q=' : '/core/plugins').catchError((_) => <String, dynamic>{}),
      builder: (_, snap) {
        if (!snap.hasData) return const Center(child: Text('加载中...'));
        final data = snap.data ?? {};
        List items = (data.containsKey('results') ? data['results'] : data['plugins']) as List? ?? [];
        if (items.isEmpty) return const Center(child: Text('暂无已安装模块'));
        return ListView.builder(itemCount: items.length, itemBuilder: (_, i) {
          final m = items[i] as Map;
          return ListTile(leading: const Icon(Icons.widgets), title: Text(m['name']?.toString() ?? ''), subtitle: Text(m['id']?.toString() ?? ''));
        });
      },
    );
  }
}

// ═══════ [2] 市场 ═══════

class MarketplacePage extends StatefulWidget {
  const MarketplacePage({super.key});
  @override State<MarketplacePage> createState() => _MarketplacePageState();
}

class _MarketplacePageState extends State<MarketplacePage> {
  final _urlCtrl = TextEditingController();
  String _status = '';

  Future<void> _install() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) return;
    setState(() => _status = '安装中...');
    try {
      final r = await _post(_ports['Core']!, '/core/install', {'url': url});
      setState(() => _status = r['success'] == true ? '✅ ${r['pluginId']} 安装成功' : '❌ ${r['error']}');
    } catch (e) {
      setState(() => _status = '❌ $e');
    }
  }

  @override Widget build(BuildContext c) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(children: [
      TextField(controller: _urlCtrl, decoration: const InputDecoration(labelText: '.plugin URL', hintText: 'https://...')),
      const SizedBox(height: 8),
      FilledButton.icon(onPressed: _install, icon: const Icon(Icons.install_desktop), label: const Text('安装')),
      if (_status.isNotEmpty) ...[const SizedBox(height: 8), Text(_status)],
      const Divider(height: 32),
      Expanded(child: FutureBuilder(
        future: _get(_ports['Core']!, '/core/plugins').catchError((_) => <String, dynamic>{'plugins': []}),
        builder: (_, snap) {
          final plugins = (snap.data?['plugins'] as List?) ?? [];
          if (plugins.isEmpty) return const Center(child: Text('暂无已安装插件'));
          return ListView.builder(itemCount: plugins.length, itemBuilder: (_, i) {
            final p = plugins[i] as Map;
            return ListTile(title: Text(p['name']?.toString() ?? ''), subtitle: Text('v${p['version']}  ${p['id']}'));
          });
        },
      )),
    ]),
  );
}

// ═══════ [3] AI 对话 ═══════

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});
  @override State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _ctrl = TextEditingController();
  final _list = ValueNotifier(<Widget>[]);
  final _scroll = ScrollController();
  bool _loading = false;

  Future<void> _send() async {
    final input = _ctrl.text.trim();
    if (input.isEmpty || _ports.isEmpty || _loading) return;
    _list.value = [..._list.value, ListTile(leading: const Icon(Icons.person), title: Text(input))];
    stderr.writeln('[TextApp] Chat UI: added user msg, list length=${_list.value.length}');
    setState(() { _loading = true; });
    _ctrl.clear();
    try {
      // 动态发现 chat 模块
      String? chatModuleId;
      final modPort = _ports['Module'];
      if (modPort != null && modPort > 0) {
        try {
          final modulesResp = await _get(modPort, '/module/modules');
          final modules = (modulesResp['modules'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          for (final m in modules) {
            if (m['ui'] == 'chat') { chatModuleId = m['id'] as String?; break; }
          }
        } catch (_) {}
      }
      // 通过模块 .exe 中间层（如存在），否则 fallback 到 AgentHttpServer 直连
      final pluginPort = chatModuleId != null ? _ports[chatModuleId] : null;
      final usePlugin = pluginPort != null && pluginPort > 0;
      final chatPort = usePlugin ? pluginPort : _ports['Agent']!;
      final chatPath = usePlugin ? '/chat' : '/agent/chat/stream';
      stderr.writeln('[TextApp] Chat route: ${usePlugin ? "$chatModuleId .exe" : "AgentHttpServer 直连"} → $chatPath');
      // 流式对话：先添加一个空占位气泡，随 SSE 事件逐步更新
      final aiMsg = ValueNotifier('...');
      _list.value = [..._list.value, ListTile(leading: const Icon(Icons.smart_toy), title: ValueListenableBuilder<String>(valueListenable: aiMsg, builder: (_, t, __) => Text(t)))];
      setState(() { _loading = false; }); // 释放 UI 线程

      final buf = StringBuffer();
      await _sseStream(chatPort, chatPath, {'input': input}, (e) {
        if (e['type'] == 'text') {
          buf.write(e['text']?.toString() ?? '');
          aiMsg.value = buf.toString();
        }
      });
      if (buf.isEmpty) aiMsg.value = '(空响应)';
      stderr.writeln('[TextApp] Chat response: "${buf.toString().length > 100 ? '${buf.toString().substring(0, 100)}...' : buf.toString()}"');
    } catch (e) {
      _list.value = [..._list.value, ListTile(leading: const Icon(Icons.error), title: Text('❌ $e'))];
      setState(() { _loading = false; });
    }
    _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
  }

  @override Widget build(BuildContext c) => Column(children: [
    Expanded(child: ValueListenableBuilder<List<Widget>>(
      valueListenable: _list,
      builder: (_, items, __) => ListView(controller: _scroll, children: items),
    )),
    Padding(padding: const EdgeInsets.all(8), child: Row(children: [
      Expanded(child: TextField(controller: _ctrl, enabled: !_loading, decoration: const InputDecoration(hintText: '输入消息...'), onSubmitted: (_) => _send())),
      IconButton(icon: _loading ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send), onPressed: _loading ? null : _send),
    ])),
  ]);
}

// ═══════ [4] 我的插件 ═══════

class MyPluginsPage extends StatelessWidget {
  const MyPluginsPage({super.key});
  @override Widget build(BuildContext c) {
    if (_ports.isEmpty) return const Center(child: CircularProgressIndicator());
    return FutureBuilder(
      future: _get(_ports['Core']!, '/core/plugins'),
      builder: (_, snap) {
        final plugins = (snap.data?['plugins'] as List?) ?? [];
        if (plugins.isEmpty) return const Center(child: Text('暂无已安装插件'));
        return ListView.builder(itemCount: plugins.length, itemBuilder: (_, i) {
          final p = plugins[i] as Map;
          return ListTile(
            leading: Icon(p['isUnstable'] == true ? Icons.warning : Icons.check_circle, color: p['isUnstable'] == true ? Colors.orange : Colors.green),
            title: Text(p['name']?.toString() ?? ''), subtitle: Text('v${p['version']}  ${p['id']}'),
            trailing: IconButton(icon: const Icon(Icons.delete), onPressed: () async {
              await _post(_ports['Core']!, '/core/uninstall/${p['id']}', {});
              (c as Element).reassemble();
            }),
          );
        });
      },
    );
  }
}

// ═══════ [5] 设置 ═══════

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  List<Map<String, dynamic>> _settings = [];
  final _ctrls = <String, TextEditingController>{};

  @override void initState() { super.initState(); _load(); }
  @override void dispose() { for (final c in _ctrls.values) { c.dispose(); } super.dispose(); }

  Future<void> _load() async {
    if (_ports.isEmpty) return;
    final themeResp = await _get(_ports['Theme']!, '/theme/active');
    final settingsResp = await _get(_ports['Config']!, '/config/settings');
    final raw = (settingsResp['settings'] as List?) ?? [];
    final list = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    list.insert(0, {'key': '_theme', 'label': '主题', 'type': 'option', 'value': themeResp['id']?.toString() ?? 'light',
      'options': [{'value':'light','label':'浅色'},{'value':'dark','label':'深色'}]});
    setState(() { _settings = list; });
  }

  Future<void> _save(String key, String value) async {
    if (key == '_theme') {
      await _post(_ports['Theme']!, '/theme/active', {'id': value});
      _themeMode.value = value == 'dark' ? Brightness.dark : Brightness.light;
    } else {
      await _post(_ports['Config']!, '/config/settings/$key', {'value': value});
    }
    _load();
  }

  @override Widget build(BuildContext c) {
    if (_settings.isEmpty) return const Center(child: CircularProgressIndicator());
    final apiKey = _settings.where((s) => s['key'] == 'DEEPSEEK_API_KEY').firstOrNull;
    final hasApiKey = (apiKey?['value'] as String?)?.isNotEmpty == true;

    return ListView(children: [
      Card(child: ListTile(
        leading: Icon(hasApiKey ? Icons.check_circle : Icons.warning, color: hasApiKey ? Colors.green : Colors.orange),
        title: Text(hasApiKey ? 'API 已配置' : '未配置 API Key'),
        subtitle: const Text('填入 DeepSeek API Key 后可使用 AI 对话'),
      )),
      Card(child: SwitchListTile(
        secondary: const Icon(Icons.terminal),
        title: const Text('6 服务已启动'),
        subtitle: Text('Core:${_ports['Core']}  Config:${_ports['Config']}  Agent:${_ports['Agent']}'),
        value: true, onChanged: (_) {},
      )),
      ..._settings.map((s) => _row(s)),
    ]);
  }

  Widget _row(Map<String, dynamic> s) {
    final key = s['key'] as String;
    final label = s['label'] as String? ?? key;
    final type = s['type'] as String? ?? 'string';
    final value = s['value'] as String? ?? '';
    final isSecure = s['isSecure'] == true;
    final options = (s['options'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList();

    // bool
    if (type == 'bool') {
      return Card(child: SwitchListTile(
        secondary: const Icon(Icons.toggle_on), title: Text(label),
        value: value == 'true', onChanged: (v) => _save(key, v ? 'true' : 'false'),
      ));
    }
    // option
    if (type == 'option' && options != null && options.isNotEmpty) {
      return Card(child: ListTile(
        leading: const Icon(Icons.tune), title: Text(label),
        trailing: DropdownButton<String>(
          value: options.any((o) => o['value'] == value) ? value : options.first['value']?.toString(),
          items: options.map((o) => DropdownMenuItem(value: o['value']?.toString(), child: Text(o['label']?.toString() ?? ''))).toList(),
          onChanged: (v) { if (v != null) _save(key, v); },
        ),
      ));
    }
    // string / path / isSecure → inline TextField
    _ctrls.putIfAbsent(key, () => TextEditingController(text: isSecure ? '' : value));
    return Card(child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: [
        SizedBox(width: 100, child: Text(label, style: const TextStyle(fontSize: 14))),
        Expanded(child: TextField(
          controller: _ctrls[key],
          obscureText: isSecure,
          decoration: InputDecoration(
            isDense: true,
            hintText: isSecure ? '••••••••' : (s['hint'] as String? ?? (value.isNotEmpty ? value : '输入...')),
          ),
        )),
        const SizedBox(width: 8),
        FilledButton(onPressed: () => _save(key, _ctrls[key]!.text), child: const Text('保存')),
      ]),
    ));
  }
}
