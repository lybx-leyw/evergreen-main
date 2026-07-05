/// Core 跨模块联动——交互式菜单 + 真实后端数据。
///
/// 用法: dart run example/example.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../module/modules.dart';
import '../theme/theme.dart';
import '../module/lib/renderer.dart';
import '../services/services.dart';

final _pluginsDir =
    '${Directory.current.path}${Platform.pathSeparator}example${Platform.pathSeparator}plugins';
late ModuleRegistry _reg;
late ThemeStore _themes;
late PluginInstaller _installer;
late CoreHttpServer _coreServer;

Future<void> main() async {
  _reg = ModuleRegistry();
  _themes = ThemeStore();
  _reg.registerAll(scanModules('builtins/'));
  _reg.registerAll(scanModules(_pluginsDir));
  // 占位依赖：mesh_demo + super_app 的 manifest 声明依赖 agent
  _reg.register(const ModuleDescriptor(id: 'agent', name: 'Agent'));
  _reg.seal();
  loadThemes(
      '${Directory.current.path}${Platform.pathSeparator}theme${Platform.pathSeparator}builtins',
      _themes);
  loadThemes(_pluginsDir, _themes);  // 插件主题覆盖同 id 内置主题

  // Core 服务初始化——启动微服务网格
  final pluginsDir = '${Directory.current.path}${Platform.pathSeparator}plugins';
  final dio = Dio();
  _installer = PluginInstaller(pluginsDir: pluginsDir, dio: dio);
  _installer.onInstall = (_) => print('  [系统] 插件已安装，请各 Loader 刷新注册表');
  _installer.onUninstall = (_) => print('  [系统] 插件已卸载，请各 Loader 刷新注册表');

  final ocrPipeline = OcrPipeline(dio);
  final updateService = UpdateService(dio);
  _coreServer = CoreHttpServer(_installer, ocrPipeline, updateService);

  // 自动启动 CoreHttpServer——模拟启动管线第 4 步
  final corePort = await _coreServer.start();
  print('╔══════════════════════════════════════════════╗');
  print('║   🌐 Core 微服务网格已就绪                   ║');
  print('║   CoreHttpServer → http://127.0.0.1:$corePort   ║');
  print('║   端口文件 → .core_port                       ║');
  print('║   插件 .exe 读取 .core_port → 调用 /core/*    ║');
  print('╚══════════════════════════════════════════════╝');
  print('');

  while (true) {
    print('\n╔══════════════════════════════════════════════╗');
    print('║   🌲 Core 2.0 跨模块联动                    ║');
    print('║   ${_reg.modules.length} 模块 · ${_themes.all.length} 主题 · ${_reg.buildRoutePaths().length} 路由        ║');
    print('║   ${_installer.listPlugins().length} 插件 · Core API: http://127.0.0.1:${_coreServer.port}              ║');
    print('╠══════════════════════════════════════════════╣');
    print('║  1.浏览模块    2.模块详情    3.渲染 UI       ║');
    print('║  4.数据交互    5.AI工具调用  6.主题配色      ║');
    print('║  7.联动图      8.目录树      9.JSON源码      ║');
    print('║ 10.安装插件   11.卸载插件   12.OCR识别       ║');
    print('║ 13.更新检查   14.插件列表   15.🌐 微服务网格 ║');
    print('║  0.退出                                      ║');
    print('╚══════════════════════════════════════════════╝');

    stdout.write('选择 > ');
    final cmd = stdin.readLineSync()?.trim() ?? '';
    print('');
    switch (cmd) {
      case '1': _browse(); break;
      case '2': _inspect(); break;
      case '3': _render(); break;
      case '4': await _dataDemo(); break;
      case '5': await _toolDemo(); break;
      case '6': _themeShow(); break;
      case '7': _linkage(); break;
      case '8': _tree(); break;
      case '9': _raw(); break;
      case '10': await _installDemo(); break;
      case '11': await _uninstallDemo(); break;
      case '12': await _ocrDemo(); break;
      case '13': await _updateDemo(); break;
      case '14': _pluginList(); break;
      case '15': await _httpServerDemo(); break;
      case '0':
      case 'q':
        await _coreServer.stop();
        print('👋\n');
        return;
    }
  }
}

// ═══ 1. 浏览 ═══
void _browse() {
  print('═══ 已注册模块 ═══');
  for (final m in _reg.modules) {
    final tags = <String>[];
    if (m.hasSidebar) tags.add('sidebar');
    if (m.isServiceOnly) tags.add('service');
    if (m.dataBindings.isNotEmpty) tags.add('data:${m.dataBindings.length}');
    if (m.process != null) tags.add('exe');
    print('  ${m.id.padRight(18)} ${m.name.padRight(10)} ui=${m.ui.padRight(12)} ${tags.join(" ")}');
  }
  print('\n═══ 已加载主题 ═══');
  for (final t in _themes.all) {
    print('  ${t.id.padRight(18)} ${t.name} (${t.semanticTokens.length}+${t.componentTokens.length} tokens)');
  }
}

// ═══ 2. 模块详情 ═══
void _inspect() {
  stdout.write('模块 id > ');
  final m = _reg.findById(stdin.readLineSync()?.trim() ?? '');
  if (m == null) { print('未找到\n'); return; }
  print('\n═══ ${m.name} (${m.id}) ═══');
  print('  ui=${m.ui}  route=${m.route ?? "-"}  sidebar=${m.sidebar?.section ?? "-"}');
  final l = m.layout;
  print('  layout: mode=${l.mode} grid=${l.grid?.columns ?? "-"}col drawers=${l.drawers} panels=${l.panels.length} search=${l.search?.enabled == true}');
  if (m.actions != null) {
    final a = m.actions!;
    print('  actions: tap=${a.itemTap} select=${a.selection} sort=${a.sortable} create=${a.creatable} edit=${a.editable} export=${a.exportable}');
  }
  if (m.dataBindings.isNotEmpty) {
    for (final d in m.dataBindings) print('  data → ${d.dataType} (${d.display}${d.filter ? ", filter" : ""})');
  }
  if (m.chat != null) print('  chat: thinking=${m.chat!.thinking.visible} stream=${m.chat!.stream.enabled}');
  if (m.spreadsheet != null) print('  spreadsheet: formulas=${m.spreadsheet!.formulas} charts=${m.spreadsheet!.charts}');
  if (m.workspace?.enabled == true) print('  workspace: ${m.workspace!.maxFiles}f/${m.workspace!.maxSizeMb}MB ai=${m.workspace!.aiCreatable}');
  if (m.process != null) print('  process: ${m.process!.exe} (${m.process!.protocol})');
  print('');
}

// ═══ 3. 渲染 ═══
void _render() {
  stdout.write('模块 id (回车=全部) > ');
  final id = stdin.readLineSync()?.trim() ?? '';
  print('');
  if (id.isEmpty) {
    for (final m in _reg.modules) print(renderModule(m));
  } else {
    final m = _reg.findById(id);
    if (m == null) { print('未找到\n'); return; }
    print(renderModule(m));
  }
  print('');
}

// ═══ 4. 数据交互 ═══
Future<void> _dataDemo() async {
  final py = '$_pluginsDir${Platform.pathSeparator}super_app${Platform.pathSeparator}data${Platform.pathSeparator}plugin.py';
  if (!File(py).existsSync()) { print('plugin.py 不存在: $py\n'); return; }

  print('启动数据源...');
  final proc = await Process.start('python', [py]);

  // 等待 PORT:
  final completer = Completer<int>();
  late StreamSubscription<String> sub;
  sub = proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
    if (!completer.isCompleted && line.startsWith('PORT:')) {
      completer.complete(int.parse(line.split(':')[1]));
      sub.cancel();
    }
  });

  int port;
  try {
    port = await completer.future.timeout(const Duration(seconds: 10));
  } on TimeoutException {
    print('PORT 检测超时\n');
    proc.kill();
    return;
  }
  await Future.delayed(const Duration(milliseconds: 300));

  final client = HttpClient();
  final base = 'http://localhost:$port';

  // health
  var req = await client.getUrl(Uri.parse('$base/health'));
  var resp = await req.close();
  print('GET /health → ${jsonDecode(await resp.transform(utf8.decoder).join())}');

  // all data
  req = await client.getUrl(Uri.parse('$base/data'));
  resp = await req.close();
  final all = jsonDecode(await resp.transform(utf8.decoder).join()) as List;
  print('\n═══ super_grades (${all.length} 条) ═══');
  for (final d in all) { print('  ${d["name"]}  ${d["score"]}分  ${d["grade"]}'); }

  // sorted
  req = await client.getUrl(Uri.parse('$base/data?sort=score&order=desc'));
  resp = await req.close();
  final sorted = jsonDecode(await resp.transform(utf8.decoder).join()) as List;
  print('\n═══ 按分数降序 ═══');
  for (final d in sorted) { print('  ${d["name"]} → ${d["score"]}分'); }

  // search
  req = await client.getUrl(Uri.parse('$base/data?q=张'));
  resp = await req.close();
  final q = jsonDecode(await resp.transform(utf8.decoder).join()) as List;
  print('\n═══ 搜索 "张" → ${q.length} 条 ═══');
  for (final d in q) { print('  ${d["name"]} ${d["score"]}分'); }

  client.close();
  proc.kill();
  print('');
}

// ═══ 5. AI 工具调用 ═══
Future<void> _toolDemo() async {
  final bridge = '$_pluginsDir${Platform.pathSeparator}super_app${Platform.pathSeparator}agent${Platform.pathSeparator}agent_bridge.py';
  final py = '$_pluginsDir${Platform.pathSeparator}super_app${Platform.pathSeparator}data${Platform.pathSeparator}plugin.py';
  if (!File(bridge).existsSync()) { print('agent_bridge.py 不存在\n'); return; }

  print('启动数据源...');
  final ds = await Process.start('python', [py]);

  // 等 PORT
  final completer = Completer<int>();
  late StreamSubscription<String> sub;
  sub = ds.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
    if (!completer.isCompleted && line.startsWith('PORT:')) {
      completer.complete(int.parse(line.split(':')[1]));
      sub.cancel();
    }
  });

  try {
    await completer.future.timeout(const Duration(seconds: 10));
  } on TimeoutException {
    print('PORT 超时\n');
    ds.kill();
    return;
  }
  await Future.delayed(const Duration(milliseconds: 300));

  // 第一轮
  print('═══ AI 调用: query_super_grades --sort score --order desc ═══');
  var r = await Process.run('python', [bridge, '--sort', 'score', '--order', 'desc']);
  var out = jsonDecode(r.stdout as String) as Map<String, dynamic>;
  if (out.containsKey('error')) { print('${out["error"]}\n'); ds.kill(); return; }
  for (final d in (out['results'] as List)) {
    print('  ${d["name"]} ${d["score"]}分 (${d["grade"]})');
  }

  // 第二轮
  print('\n═══ AI 调用: query_super_grades --query 李 ═══');
  r = await Process.run('python', [bridge, '--query', '李']);
  out = jsonDecode(r.stdout as String) as Map<String, dynamic>;
  for (final d in (out['results'] as List)) {
    print('  ${d["name"]} ${d["score"]}分');
  }

  ds.kill();
  print('');
}

// ═══ 6. 主题配色 ═══
void _themeShow() {
  for (final t in _themes.all) {
    print('═══ ${t.name} (${t.id}) ═══');
    print('  语义 (${t.semanticTokens.length}):');
    for (final key in ['primary', 'secondary', 'background', 'surface', 'text', 'textSecondary', 'error', 'success', 'border']) {
      final v = t.semantic(key);
      if (v != null) print('    ${key.padRight(14)} ████████  $v');
    }
    print('  组件 (${t.componentTokens.length}):');
    for (final name in t.componentTokens.keys.take(12)) {
      final c = t.component(name)!;
      print('    ${name.padRight(14)} ${c.entries.map((e) => '${e.key}=${e.value}').join(' ')}');
    }
  }
  print('');
}

// ═══ 7. 联动图 ═══
void _linkage() {
  print('''
  super_app/
    data/plugin.exe     → DataOrchestrator 数据源 (super_grades)
    module/manifest.json → ModuleRegistry 页面 (data[].type 引用数据源)
    agent/agent_bridge   → PluginBridge AI工具 → HTTP GET 数据源 → 过滤返回

  ocean_theme/
    theme/theme.json    → ThemeStore 全局暗色主题

  Agent 调用流程:
    AI → PluginBridge → agent_bridge.exe --query 李
      → HTTP GET data/plugin.exe:/data?q=李
      → 过滤 → stdout → AI

  加载顺序: data → module → agent → theme
  ''');
  print('当前: ${_reg.modules.length} 模块 · ${_themes.all.length} 主题 · ${_reg.buildRoutePaths().length} 路由');
  print('');
}

// ═══ 8. 目录树 ═══
void _tree([String? dir, String prefix = '  ']) {
  dir ??= _pluginsDir;
  final d = Directory(dir);
  if (!d.existsSync()) return;
  final entries = d.listSync()..sort((a, b) {
    if (a is Directory && b is! Directory) return -1;
    if (a is! Directory && b is Directory) return 1;
    return a.path.compareTo(b.path);
  });
  for (var i = 0; i < entries.length; i++) {
    final isLast = i == entries.length - 1;
    final name = entries[i].path.split(Platform.pathSeparator).last;
    print('$prefix${isLast ? "└──" : "├──"} $name');
    if (entries[i] is Directory) {
      _tree(entries[i].path, '$prefix${isLast ? "    " : "│   "}');
    }
  }
}

// ═══ 9. JSON 源码 ═══
void _raw() {
  stdout.write('模块 id > ');
  final m = _reg.findById(stdin.readLineSync()?.trim() ?? '');
  if (m == null) { print('未找到\n'); return; }
  print('\n${const JsonEncoder.withIndent('  ').convert(m.toJson())}\n');
}

// ═══ 10. 安装插件 ═══
Future<void> _installDemo() async {
  stdout.write('插件包路径或 URL > ');
  final path = stdin.readLineSync()?.trim() ?? '';
  if (path.isEmpty) { print('已取消\n'); return; }

  print('正在安装...');
  final result = await _installer.install(path);
  result.fold(
    (r) => print('✅ 安装成功: ${r.pluginId}\n'),
    (e) => print('❌ 安装失败: ${e.userMessage}\n'),
  );
}

// ═══ 11. 卸载插件 ═══
Future<void> _uninstallDemo() async {
  stdout.write('插件 id > ');
  final id = stdin.readLineSync()?.trim() ?? '';
  if (id.isEmpty) { print('已取消\n'); return; }

  final result = await _installer.uninstall(id);
  result.fold(
    (_) => print('✅ 已卸载: $id\n'),
    (e) => print('❌ 卸载失败: ${e.userMessage}\n'),
  );
}

// ═══ 12. OCR 识别 ═══
Future<void> _ocrDemo() async {
  stdout.write('图片路径 > ');
  final path = stdin.readLineSync()?.trim() ?? '';
  if (path.isEmpty) { print('已取消\n'); return; }

  print('OCR 识别中（DeepSeek → Tesseract 两级降级）...');
  final ocrPipeline = OcrPipeline(Dio());
  final text = await ocrPipeline.recognizeFile(path);
  if (text != null && text.isNotEmpty) {
    print('═══ 识别结果 ═══');
    print(text);
  } else {
    print('❌ 识别失败（文件不存在或 OCR 服务不可用）');
  }
  print('');
}

// ═══ 13. 更新检查 ═══
Future<void> _updateDemo() async {
  final updateService = UpdateService(Dio());

  // 宿主更新
  print('═══ 宿主更新检查 ═══');
  final (hasUpdate, version, url) = await updateService.checkForUpdate();
  print('  有新版本: $hasUpdate');
  if (version != null) print('  最新版本: $version');
  if (url != null) print('  下载地址: $url');

  // 各插件更新
  final plugins = _installer.listPlugins();
  if (plugins.isNotEmpty) {
    print('\n═══ 插件更新检查 (${plugins.length}) ═══');
    for (final p in plugins) {
      final check = await _installer.checkUpdate(p.id);
      print('  ${p.id.padRight(20)} v${p.version}  ${check.hasUpdate ? "🔔 有更新 → v${check.latestVersion}" : "✅ 最新"}');
    }
  }
  print('');
}

// ═══ 14. 插件列表 ═══
void _pluginList() {
  final plugins = _installer.listPlugins();
  if (plugins.isEmpty) {
    print('═══ 暂无已安装插件 ═══\n');
    return;
  }
  print('═══ 已安装插件 (${plugins.length}) ═══');
  for (final p in plugins) {
    final components = p.subComponents.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .join(', ');
    final status = p.isUnstable ? '⚠️ 不稳定' : '✅ 正常';
    print('  ${p.id.padRight(20)} v${p.version.padRight(8)} $status  组件: [$components]');
    print('    名称: ${p.name}  安装时间: ${p.installedAt.toLocal().toString().substring(0, 19)}');
  }
  print('');
}

// ═══ 15. 🌐 微服务网格 ═══
///
/// 模拟真实插件 .exe 如何通过 HTTP 调用 Core 微服务：
///   1. 读取 .core_port 发现服务地址
///   2. GET  /core/health         → 健康检查
///   3. GET  /core/plugins        → 查看已安装插件
///   4. POST /core/install        → 从 URL 安装插件
///   5. GET  /core/update/check   → 检查宿主更新
///   6. GET  /core/ocr/status     → OCR 状态
///   7. POST /core/uninstall/:id  → 卸载插件
///
/// 这就是插件 .exe 看到的平台：一个本地微服务网格，
/// 不需要把 Tesseract、签名校验、下载重试重新实现一遍。
Future<void> _httpServerDemo() async {
  final base = 'http://127.0.0.1:${_coreServer.port}';
  final client = HttpClient();

  // 辅助函数：GET 请求
  Future<Map<String, dynamic>> _get(String path) async {
    final req = await client.getUrl(Uri.parse('$base$path'));
    final resp = await req.close();
    final raw = await resp.transform(utf8.decoder).join();
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  // 辅助函数：POST 请求
  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final req = await client.postUrl(Uri.parse('$base$path'));
    req.headers.contentType = ContentType.json;
    final bytes = utf8.encode(jsonEncode(body));
    req.contentLength = bytes.length;
    req.add(bytes);
    final resp = await req.close();
    final raw = await resp.transform(utf8.decoder).join();
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  try {
    // ── 1. 端口发现 ──
    print('═══ 1. 端口发现 ═══');
    final portFile = File('.core_port');
    if (portFile.existsSync()) {
      final discoveredPort = portFile.readAsStringSync().trim();
      print('   读取 .core_port → $discoveredPort');
      print('   → http://127.0.0.1:$discoveredPort');
    }

    // ── 2. 健康检查 ──
    print('\n═══ 2. GET /core/health ═══');
    final health = await _get('/core/health');
    print('   status: ${health['status']}');
    print('   pluginsCount: ${health['pluginsCount']}');
    print('   ocrAvailable: ${health['ocrAvailable']}');

    // ── 3. 查看已安装插件 ──
    print('\n═══ 3. GET /core/plugins ═══');
    final pluginsResp = await _get('/core/plugins');
    final plugins = pluginsResp['plugins'] as List? ?? [];
    if (plugins.isEmpty) {
      print('   (无已安装插件)');
    } else {
      for (final p in plugins) {
        final m = p as Map;
        print('   ${m['id']}  v${m['version']}  ${m['isUnstable'] == true ? "⚠️" : "✅"}');
      }
    }

    // ── 4. 安装演示 ──
    stdout.write('\n─── 4. 安装插件 (回车跳过) ───\n   .plugin URL > ');
    final url = stdin.readLineSync()?.trim() ?? '';
    if (url.isNotEmpty) {
      print('   POST /core/install {url: "$url"} ...');
      final result = await _post('/core/install', {'url': url});
      if (result['success'] == true) {
        print('   ✅ 安装成功: ${result['pluginId']}');
      } else {
        print('   ❌ 安装失败: ${result['error'] ?? result['errorType']}');
      }
    }

    // ── 5. 宿主更新 ──
    print('\n═══ 5. GET /core/update/check ═══');
    final hostUpdate = await _get('/core/update/check');
    print('   hasUpdate: ${hostUpdate['hasUpdate']}');
    if (hostUpdate['latestVersion'] != null) {
      print('   latestVersion: ${hostUpdate['latestVersion']}');
    }

    // ── 6. OCR 状态 + 演示 ──
    print('\n═══ 6. GET /core/ocr/status ═══');
    final ocrStatus = await _get('/core/ocr/status');
    print('   deepseekAvailable: ${ocrStatus['deepseekAvailable']}');
    print('   tesseractAvailable: ${ocrStatus['tesseractAvailable']}');

    stdout.write('\n─── 7. OCR 识别 (回车跳过) ───\n   图片路径 > ');
    final imagePath = stdin.readLineSync()?.trim() ?? '';
    if (imagePath.isNotEmpty) {
      print('   POST /core/ocr {path: "$imagePath"} ...');
      final ocrResult = await _post('/core/ocr', {'path': imagePath});
      final text = ocrResult['text'] as String?;
      if (text != null && text.isNotEmpty) {
        print('   识别结果 (前 200 字符):');
        print('   ${text.substring(0, text.length > 200 ? 200 : text.length)}');
      } else {
        print('   ❌ 未识别到文字');
      }
    }

    // ── 8. 卸载演示 ──
    final currentPlugins = (_installer.listPlugins().map((p) => p.id)).toList();
    if (currentPlugins.isNotEmpty) {
      stdout.write('\n─── 8. 卸载插件 (回车跳过) ───\n   已安装: ${currentPlugins.join(", ")}\n   插件 id > ');
      final uninstallId = stdin.readLineSync()?.trim() ?? '';
      if (uninstallId.isNotEmpty) {
        print('   POST /core/uninstall/$uninstallId ...');
        final uninstallResult = await _post('/core/uninstall/$uninstallId', {});
        if (uninstallResult.containsKey('uninstalled')) {
          print('   ✅ 已卸载: ${uninstallResult['uninstalled']}');
        } else {
          print('   ❌ ${uninstallResult['error']}');
        }
      }
    }

    // ── 9. 微服务网格总览 ──
    print('\n╔══════════════════════════════════════════════╗');
    print('║   Core 微服务网格 —— 8 端点全部可用          ║');
    print('╠══════════════════════════════════════════════╣');
    print('║  GET  /core/health           健康检查        ║');
    print('║  POST /core/install          安装插件        ║');
    print('║  POST /core/uninstall/:id    卸载插件        ║');
    print('║  GET  /core/plugins          列出插件        ║');
    print('║  GET  /core/update/check/:id 检查插件更新    ║');
    print('║  GET  /core/update/check     检查宿主更新    ║');
    print('║  POST /core/ocr              OCR 识别        ║');
    print('║  GET  /core/ocr/status       OCR 状态        ║');
    print('╚══════════════════════════════════════════════╝');
    print('\n   插件 .exe 视角：读取 .core_port → HTTP → 获得全部能力');
  } finally {
    client.close();
  }
  print('');
}
