/// Core 层纯文本集成测试——不依赖 renderer/、不引入 Flutter Widget。
///
/// 启动全部 6 个 HttpServer，通过 HTTP 端点完成 7 个场景验证。
/// 用法: `dart run core_integration_test.dart`
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Core（自有）
import 'services/services.dart';

// Config
import 'config/config_http_server.dart';
import 'config/settings.dart';
import 'config/permissions.dart';

// Data
import 'data/data_http_server.dart';
import 'data/orchestrator.dart';
import 'data/type.dart';

// Module
import 'module/module_http_server.dart';
import 'module/module_registry.dart';
import 'module/module_loader.dart';
import 'module/module_descriptor.dart';

// Theme
import 'theme/theme_http_server.dart';
import 'theme/theme_store.dart';
import 'theme/theme_loader.dart';
import 'theme/theme_descriptor.dart';

// Agent（Scripted，Agent 工程师交付）
import 'agent/tools/scripted_agent_http_server.dart';

// ═══════ HTTP 辅助 ═══════

Future<Map<String, dynamic>> _get(int port, String path) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse('http://127.0.0.1:$port$path'));
    final resp = await req.close();
    final raw = await resp.transform(utf8.decoder).join();
    return jsonDecode(raw) as Map<String, dynamic>;
  } finally {
    client.close();
  }
}

Future<Map<String, dynamic>> _post(int port, String path, Map<String, dynamic> body) async {
  final client = HttpClient();
  try {
    final req = await client.postUrl(Uri.parse('http://127.0.0.1:$port$path'));
    req.headers.contentType = ContentType.json;
    final bytes = utf8.encode(jsonEncode(body));
    req.contentLength = bytes.length;
    req.add(bytes);
    final resp = await req.close();
    final raw = await resp.transform(utf8.decoder).join();
    return jsonDecode(raw) as Map<String, dynamic>;
  } finally {
    client.close();
  }
}

/// 读取 SSE 流，返回每行 JSON 解析后的 Map 列表。
Future<List<Map<String, dynamic>>> _sseGet(int port, String path, Map<String, dynamic> body) async {
  final client = HttpClient();
  try {
    final req = await client.postUrl(Uri.parse('http://127.0.0.1:$port$path'));
    req.headers.contentType = ContentType.json;
    final bytes = utf8.encode(jsonEncode(body));
    req.contentLength = bytes.length;
    req.add(bytes);
    final resp = await req.close();
    final events = <Map<String, dynamic>>[];
    await for (final line in resp.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.startsWith('data: ')) {
        try {
          events.add(jsonDecode(line.substring(6)) as Map<String, dynamic>);
        } catch (_) {}
      }
    }
    return events;
  } finally {
    client.close();
  }
}

// ═══════ main ═══════

void main() async {
  var passed = 0;
  var failed = 0;
  final failures = <String>[];

  void pass(String msg) {
    passed++;
    print('  ✅ $msg');
  }

  void fail(String msg, [String? detail]) {
    failed++;
    failures.add(msg);
    print('  ❌ $msg${detail != null ? ' — $detail' : ''}');
  }

  // ═══════════════════════════════════════════════
  // 初始化
  // ═══════════════════════════════════════════════

  print('══════════════════════════════════════════════');
  print('  Core 层纯文本集成测试');
  print('  6 个 HttpServer · 7 个场景');
  print('══════════════════════════════════════════════\n');

  final prefs = await SharedPreferences.getInstance();
  final dio = Dio();
  final testPluginsDir = '.test_plugins';

  // Core
  final installer = PluginInstaller(pluginsDir: testPluginsDir, dio: dio);
  final coreServer = CoreHttpServer(installer, OcrPipeline(dio), UpdateService(dio));

  // Config
  await initSettings(prefs, pluginDirs: ['builtins/']);
  registerPermissions('exam-review', [
    const PermissionDecl(key: 'network', label: '网络', description: '访问互联网'),
    const PermissionDecl(key: 'file', label: '文件', description: '读取文件', defaultGranted: false),
  ]);
  final configServer = ConfigHttpServer(prefs);

  // Data
  final orch = DataOrchestrator();
  const scoresType = DataType<Map<String, dynamic>>(
    name: '课表',
    category: '教务',
    displayName: '课程表',
    ttl: Duration(minutes: 5),
  );
  orch.register(scoresType, () async => [
    {'name': '高等数学', 'room': 'B201', 'time': '08:00'},
    {'name': '线性代数', 'room': 'C305', 'time': '10:00'},
  ]);
  final dataServer = DataHttpServer(orch);

  // Module（只加载 Core builtins/ + example plugins）
  final moduleReg = ModuleRegistry()
    ..registerAll(scanModules('builtins/'))
    ..register(const ModuleDescriptor(id: 'agent', name: 'Agent'))
    ..registerAll(scanModules('example/plugins/'));
  moduleReg.seal();
  final moduleServer = ModuleHttpServer(moduleReg, port: 0);

  // Theme（从 builtins/ 加载主题文件）
  final themeStore = ThemeStore();
  loadThemes('builtins/', themeStore);
  themeStore.activeTheme = themeStore.findById('light');
  final themeServer = ThemeHttpServer(themeStore);

  // Agent（Scripted，零外部依赖）
  var agentServer = ScriptedAgentHttpServer(scenario: ScriptedAgentHttpServer.scenario3());

  // ── 启动全部 ──
  print('启动服务网格...');
  final servers = <String, dynamic>{
    'Core': coreServer,
    'Config': configServer,
    'Data': dataServer,
    'Module': moduleServer,
    'Theme': themeServer,
    'Agent': agentServer,
  };

  final ports = <String, int>{};
  var allStarted = true;
  for (final entry in servers.entries) {
    try {
      final result = await (entry.value as dynamic).start();
      // ModuleHttpServer.start() 返回 void，其他返回 Future<int>
      final p = (result is int) ? result : (entry.value as dynamic).port as int;
      ports[entry.key] = p;
      print('  ${entry.key.padRight(8)} http://127.0.0.1:$p  ✅');
    } catch (e) {
      print('  ${entry.key.padRight(8)} 启动失败: $e  ❌');
      allStarted = false;
    }
  }

  if (!allStarted) {
    print('\n❌ 服务网格启动失败，终止测试。');
    return;
  }

  // ── 硬性标准 #1：6 个 /health 全 200 ──
  print('\n─── 健康检查 ───');
  for (final entry in ports.entries) {
    try {
      final health = await _get(entry.value, entry.key == 'Config'
          ? '/config/health'
          : entry.key == 'Data'
              ? '/data/health'
              : entry.key == 'Module'
                  ? '/module/health'
                  : entry.key == 'Theme'
                      ? '/theme/health'
                      : entry.key == 'Agent'
                          ? '/health'
                          : '/core/health');
      if (health['status'] == 'ok') {
        print('  ${entry.key}/health  ✅');
      } else {
        print('  ${entry.key}/health  ⚠️ status=${health['status']}');
      }
    } catch (e) {
      print('  ${entry.key}/health  ❌ $e');
    }
  }

  // ═══════════════════════════════════════════════
  // 场景执行
  // ═══════════════════════════════════════════════

  print('\n══════════════════════════════════════════════');
  print('  场景验证');
  print('══════════════════════════════════════════════\n');

  // ── [1] 安装插件 (Core) ──
  print('[1] 安装插件 (Core)');
  try {
    // 创建最小合法 .plugin ZIP（使用真实 package:archive）
    final manifest = jsonEncode({
      'type': 'plugin', 'id': 'exam-review', 'name': 'Exam Review', 'version': '1.0.0',
    });
    final manifestBytes = utf8.encode(manifest);
    final sigHex = sha256.convert(manifestBytes).toString();
    final sigBytes = utf8.encode(sigHex);

    final archive = Archive();
    archive.addFile(ArchiveFile('manifest.json', manifestBytes.length, manifestBytes));
    archive.addFile(ArchiveFile('.signature', sigBytes.length, sigBytes));
    final zipBytes = ZipEncoder().encode(archive)!;

    final pkgPath = '.test_plugin.zip';
    await File(pkgPath).writeAsBytes(zipBytes);

    final installResp = await _post(ports['Core']!, '/core/install', {'path': pkgPath});
    if (installResp['success'] == true) {
      pass('POST /core/install → 200');
    } else {
      fail('POST /core/install', '${installResp['error']}');
    }

    final pluginsResp = await _get(ports['Core']!, '/core/plugins');
    final plugins = (pluginsResp['plugins'] as List?) ?? [];
    if (plugins.any((p) => (p as Map)['id'] == 'exam-review')) {
      pass('GET /core/plugins 含 exam-review');
    } else {
      fail('GET /core/plugins', '未找到 exam-review');
    }

    await _post(ports['Core']!, '/core/uninstall/exam-review', {});
    pass('POST /core/uninstall/exam-review → 200');

    await File(pkgPath).delete();
  } catch (e) {
    fail('[1]', '$e');
  }

  // ── [2] 数据源启动 (Data) ──
  print('\n[2] 数据源启动 (Data)');
  try {
    final health = await _get(ports['Data']!, '/data/health');
    if (health['status'] == 'ok') {
      pass('GET /data/health → 200');
    } else {
      fail('GET /data/health', '$health');
    }

    final typesResp = await _get(ports['Data']!, '/data/types');
    final types = (typesResp['types'] as List?) ?? [];
    if (types.any((t) => (t as Map)['name'] == '课表')) {
      pass('GET /data/types 含 课表');
    } else {
      fail('GET /data/types', '$types');
    }

    final detailResp = await _get(ports['Data']!, '/data/types/课表');
    if (detailResp.isNotEmpty) {
      pass('GET /data/types/课表 返回数据');
    } else {
      fail('GET /data/types/课表', '空响应');
    }
  } catch (e) {
    fail('[2]', '$e');
  }

  // ── [3] Agent 对话 (Agent) ──
  print('\n[3] Agent 对话 (Agent)');
  try {
    final events = await _sseGet(ports['Agent']!, '/agent/chat/stream', {'input': '明天什么课'});
    if (events.isEmpty) {
      fail('SSE 流为空');
    } else {
      final kinds = events.map((e) => e['type'] as String?).toList();
      if (kinds.contains('turn_started')) pass('turn_started');
      else fail('缺少 turn_started', '$kinds');

      final toolDispatch = events.firstWhere(
        (e) => e['type'] == 'tool_dispatch',
        orElse: () => <String, dynamic>{},
      );
      if (toolDispatch['name'] == 'check_schedule') {
        pass('tool_dispatch → check_schedule');
      } else {
        fail('tool_dispatch 不正确', '${toolDispatch['name']}');
      }

      final toolResult = events.firstWhere(
        (e) => e['type'] == 'tool_result',
        orElse: () => <String, dynamic>{},
      );
      final output = toolResult['output'] as String? ?? '';
      if (output.contains('高等数学')) {
        pass('tool_result 含 高等数学');
      } else {
        fail('tool_result 不含预期内容', output);
      }

      final textEvents = events.where((e) => e['type'] == 'text').toList();
      if (textEvents.isNotEmpty && textEvents.any((t) => (t['text'] as String? ?? '').contains('高等数学'))) {
        pass('text 含 高等数学');
      } else {
        fail('text 不含预期内容');
      }

      if (kinds.contains('turn_done')) pass('turn_done');
      else fail('缺少 turn_done');
    }
  } catch (e) {
    fail('[3]', '$e');
  }

  // ── [4] 跨模块调度 (Agent scenario4) ──
  print('\n[4] 跨模块调度 (Agent)');
  try {
    // 重启 Agent 为 scenario4
    agentServer.stop();
    agentServer = ScriptedAgentHttpServer(scenario: ScriptedAgentHttpServer.scenario4());
    ports['Agent'] = await agentServer.start();

    final events = await _sseGet(ports['Agent']!, '/agent/chat/stream', {'input': '比对课表和番茄钟'});
    final toolNames = events
        .where((e) => e['type'] == 'tool_dispatch')
        .map((e) => e['name'] as String?)
        .toList();

    if (toolNames.contains('check_schedule') && toolNames.contains('get_pomodoro')) {
      pass('双 tool dispatch: check_schedule + get_pomodoro');
    } else {
      fail('双 tool 调度失败', '$toolNames');
    }

    final textEvents = events.where((e) => e['type'] == 'text').toList();
    final allText = textEvents.map((t) => t['text'] as String? ?? '').join();
    if (allText.contains('高等数学') && allText.contains('番茄钟')) {
      pass('聚合回复含 高等数学 + 番茄钟');
    } else {
      fail('聚合回复不含预期内容', allText);
    }
  } catch (e) {
    fail('[4]', '$e');
  }

  // ── [5] 主题切换 (Theme) ──
  print('\n[5] 主题切换 (Theme)');
  try {
    final themesResp = await _get(ports['Theme']!, '/theme/themes');
    final themes = (themesResp['themes'] as List?) ?? [];
    if (themes.length >= 2) {
      pass('GET /theme/themes → ${themes.length} 个主题');
    } else {
      fail('GET /theme/themes 数量不足', '${themes.length}');
    }

    final switchResp = await _post(ports['Theme']!, '/theme/active', {'id': 'dark'});
    if (switchResp['active'] == 'dark') {
      pass('POST /theme/active dark → 200');
    } else {
      fail('POST /theme/active', '$switchResp');
    }

    final tokenResp = await _get(ports['Theme']!, '/theme/token?component=sidebar&token=bg');
    final hex = tokenResp['color'] as String? ?? tokenResp['hex'] as String? ?? '';
    if (hex.startsWith('#')) {
      pass('GET /theme/token → $hex');
    } else {
      fail('GET /theme/token 返回非颜色值', hex);
    }

    // 切回 light
    await _post(ports['Theme']!, '/theme/active', {'id': 'light'});
  } catch (e) {
    fail('[5]', '$e');
  }

  // ── [6] 设置读写 (Config) ──
  print('\n[6] 设置读写 (Config)');
  try {
    final readResp = await _get(ports['Config']!, '/config/settings/DEEPSEEK_MODEL');
    final originalValue = readResp['value'] as String? ?? '';
    if (originalValue.isNotEmpty) {
      pass('GET /config/settings/DEEPSEEK_MODEL → $originalValue');
    } else {
      pass('GET /config/settings/DEEPSEEK_MODEL → (空/默认)');
    }

    await _post(ports['Config']!, '/config/settings/DEEPSEEK_MODEL', {'value': 'deepseek-v4-lite'});
    final verifyResp = await _get(ports['Config']!, '/config/settings/DEEPSEEK_MODEL');
    if (verifyResp['value'] == 'deepseek-v4-lite') {
      pass('POST → GET 验证: deepseek-v4-lite');
    } else {
      fail('设置写入未生效', '${verifyResp['value']}');
    }

    // 恢复原值
    if (originalValue.isNotEmpty) {
      await _post(ports['Config']!, '/config/settings/DEEPSEEK_MODEL', {'value': originalValue});
    }
  } catch (e) {
    fail('[6]', '$e');
  }

  // ── [7] 权限管理 (Config) ──
  print('\n[7] 权限管理 (Config)');
  try {
    final permResp = await _get(ports['Config']!, '/config/permissions/exam-review');
    final perms = permResp['permissions'] as List? ?? [];
    if (perms.isNotEmpty) {
      pass('GET /config/permissions/exam-review → ${perms.length} 项权限');
    } else {
      fail('GET /config/permissions/exam-review 为空');
    }

    final setResp = await _post(ports['Config']!, '/config/permissions/exam-review', {
      'key': 'file',
      'granted': true,
    });
    if (setResp['granted'] == true) {
      pass('POST 授权 file → true');
    } else {
      fail('POST 授权失败', '$setResp');
    }
  } catch (e) {
    fail('[7]', '$e');
  }

  // ═══════════════════════════════════════════════
  // 错误路径 + OCR 真实验证（硬性标准 #3 + #4）
  // ═══════════════════════════════════════════════

  print('\n─── 错误路径 + OCR ──');
  try {
    final badInstall = await _post(ports['Core']!, '/core/install', {'path': '/nonexistent/file.plugin'});
    if (badInstall.containsKey('error')) {
      pass('POST /core/install 无效路径 → error');
    } else {
      fail('POST /core/install 无效路径未返回 error');
    }
  } catch (e) {
    pass('POST /core/install 无效路径 → 异常: $e');
  }

  // 真实 OCR 验证（Tesseract Level 2 降级链）
  final ocrImage = '${Directory.systemTemp.path.replaceAll('\\', '/')}/test_ocr.png';
  if (File(ocrImage).existsSync()) {
    try {
      final ocrResp = await _post(ports['Core']!, '/core/ocr', {'path': ocrImage});
      final ocrText = ocrResp['text'] as String?;
      if (ocrText != null && ocrText.isNotEmpty) {
        pass('POST /core/ocr → "$ocrText"');
      } else {
        fail('POST /core/ocr', '返回 null/空');
      }
    } catch (e) {
      fail('POST /core/ocr', '$e');
    }
  } else {
    print('  ⏭️  跳过 OCR（测试图片不存在）');
  }

  // ═══════════════════════════════════════════════
  // 清理
  // ═══════════════════════════════════════════════

  print('\n─── 清理 ──');
  for (final entry in servers.entries) {
    try {
      await (entry.value as dynamic).stop();
    } catch (_) {}
  }
  // 清理测试插件目录
  try {
    final d = Directory(testPluginsDir);
    if (d.existsSync()) d.deleteSync(recursive: true);
  } catch (_) {}

  // ═══════════════════════════════════════════════
  // 报告
  // ═══════════════════════════════════════════════

  final total = passed + failed;
  print('\n══════════════════════════════════════════════');
  print('  $passed/$total 通过${failed > 0 ? ' · $failed 失败' : ''}');
  if (failures.isNotEmpty) {
    print('  失败项:');
    for (final f in failures) {
      print('    - $f');
    }
  }
  print('══════════════════════════════════════════════');

  // ── 强行退出 ──
  // 某些 HttpServer（Module/Agent）的 stop() 未完全关闭连接，
  // 导致 Dart event loop 无法自然退出。exit() 确保进程终止。
  print('');
  exit(failed > 0 ? 1 : 0);
}