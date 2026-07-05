/// Evergreen 2.0 启动入口——初始化设置、模块、数据、主题，注入 ProviderScope。
///
/// 启动顺序：
/// 1. Flutter 绑定 + 桌面窗口
/// 2. SharedPreferences + 设置初始化
/// 3. 模块注册中心（内置 + 插件）
/// 4. 数据谱仪器
/// 5. 主题加载
/// 6. ProviderScope → runApp
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:dio/dio.dart';
import 'package:evergreen_base/app.dart';
import 'package:evergreen_base/core/config/config.dart';
import 'package:evergreen_base/core/config/config_http_server.dart';
import 'package:evergreen_base/core/module/module_registry.dart';
import 'package:evergreen_base/core/module/module_loader.dart';
import 'package:evergreen_base/core/module/module_http_server.dart';
import 'package:evergreen_base/core/data/orchestrator.dart';
import 'package:evergreen_base/core/data/data_http_server.dart';
import 'package:evergreen_base/core/theme/theme_loader.dart';
import 'package:evergreen_base/core/theme/theme_store.dart';
import 'package:evergreen_base/core/theme/theme_http_server.dart';
import 'package:evergreen_base/core/agent/agent/session.dart' as agent;
import 'package:evergreen_base/core/agent/controller/controller.dart' as agent;
import 'package:evergreen_base/core/agent/event.dart' as agent;
import 'package:evergreen_base/core/agent/tool.dart' as agent;
import 'package:evergreen_base/core/agent/provider.dart' as agent;
import 'package:evergreen_base/core/agent/tools/agent_http_server.dart';
import 'package:evergreen_base/core/agent/tools/plugin_bridge.dart';
import 'package:evergreen_base/core/agent/tools/read_global_memory.dart';
import 'package:evergreen_base/core/agent/tools/write_global_memory.dart';
import 'package:evergreen_base/core/agent/tools/web_search.dart';
import 'package:evergreen_base/core/agent/tools/read_file.dart';
import 'package:evergreen_base/core/agent/tools/write_file.dart';
import 'package:evergreen_base/core/agent/tools/python_runner_tool.dart';
import 'package:evergreen_base/core/agent/skill/skill.dart';
import 'package:evergreen_base/core/agent/memory/file_memory_store.dart';
import 'package:evergreen_base/core/agent/file_session_store.dart';
import 'package:evergreen_base/core/agent/session_manager.dart';
import 'package:evergreen_base/core/services/core_http_server.dart';
import 'package:evergreen_base/core/services/plugin_installer.dart';
import 'package:evergreen_base/core/services/ocr_pipeline.dart';
import 'package:evergreen_base/core/services/update_service.dart';
import 'package:evergreen_base/core/utils/greenix_path.dart';
import 'package:evergreen_base/providers.dart';
import 'package:evergreen_base/renderer/shared/renderer_providers.dart';

// ═══════ 项目根 ═══════

/// 沿目录树向上查找 `pubspec.yaml`，定位项目根目录。
/// 从可执行文件自身路径出发（而非 Directory.current），确保双击启动时也能正确解析。
String _findProjectRoot() {
  var dir = Directory(p.dirname(Platform.resolvedExecutable));
  while (true) {
    if (File(p.join(dir.path, 'pubspec.yaml')).existsSync()) return dir.path;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  // 回退：尝试当前工作目录
  var cwd = Directory.current;
  while (true) {
    if (File(p.join(cwd.path, 'pubspec.yaml')).existsSync()) return cwd.path;
    final parent = cwd.parent;
    if (parent.path == cwd.path) break;
    cwd = parent;
  }
  return Directory.current.path;
}

/// 项目根目录（首次访问时计算）。
late final String _projectRoot = _findProjectRoot();

// ═══════ 路径常量 ═══════

/// 内置模块/主题/设置统一目录。
String get _builtinsDir => p.join(_projectRoot, 'lib/core/builtins');

/// 插件目录（plugins/ 位于 evg-base/ 的父目录，以实现核心与插件的隔离）。
String get _pluginsDir => p.join(_projectRoot, '..', 'plugins');

/// 文本模式下各 HttpServer 实际端口（main 启动后填充，app.dart 读取）。
final textModeServerPorts = <String, int>{};

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── 桌面窗口 ──
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    try {
      await windowManager.ensureInitialized();
      await windowManager.setMinimumSize(const Size(900, 600));
      await windowManager.setSize(const Size(1200, 800));
      await windowManager.setTitle('Evergreen 多工具集成版');
      await windowManager.center();
      await windowManager.show();
    } catch (e) {
      stderr.writeln('[main] windowManager 初始化失败（缺少 screen_retriever 等插件？）: $e');
      stderr.writeln('[main] 窗口将以默认尺寸和位置启动。');
    }
  }

  // ── Greenix 路径 ──
  initGreenixPaths();

  // ── SharedPreferences ──
  SharedPreferences prefs;
  try {
    prefs = await SharedPreferences.getInstance();
    stderr.writeln('[main] SharedPreferences 初始化成功（持久化存储）');
  } catch (e) {
    stderr.writeln('[main] SharedPreferences 不可用（无 Windows 平台实现？）: $e');
    stderr.writeln('[main] 将使用内存存储回退方案（设置不会持久化）。');
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  }

  // ── 设置初始化（内置 + 插件 config.json，写入默认值） ──
  await initSettings(
    prefs,
    pluginDirs: [_builtinsDir, _pluginsDir],
  );

  // ── 数据谱仪器 ──
  final orchestrator = DataOrchestrator();
  orchestrator.refreshStatusFromDisk();

  // ── 主题（内置 → 插件，后者覆盖同 id） ──
  final themeStore = ThemeStore();
  loadThemes(_builtinsDir, themeStore);
  loadThemes(_pluginsDir, themeStore);

  // ── ⚠️ 启动各模块 HttpServer 必须在模块 .exe 之前 —— 确保 .xxx_port 文件已写入 ──
  final dio = Dio();
  final installer = PluginInstaller(pluginsDir: _pluginsDir, dio: dio);
  final ocr = OcrPipeline(dio);
  final updater = UpdateService(dio);

  final coreServer = CoreHttpServer(installer, ocr, updater);
  final configServer = ConfigHttpServer(prefs);
  final dataServer = DataHttpServer(orchestrator);
  final themeServer = ThemeHttpServer(themeStore);

  // ── Agent 运行时（真实 DeepSeek API） ──
  stderr.writeln('[main] 初始化 Agent 运行时...');
  final apiKey = getSetting(prefs, 'DEEPSEEK_API_KEY');
  if (apiKey.isEmpty) {
    stderr.writeln('[main] ⚠ DEEPSEEK_API_KEY 未设置！AI 对话将不可用。请在设置中配置 API Key。');
  }
  final dioAgent = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 120),
  ));
  final provider = agent.DeepSeekProvider(dio: dioAgent, apiKey: apiKey);
  final toolRegistry = agent.Registry();
  final memoryStore = FileMemoryStore(greenixMemoriesDir);
  final sessionStore = FileSessionStore(greenixSessionsDir);
  final skillIndex = SkillIndex();
  // 扫描内置 Skill
  final skillLoader = SkillLoader([greenixSkillsDir]);
  skillIndex.addAll(skillLoader.loadAll());
  // 注册内置工具
  final aiWorkspace = greenixWorkspaceDir('ai-assistant');
  Directory(aiWorkspace).createSync(recursive: true);
  toolRegistry.register(ReadGlobalMemoryTool(memoryStore));
  toolRegistry.register(WriteGlobalMemoryTool(memoryStore));
  toolRegistry.register(WebSearchTool(dioAgent));
  toolRegistry.register(ReadFileTool(workspaceDir: aiWorkspace));
  toolRegistry.register(WriteFileTool(workspaceDir: aiWorkspace));
  // 注册嵌入式 Python 解释器工具 (.greenix/python/)
  final pythonExe = p.join(greenixPythonDir, 'python.exe');
  if (File(pythonExe).existsSync()) {
    toolRegistry.register(PythonRunnerTool(
      pythonExePath: pythonExe,
      pythonWorkDir: greenixPythonDir,
    ));
    stderr.writeln('[main] PythonRunnerTool 已注册 ($pythonExe)');
  } else {
    stderr.writeln('[main] ⚠ Python 解释器未找到: $pythonExe');
  }
  // 注册插件 Agent 工具
  PluginBridge.registerAll(toolRegistry, Directory(_pluginsDir));
  stderr.writeln('[main] Agent 工具: ${toolRegistry.all().map((t) => t.name).toList()}');

  final session = agent.Session();
  final sink = agent.StreamEventSink();
  final controller = agent.Controller(
    provider: provider,
    registry: toolRegistry,
    sink: sink,
    session: session,
    skillIndex: skillIndex,
  );

  final agentServer = AgentHttpServer(
    controller: controller,
    eventSink: sink,
    session: session,
    registry: toolRegistry,
    portFile: p.join(_projectRoot, '.agent_port'),
    memoryStore: memoryStore,
    skillIndex: skillIndex,
  );
  stderr.writeln('[main] AgentHttpServer 就绪 (DeepSeek v4-pro)');

  final servers = <String, dynamic>{
    'Core': coreServer, 'Config': configServer, 'Data': dataServer,
    'Theme': themeServer, 'Agent': agentServer,
  };

  // 注册进程退出时清理所有端口
  ProcessSignal.sigint.watch().listen((_) {
    stderr.writeln('[main] 收到 SIGINT，关闭所有服务...');
    for (final entry in servers.entries) {
      try { (entry.value as dynamic).stop(); } catch (_) {}
    }
    exit(0);
  });

  for (final entry in servers.entries) {
    try {
      final r = (entry.value as dynamic).start();
      final p = (r is Future) ? await r : (entry.value as dynamic).port;
      final port = p is int ? p : 0;
      textModeServerPorts[entry.key] = port;
      // 统一写入端口发现文件到 _projectRoot
      final portFileName = '.${entry.key.toLowerCase()}_port';
      File(p.join(_projectRoot, portFileName)).writeAsStringSync('$port');
      stderr.writeln('[main] ${entry.key}HttpServer → port $port → $portFileName');
    } catch (e) {
      stderr.writeln('[main] 启动 ${entry.key}HttpServer 失败: $e');
      textModeServerPorts[entry.key] = 0;
    }
  }

  // ── 模块注册中心（HttpServer 就绪后再启动 .exe，确保端口文件已存在） ──
  final registry = ModuleRegistry();

  final builtinLoaders = await scanAndLoadModules(_builtinsDir, registry, projectRoot: _projectRoot);
  await scanAndLoadModules(_pluginsDir, registry, projectRoot: _projectRoot);

  for (final loader in builtinLoaders) {
    if (loader.isRunning && loader.port != null) {
      textModeServerPorts[loader.manifest.id] = loader.port!;
      stderr.writeln('[main] 内置模块 ${loader.manifest.id} → http://127.0.0.1:${loader.port}');
    }
  }
  registry.seal();
  stderr.writeln('[main] 模块注册完毕: ${registry.modules.map((m) => m.id).toList()}');

  // ModuleHttpServer 在 registry 创建后启动
  final moduleServer = ModuleHttpServer(registry, port: 0);
  try {
    final mp = await moduleServer.start();
    textModeServerPorts['Module'] = mp;
  } catch (e) {
    stderr.writeln('[main] 启动 ModuleHttpServer 失败: $e');
    textModeServerPorts['Module'] = 0;
  }

  // 选取默认主题
  final defaultTheme = themeStore.findById('default') ??
      (themeStore.all.isNotEmpty ? themeStore.all.first : null);

  // ── 启动应用 ──
  runApp(
    ProviderScope(
      overrides: [
        // SharedPreferences（agent 运行时、设置等依赖）
        sharedPreferencesProvider.overrideWith((ref) => prefs),

        // 模块注册中心
        moduleRegistryProvider.overrideWith((ref) => registry),

        // 数据谱仪器
        dataOrchestratorProvider.overrideWith((ref) => orchestrator),

        // 插件目录（供渲染层构造模块工作目录）
        pluginsDirProvider.overrideWith((ref) => _pluginsDir),

        // 内置模块目录（PLAN_NOW composite 模式用）
        builtinsDirProvider.overrideWith((ref) => _builtinsDir),

        // Agent Controller——Chat 视图通过此 provider 发送消息
        agentControllerProvider.overrideWith((ref) => controller),

        // Agent 事件流——Chat 视图订阅此流以接收响应
        agentEventStreamProvider.overrideWith((ref) => sink.stream),

        // 记忆 & Skill 目录路径
        memoriesDirProvider.overrideWith((ref) => greenixMemoriesDir),
        skillsDirProvider.overrideWith((ref) => greenixSkillsDir),

        // 全局记忆存储——供全局记忆页面读写
        memoryStoreProvider.overrideWith((ref) => memoryStore),

        // 会话持久化存储——供会话列表/切换/创建使用
        sessionStoreProvider.overrideWith((ref) => sessionStore),

        // Skill 索引——供技能管理页面列举
        skillIndexProvider.overrideWith((ref) => skillIndex),

        // 主题描述符
        if (defaultTheme != null)
          themeDescriptorProvider.overrideWith((ref) => defaultTheme),
      ],
      child: const EvergreenApp(),
    ),
  );
}
