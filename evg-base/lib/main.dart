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

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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
import 'package:evergreen_base/core/data/cache.dart';
import 'package:evergreen_base/core/data/orchestrator.dart';
import 'package:evergreen_base/core/data/type.dart';
import 'package:evergreen_base/core/log.dart';
import 'package:evergreen_base/core/data/data_http_server.dart';
import 'package:evergreen_base/core/data/register_data_source.dart';
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
import 'package:evergreen_base/core/agent/tools/data_query.dart';
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
import 'package:evergreen_base/core/utils/python_env.dart';
import 'package:evergreen_base/providers.dart';
import 'package:evergreen_base/renderer/app/service/providers/renderer_providers.dart';
import 'package:media_kit/media_kit.dart';
import 'package:webview_windows/webview_windows.dart';

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

/// 插件目录（位于项目根上级，统一存放所有模块/主题/设置）。
String get _pluginsDir => p.join(_projectRoot, '..', 'plugins');

/// 文本模式下各 HttpServer 实际端口（main 启动后填充，app.dart 读取）。
final textModeServerPorts = <String, int>{};

/// 扫描 plugins/ 下所有 module/manifest.json，提取 schemaVersion="2.0" 的原始 JSON。
/// 结果存入 [out] map，key 为模块 id。
/// 扫描 data 插件 manifest.json，注册 DataType（CLI fetcher）。
/// 在模块加载前调用，避免组件渲染时数据源尚未注册的时序问题。
///
/// 注册逻辑委托给 [registerDataSourcesFromManifest]（与运行期热注册同一份契约，
/// 见 register_data_source.dart），避免双实现漂移。
void _scanAndRegisterDataSources(String pluginsDir, DataOrchestrator orch) {
  final dir = Directory(pluginsDir);
  if (!dir.existsSync()) return;

  for (final entity in dir.listSync()) {
    if (entity is! Directory) continue;
    final names = registerDataSourcesFromManifest(
      orch: orch,
      pluginDir: entity.path,
      projectRoot: _projectRoot,
    );
    if (names.isNotEmpty) {
      Log().info('DataSource 扫描完成',
          data: {'plugin': p.basename(entity.path), 'count': names.length, 'types': names});
    }
  }
}

void _scanV2Manifests(String pluginsDir, Map<String, Map<String, dynamic>> out) {
  final dir = Directory(pluginsDir);
  if (!dir.existsSync()) return;
  for (final entity in dir.listSync()) {
    if (entity is! Directory) continue;
    final manifestFile = File(p.join(entity.path, 'module', 'manifest.json'));
    if (!manifestFile.existsSync()) continue;
    try {
      final map = jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
      if (map['type'] != 'module') continue;
      if (map['schemaVersion'] == '2.0') {
        out[map['id'] as String] = map;
      }
    } catch (e) {
      stderr.writeln('[main] V2 清单解析失败 ${manifestFile.path}: $e');
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Web 不支持 dart:io（HttpServer / Process / File），提前退出 ──
  if (kIsWeb) {
    runApp(const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Text(
            'Evergreen 需要桌面环境运行\n\n不支持 Web / Chrome',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.white54),
          ),
        ),
      ),
    ));
    return;
  }

  // ── 桌面窗口（跳过 Web：dart:io Platform 不支持）──
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
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

  // ── media_kit 初始化（libmpv，Windows/macOS/Linux 视频播放） ──
  try {
    MediaKit.ensureInitialized();
    stderr.writeln('[main] media_kit 初始化成功（libmpv 视频播放）');
  } catch (e) {
    stderr.writeln('[main] ⚠ media_kit 初始化失败，视频播放不可用: $e');
  }

  // ── WebView2 环境：开启 CDP 远程调试端口 ──
  // 供爬虫模块通过 CDP Network 域全量捕获 HTTP 请求。
  // 端口 9222 是 Chrome DevTools 标准端口，仅监听 127.0.0.1，无外部暴露风险。
  try {
    await WebviewController.initializeEnvironment(
      additionalArguments: '--remote-debugging-port=9222',
    );
    stderr.writeln('[main] WebView2 环境已初始化（CDP port 9222）');
  } catch (e) {
    stderr.writeln('[main] ⚠ WebView2 环境初始化失败: $e');
    stderr.writeln('[main]    CDP 网络捕获将不可用，爬虫模块降级到 JS 方案。');
  }

  // ── SharedPreferences ──
  SharedPreferences prefs;
  try {
    prefs = await SharedPreferences.getInstance();
    stderr.writeln('[main] SharedPreferences 初始化成功（持久化存储）');
  } catch (e) {
    stderr.writeln('[main] SharedPreferences 不可用（无 Windows 平台实现？）: $e');
    stderr.writeln('[main] 将使用内存存储回退方案（设置不会持久化）。');
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  }

  // ── 设置初始化（扫描 plugins/ 下所有 config.json，写入默认值） ──
  await initSettings(
    prefs,
    pluginDirs: [_pluginsDir],
  );

  // ── 数据谱仪器 ──
  await Cache.getInstance(); // 初始化缓存（磁盘持久化）
  final orchestrator = DataOrchestrator();
  orchestrator.refreshStatusFromDisk();

  // ── 主题（从 plugins/ 加载） ──
  final themeStore = ThemeStore();
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
  toolRegistry.register(DataQueryTool(orchestrator: orchestrator));
  // 注册嵌入式 Python 解释器工具——多级回退发现
  // ① .greenix/python/python.exe（同学打包的嵌入式 Python，最高优先级）
  // ② scripts/python/python.exe（安装包自带）
  // ③ 用户配置路径 → 系统 PATH（python3 → python → py -3）
  final bundledCandidate = p.join(greenixPythonDir, 'python.exe');
  final resolvedPython = await resolvePythonExe(configuredPath: bundledCandidate);
  if (resolvedPython != null) {
    // workDir: 嵌入式 Python 用其所在目录；系统 PATH 命令用 workspace
    final isBundled = resolvedPython == bundledCandidate ||
        p.isAbsolute(resolvedPython);
    // 当是完整路径时用父目录，否则（系统 PATH 命令如 python/python3）用 workspace
    final workDir = isBundled
        ? Directory(resolvedPython).parent.path
        : aiWorkspace;
    toolRegistry.register(PythonRunnerTool(
      pythonExePath: resolvedPython,
      pythonWorkDir: workDir,
      workspaceDir: aiWorkspace,
    ));
    stderr.writeln('[main] PythonRunnerTool 已注册 ($resolvedPython, workDir: $workDir)');
  } else {
    stderr.writeln('[main] ⚠ Python 解释器未找到——已尝试 .greenix/python/、scripts/python/、系统 PATH。');
    stderr.writeln('[main]    AI 将无法执行 Python 代码。安装 Python 3.8+ 或放置 python.exe 到 .greenix/python/。');
  }
  // 注册插件 Agent 工具
  PluginBridge.registerAll(toolRegistry, Directory(_pluginsDir));
  stderr.writeln('[main] Agent 工具: ${toolRegistry.all().map((t) => t.name).toList()}');

  // ── 加载用户禁用的工具（持久化） ──
  final toolDisabledRaw = prefs.getString('tool_disabled') ?? '';
  final toolDisabled = <String>{};
  if (toolDisabledRaw.isNotEmpty) {
    toolDisabled.addAll(toolDisabledRaw.split(','));
  }
  for (final name in toolDisabled) {
    toolRegistry.disable(name);
  }
  if (toolDisabled.isNotEmpty) {
    stderr.writeln('[main] 已禁用工具: ${toolDisabled.toList()}');
  }

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
      final pVal = (r is Future) ? await r : (entry.value as dynamic).port;
      final port = pVal is int ? pVal : 0;
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

  // ── 扫描 V2 原始清单（独立于 ModuleLoader，用于 HTML 渲染） ──
  final v2Manifests = <String, Map<String, dynamic>>{};
  _scanV2Manifests(_pluginsDir, v2Manifests);
  stderr.writeln('[main] V2 清单: ${v2Manifests.keys.toList()}');

  // ── 扫描数据插件 → 注册 DataType（CLI fetcher，模块加载前完成）──
  _scanAndRegisterDataSources(_pluginsDir, orchestrator);

  // ── 模块注册中心（HttpServer 就绪后再启动 .exe，确保端口文件已存在） ──
  final registry = ModuleRegistry();

  final loaders = await scanAndLoadModules(_pluginsDir, registry, projectRoot: _projectRoot);

  for (final loader in loaders) {
    if (loader.isRunning && loader.port != null) {
      textModeServerPorts[loader.manifest.id] = loader.port!;
      stderr.writeln('[main] 模块 ${loader.manifest.id} → http://127.0.0.1:${loader.port}');
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

  // 选取默认主题 → 写入 ThemeStore（ChangeNotifierProvider 自动通知 UI）
  final defaultTheme = themeStore.findById('default') ??
      (themeStore.all.isNotEmpty ? themeStore.all.first : null);
  if (defaultTheme != null) {
    themeStore.activeTheme = defaultTheme;
  }

  // ── 启动 Flutter 窗口（纯 Dart 渲染）──
  runApp(
    ProviderScope(
      overrides: [
        // SharedPreferences（agent 运行时、设置等依赖）
        sharedPreferencesProvider.overrideWith((ref) => prefs),

        // 模块注册中心
        moduleRegistryProvider.overrideWith((ref) => registry),

        // 数据谱仪器
        dataOrchestratorProvider.overrideWith((ref) => orchestrator),

        // 配置层 HTTP 服务器（供热注册配置项）
        configHttpServerProvider.overrideWith((ref) => configServer),

        // 插件目录（供渲染层构造模块工作目录）
        pluginsDirProvider.overrideWith((ref) => _pluginsDir),

        // 模块端口映射（供渲染层通过 HTTP 与模块 .exe 通信）
        modulePortsProvider.overrideWith((ref) => textModeServerPorts),

        // Agent Controller——Chat 视图通过此 provider 发送消息
        agentControllerProvider.overrideWith((ref) => controller),

        // Agent 工具注册表——供工具管理面板读取/控制
        toolRegistryProvider.overrideWith((ref) => toolRegistry),

        // 已禁用的工具名称——持久化状态
        toolDisabledProvider.overrideWith((ref) => toolDisabled),

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

        // 主题存储——ChangeNotifierProvider，HTTP 切换主题后自动通知 UI 刷新
        themeStoreProvider.overrideWith((ref) => themeStore),

        // V2 原始 manifest JSON（HTML 渲染引擎使用）
        v2ManifestProvider.overrideWith((ref) => v2Manifests),
      ],
      child: const EvergreenApp(),
    ),
  );
}
