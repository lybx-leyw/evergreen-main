/// Evergreen 2.0 启动序列（AppBootstrap）——把 main() 单体拆为可定位的步骤列表。
///
/// 设计目标（docs/错误排查契约-v1.md）：
/// - 任意启动步骤失败，1 行 `[BOOT]` 日志即可定位到步骤 + errorId；
/// - 每步保留原有降级逻辑（内部 catch → 回退 → Ok），runner 兜底捕获
///   未捕获异常 → Err（含 AppError 序列化）；
/// - 结束输出 `[BOOT] 完成: 成功 X/N` 总览行，logcat/日志文件 grep `[BOOT]`
///   即得完整启动时间线。
///
/// 步骤顺序与原 main() 完全一致，含关键时序约束：
/// 1. ZJU 安全网必须先于 configServer.setGreenixConfigPath（否则空值固化）；
/// 2. 各 HttpServer 必须先于模块 .exe 启动（端口发现文件先落盘）；
/// 3. 窗口 show() 必须最后（避免启动白屏）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:evergreen_base/app.dart';
import 'package:evergreen_base/core/agent/agent/session.dart' as agent;
import 'package:evergreen_base/core/agent/controller/controller.dart' as agent;
import 'package:evergreen_base/core/agent/event.dart' as agent;
import 'package:evergreen_base/core/agent/file_session_store.dart';
import 'package:evergreen_base/core/agent/memory/file_memory_store.dart';
import 'package:evergreen_base/core/agent/provider.dart' as agent;
import 'package:evergreen_base/core/agent/session_manager.dart';
import 'package:evergreen_base/core/agent/skill/skill.dart';
import 'package:evergreen_base/core/agent/tool.dart' as agent;
import 'package:evergreen_base/core/agent/tools/agent_http_server.dart';
import 'package:evergreen_base/core/agent/tools/data_query.dart';
import 'package:evergreen_base/core/agent/tools/file_info.dart';
import 'package:evergreen_base/core/agent/tools/grep.dart';
import 'package:evergreen_base/core/agent/tools/head_tail.dart';
import 'package:evergreen_base/core/agent/tools/plugin_bridge.dart';
import 'package:evergreen_base/core/agent/tools/python_runner_tool.dart';
import 'package:evergreen_base/core/agent/tools/read_file.dart';
import 'package:evergreen_base/core/agent/tools/read_global_memory.dart';
import 'package:evergreen_base/core/agent/tools/web_search.dart';
import 'package:evergreen_base/core/agent/tools/write_file.dart';
import 'package:evergreen_base/core/agent/tools/write_global_memory.dart';
import 'package:evergreen_base/core/config/config.dart';
import 'package:evergreen_base/core/data/cache.dart';
import 'package:evergreen_base/core/data/data_http_server.dart';
import 'package:evergreen_base/core/data/orchestrator.dart';
import 'package:evergreen_base/core/data/register_data_source.dart';
import 'package:evergreen_base/core/errors.dart';
import 'package:evergreen_base/core/log.dart';
import 'package:evergreen_base/core/module/module_http_server.dart';
import 'package:evergreen_base/core/module/module_loader.dart';
import 'package:evergreen_base/core/module/module_registry.dart';
import 'package:evergreen_base/core/result.dart';
import 'package:evergreen_base/core/services/core_http_server.dart';
import 'package:evergreen_base/core/services/ocr_pipeline.dart';
import 'package:evergreen_base/core/services/plugin_installer.dart';
import 'package:evergreen_base/core/services/update_service.dart';
import 'package:evergreen_base/core/theme/builtin_themes.dart';
import 'package:evergreen_base/core/theme/theme_descriptor.dart';
import 'package:evergreen_base/core/theme/theme_http_server.dart';
import 'package:evergreen_base/core/theme/theme_loader.dart';
import 'package:evergreen_base/core/theme/theme_store.dart';
import 'package:evergreen_base/core/utils/greenix_path.dart';
import 'package:evergreen_base/core/utils/plugin_asset_releaser.dart';
import 'package:evergreen_base/core/utils/python_env.dart';
import 'package:evergreen_base/providers.dart';
import 'package:evergreen_base/renderer/app/service/providers/renderer_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_windows/webview_windows.dart';
import 'package:window_manager/window_manager.dart';

/// 一个启动步骤。
class BootStep {
  /// 构造步骤定义。
  BootStep(this.id, this.name, this.run, {this.fatal = false});

  /// 步骤执行体；内部应自行降级并返回 [Ok]，未捕获异常由 runner 转 [Err]。
  final Future<Result<void>> Function() run;

  /// 步骤 id（如 'greenix-paths'，用于 `[BOOT] N/23 <id>` 日志定位）。
  final String id;

  /// 步骤中文名（日志展示）。
  final String name;

  /// 失败是否中止启动（当前仅 greenix-paths 为致命步骤）。
  final bool fatal;
}

/// 启动报告：跑完后的结构化结果（供 main 决定是否退出）。
class BootReport {
  /// 汇总各步骤结果。
  BootReport({
    required this.ok,
    required this.failed,
    required this.total,
    required this.elapsedMs,
    this.fatalFailed,
  });

  /// 是否全部成功。
  final bool ok;

  /// 失败（含降级）步骤 id 列表。
  final List<String> failed;

  /// 总步骤数。
  final int total;

  /// 总耗时（毫秒）。
  final int elapsedMs;

  /// 致命步骤 id（失败即中止），无则 null。
  final String? fatalFailed;
}

/// 启动执行器。
///
/// 用法（main.dart）：
/// ```dart
/// final report = await AppBootstrap(
///   projectRoot: _projectRoot,
///   pluginsDir: _pluginsDir,
///   ports: textModeServerPorts,
/// ).run();
/// if (report.fatalFailed != null) exit(1);
/// ```
class AppBootstrap {
  /// 注入项目根/插件目录/端口发现表。
  AppBootstrap({
    required this.projectRoot,
    required this.pluginsDir,
    required this.ports,
  });

  /// 项目根目录（端口发现文件、模块加载等使用）。
  final String projectRoot;

  /// 插件目录（模块/主题/数据插件统一存放处）。
  final String pluginsDir;

  /// 端口发现表（main.dart 顶层持有，供 app.dart 读取）。
  final Map<String, int> ports;

  // ═══════════ 步骤间共享状态 ═══════════

  /// SharedPreferences（设置/凭证持久化）。
  SharedPreferences? prefs;

  /// 数据谱仪器（CLI fetcher 注册目标）。
  DataOrchestrator? orchestrator;

  /// 主题存储（ChangeNotifierProvider 数据源）。
  ThemeStore? themeStore;

  /// Core 服务 HTTP 服务器。
  CoreHttpServer? coreServer;

  /// 配置层 HTTP 服务器。
  ConfigHttpServer? configServer;

  /// 数据层 HTTP 服务器。
  DataHttpServer? dataServer;

  /// 主题层 HTTP 服务器。
  ThemeHttpServer? themeServer;

  /// Agent 层 HTTP 服务器。
  AgentHttpServer? agentServer;

  /// 模块 HTTP 服务器（注册中心启动后创建）。
  ModuleHttpServer? moduleServer;

  /// 模块注册中心。
  ModuleRegistry? registry;

  /// Agent 控制器（Chat 视图通过 provider 获取）。
  agent.Controller? controller;

  /// Agent 事件流（Chat 视图订阅）。
  agent.StreamEventSink? eventSink;

  /// Agent 工具注册表（工具管理面板读写）。
  agent.Registry? toolRegistry;

  /// Agent 会话（持久化）。
  agent.Session? session;

  /// 全局记忆存储。
  FileMemoryStore? memoryStore;

  /// 会话持久化存储。
  FileSessionStore? sessionStore;

  /// Skill 索引（技能管理页面列举）。
  SkillIndex? skillIndex;

  /// 已禁用的工具名称（持久化状态）。
  Set<String> toolDisabled = {};

  /// V2 原始 manifest JSON（HTML 渲染引擎使用）。
  Map<String, Map<String, dynamic>> v2Manifests = {};

  /// 各 HttpServer 实例（SIGINT 清理用）。
  Map<String, dynamic> servers = {};

  /// Agent 数据层 Dio（工具注册用）。
  Dio? _agentDio;

  // ═══════════ 步骤定义 ═══════════

  /// 步骤定义（测试用：校验步骤契约，如 id 唯一性/致命标记/时序约束）。
  List<BootStep> get stepsForTest => _steps;

  List<BootStep> get _steps => [
        BootStep('window-init', '桌面窗口参数预设', _stepWindowInit),
        BootStep('greenix-paths', 'Greenix 路径初始化', _stepGreenixPaths,
            fatal: true),
        BootStep('android-assets', '安卓插件资产释放', _stepAndroidAssets),
        BootStep('media-kit', 'media_kit 初始化', _stepMediaKit),
        BootStep('webview2', 'WebView2 CDP 环境', _stepWebView2),
        BootStep('prefs', 'SharedPreferences 初始化', _stepPrefs),
        BootStep('settings', '设置初始化', _stepSettings),
        BootStep('data-orchestrator', '数据谱仪器', _stepDataOrchestrator),
        BootStep('themes', '主题加载', _stepThemes),
        BootStep('http-services', '核心服务构造', _stepHttpServices),
        BootStep('zju-safety', 'ZJU 凭证安全网', _stepZjuSafety),
        BootStep('agent-runtime', 'Agent 运行时构造', _stepAgentRuntime),
        BootStep('agent-tools', 'Agent 工具注册', _stepAgentTools),
        BootStep('tool-disabled', '禁用工具加载', _stepToolDisabled),
        BootStep('agent-controller', 'Agent 会话与控制', _stepAgentController),
        BootStep('servers-start', 'HttpServer 启动', _stepServersStart),
        BootStep('v2-scan', 'V2 清单扫描', _stepV2Scan),
        BootStep('data-sources', '数据插件注册', _stepDataSources),
        BootStep('modules', '模块注册中心', _stepModules),
        BootStep('module-server', 'ModuleHttpServer 启动', _stepModuleServer),
        BootStep('default-theme', '默认主题选取', _stepDefaultTheme),
        BootStep('ui-launch', 'UI 启动 (runApp)', _stepUiLaunch),
        BootStep('window-show', '窗口显示', _stepWindowShow),
      ];

  /// 顺序执行全部步骤；失败步骤记录并继续（致命步骤除外）。
  Future<BootReport> run() async {
    final steps = _steps;
    final failed = <String>[];
    String? fatalFailed;
    final swAll = Stopwatch()..start();

    for (var i = 0; i < steps.length; i++) {
      final s = steps[i];
      Log().info('[BOOT] $i/${steps.length} ${s.id} ${s.name} 开始');
      final sw = Stopwatch()..start();
      Result<void> r;
      try {
        r = await s.run();
      } catch (e, st) {
        Log().error('[BOOT] $i/${steps.length} ${s.id} ${s.name} 未捕获异常',
            error: e, stack: st);
        r = Err(AppError.unknown(e));
      }
      if (r.isOk) {
        Log().info(
            '[BOOT] ✅ $i/${steps.length} ${s.id} (${sw.elapsedMilliseconds}ms)');
      } else {
        final err = (r as Err<void>).error;
        Log().error('[BOOT] ❌ $i/${steps.length} ${s.id} ${s.name} 失败: '
            '${err.toLogLine()}');
        failed.add(s.id);
        if (s.fatal) {
          fatalFailed = s.id;
          Log().error('[BOOT] 中止：${s.id} 为致命步骤');
          break;
        }
      }
    }

    final ok = failed.isEmpty;
    Log().info('[BOOT] 完成: ${ok ? '✅ 全部成功' : '⚠ 有降级/失败'} '
        '${steps.length - failed.length}/${steps.length}'
        '${failed.isNotEmpty ? ' 失败步骤: $failed' : ''} '
        '(${swAll.elapsedMilliseconds}ms)');
    return BootReport(
      ok: ok,
      failed: failed,
      total: steps.length,
      elapsedMs: swAll.elapsedMilliseconds,
      fatalFailed: fatalFailed,
    );
  }

  Result<void> _ok() => const Ok<void>(null);

  // ═══════════ 步骤实现（行为与原 main() 逐段一致） ═══════════

  /// 桌面窗口参数预设（只设参数不 show，show 延后到 runApp 之后）。
  Future<Result<void>> _stepWindowInit() async {
    if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      return _ok();
    }
    try {
      await windowManager.ensureInitialized();
      await windowManager.setMinimumSize(const Size(900, 600));
      await windowManager.setSize(const Size(1200, 800));
      await windowManager.setTitle('Evergreen 多工具集成版');
      await windowManager.center();
    } catch (e) {
      Log().warn('[BOOT] windowManager 初始化失败（缺少 screen_retriever 等插件？）: $e');
      Log().warn('[BOOT] 窗口将以默认尺寸和位置启动。');
    }
    return _ok();
  }

  /// Greenix 路径初始化（致命：后续所有步骤依赖路径）。
  Future<Result<void>> _stepGreenixPaths() async {
    await initGreenixPaths();
    Log().info('[BOOT] 🗺️ initGreenixPaths 完成');
    Log().info('[BOOT]   greenixConfigPath=$greenixConfigPath');
    Log().info('[BOOT]   pluginsDir=$pluginsDir');
    return _ok();
  }

  /// 安卓：释放插件资产到设备可写目录。
  Future<Result<void>> _stepAndroidAssets() async {
    if (!Platform.isAndroid) return _ok();
    Log().info('[BOOT] 安卓：开始释放插件资产...');
    try {
      final released = await releasePluginsAssetsIfNeeded();
      Log().info('[BOOT] 安卓插件资产释放目录: $released');
    } catch (e, st) {
      Log().error('[BOOT] 安卓插件资产释放失败: $e', error: e, stack: st);
    }
    return _ok();
  }

  /// media_kit（安卓跳过：libmpv 初始化即原生崩溃，安卓走 video_player）。
  Future<Result<void>> _stepMediaKit() async {
    if (Platform.isAndroid) return _ok();
    try {
      MediaKit.ensureInitialized();
      Log().info('[BOOT] media_kit 初始化成功（libmpv 视频播放）');
    } catch (e) {
      Log().warn('[BOOT] ⚠ media_kit 初始化失败，视频播放不可用: $e', error: e);
    }
    return _ok();
  }

  /// WebView2 CDP 远程调试端口（爬虫网络捕获）。
  Future<Result<void>> _stepWebView2() async {
    try {
      await WebviewController.initializeEnvironment(
        additionalArguments: '--remote-debugging-port=9222',
      );
      Log().info('[BOOT] WebView2 环境已初始化（CDP port 9222）');
    } catch (e) {
      Log().warn('[BOOT] ⚠ WebView2 环境初始化失败: $e');
      Log().warn('[BOOT]    CDP 网络捕获将不可用，爬虫模块降级到 JS 方案。');
    }
    return _ok();
  }

  /// SharedPreferences（失败回退内存存储）。
  Future<Result<void>> _stepPrefs() async {
    SharedPreferences p;
    try {
      p = await SharedPreferences.getInstance();
      Log().info('[BOOT] SharedPreferences 初始化成功（持久化存储）');
    } catch (e) {
      Log().warn('[BOOT] SharedPreferences 不可用（无 Windows 平台实现？）: $e');
      Log().warn('[BOOT] 将使用内存存储回退方案（设置不会持久化）。');
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      p = await SharedPreferences.getInstance();
    }
    prefs = p;
    return _ok();
  }

  /// 设置初始化 + 启动诊断（SP 键值 dump 仅 debug 输出、密码脱敏）。
  Future<Result<void>> _stepSettings() async {
    final p = prefs!;
    await initSettings(p, pluginDirs: [pluginsDir]);
    Log().info('[BOOT] 🔧 initSettings 完成 — 已注册 key 数: ${p.getKeys().length}');
    Log().info('[BOOT]   ZJU_USERNAME 在 prefs? ${p.containsKey("ZJU_USERNAME")}');
    Log().info('[BOOT]   ZJU_PASSWORD 在 prefs? ${p.containsKey("ZJU_PASSWORD")}');
    final allKeys = p.getKeys().toList()..sort();
    Log().debug('[BOOT] 📋 SharedPreferences 全部键(${allKeys.length}): $allKeys');
    for (final k in allKeys) {
      // 安全取值：某些键存的是 List/Bool/其他类型，getString 会抛类型异常
      String? v;
      try {
        v = p.getString(k);
      } catch (_) {
        try {
          v = p.getStringList(k)?.toString();
        } catch (_) {
          v = p.get(k)?.toString();
        }
      }
      final masked = (k.contains('PASSWORD') || k.contains('SECRET') || k.contains('KEY'))
          ? (v != null && v.isNotEmpty ? '***(${v.length}字符)' : '(空)')
          : v;
      Log().debug('[BOOT]   $k = $masked');
    }
    return _ok();
  }

  /// 数据谱仪器（磁盘缓存 + orchestrator）。
  Future<Result<void>> _stepDataOrchestrator() async {
    await Cache.getInstance(); // 初始化缓存（磁盘持久化）
    final orch = DataOrchestrator();
    orch.refreshStatusFromDisk();
    orchestrator = orch;
    return _ok();
  }

  /// 主题加载（内置 + 插件主题）。
  Future<Result<void>> _stepThemes() async {
    final store = ThemeStore();
    registerBuiltinThemes(store);
    loadThemes(pluginsDir, store);
    themeStore = store;
    return _ok();
  }

  /// 核心服务构造（installer/ocr/updater + 各 HttpServer 实例）。
  Future<Result<void>> _stepHttpServices() async {
    final dio = Dio();
    final installer = PluginInstaller(pluginsDir: pluginsDir, dio: dio);
    final ocr = OcrPipeline(dio);
    final updater = UpdateService(dio);

    coreServer = CoreHttpServer(installer, ocr, updater);
    configServer = ConfigHttpServer(prefs!);
    dataServer = DataHttpServer(orchestrator!);
    themeServer = ThemeHttpServer(themeStore!);
    return _ok();
  }

  /// ZJU 凭证安全网（直写 config.json）。
  ///
  /// ⚠️ 必须在 setGreenixConfigPath（触发 syncConfigToGreenix）之前执行！
  /// 否则 syncConfigToGreenix 先用空值覆写 config.json，安全网再检测
  /// containsKey=true → 跳过不补 → 空值永久固化。
  Future<Result<void>> _stepZjuSafety() async {
    Log().info('[BOOT] 🛡️ 即将调用 ZJU 安全网(path=${greenixConfigPath.length}chars)');
    _ensureZjuCredentialsInGreenixConfig(greenixConfigPath, prefs!);
    Log().info('[BOOT] ✅ ZJU 安全网返回');
    // 设置 greenix config JSON 路径，启动后、每次写入设置项时自动同步覆写。
    configServer!.setGreenixConfigPath(greenixConfigPath);
    return _ok();
  }

  /// Agent 运行时构造（DeepSeek provider/registry/记忆/Skill 索引）。
  Future<Result<void>> _stepAgentRuntime() async {
    final p = prefs!;
    Log().info('[BOOT] 初始化 Agent 运行时...');
    final apiKey = getSetting(p, 'DEEPSEEK_API_KEY');
    if (apiKey.isEmpty) {
      Log().warn('[BOOT] ⚠ DEEPSEEK_API_KEY 未设置！AI 对话将不可用。请在设置中配置 API Key。');
    }
    final dioAgent = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 120),
    ));
    _agentDio = dioAgent;
    final provider = agent.DeepSeekProvider(dio: dioAgent, apiKey: apiKey);
    final registry = agent.Registry();
    memoryStore = FileMemoryStore(greenixMemoriesDir);
    sessionStore = FileSessionStore(greenixSessionsDir);
    skillIndex = SkillIndex();
    // 扫描内置 Skill
    final skillLoader = SkillLoader([greenixSkillsDir]);
    skillIndex!.addAll(skillLoader.loadAll());
    toolRegistry = registry;
    // provider 暂存供 controller 步骤使用
    _agentProvider = provider;
    return _ok();
  }

  agent.DeepSeekProvider? _agentProvider;

  /// Agent 工具注册（内置 + Python 多级回退 + 插件桥）。
  Future<Result<void>> _stepAgentTools() async {
    final registry = toolRegistry!;
    final aiWorkspace = greenixWorkspaceDir('ai-assistant');
    Directory(aiWorkspace).createSync(recursive: true);
    registry.register(ReadGlobalMemoryTool(memoryStore!));
    registry.register(WriteGlobalMemoryTool(memoryStore!));
    registry.register(WebSearchTool(_agentDio!));
    registry.register(ReadFileTool(workspaceDir: aiWorkspace));
    registry.register(WriteFileTool(workspaceDir: aiWorkspace));
    registry.register(GrepTool(workspaceDir: aiWorkspace));
    registry.register(ReadHeadTool(workspaceDir: aiWorkspace));
    registry.register(ReadTailTool(workspaceDir: aiWorkspace));
    registry.register(FileInfoTool(workspaceDir: aiWorkspace));
    registry.register(DataQueryTool(orchestrator: orchestrator));
    // 注册嵌入式 Python 解释器工具——多级回退发现
    // ① .greenix/python/python.exe（同学打包的嵌入式 Python，最高优先级）
    // ② scripts/python/python.exe（安装包自带）
    // ③ 用户配置路径 → 系统 PATH（python3 → python → py -3）
    final bundledCandidate = p.join(greenixPythonDir, 'python.exe');
    final resolvedPython =
        await resolvePythonExe(configuredPath: bundledCandidate);
    if (resolvedPython != null) {
      // workDir: 嵌入式 Python 用其所在目录；系统 PATH 命令用 workspace
      final isBundled =
          resolvedPython == bundledCandidate || p.isAbsolute(resolvedPython);
      // 当是完整路径时用父目录，否则（系统 PATH 命令如 python/python3）用 workspace
      final workDir =
          isBundled ? Directory(resolvedPython).parent.path : aiWorkspace;
      registry.register(PythonRunnerTool(
        pythonExePath: resolvedPython,
        pythonWorkDir: workDir,
        workspaceDir: aiWorkspace,
      ));
      Log().info('[BOOT] PythonRunnerTool 已注册 ($resolvedPython, workDir: $workDir)');
    } else {
      Log().warn('[BOOT] ⚠ Python 解释器未找到——已尝试 .greenix/python/、scripts/python/、系统 PATH。');
      Log().warn('[BOOT]    AI 将无法执行 Python 代码。安装 Python 3.8+ 或放置 python.exe 到 .greenix/python/。');
    }
    // 注册插件 Agent 工具
    PluginBridge.registerAll(registry, Directory(pluginsDir));
    Log().info('[BOOT] Agent 工具: ${registry.all().map((t) => t.name).toList()}');
    return _ok();
  }

  /// 加载用户禁用的工具（持久化）。
  Future<Result<void>> _stepToolDisabled() async {
    // tool_disabled 可能存为 List<String> 或逗号分隔 String，防御性取值
    String raw;
    try {
      raw = prefs!.getString('tool_disabled') ?? '';
    } catch (_) {
      final list = prefs!.getStringList('tool_disabled') ?? <String>[];
      raw = list.join(',');
    }
    final disabled = <String>{};
    if (raw.isNotEmpty) {
      disabled.addAll(raw.split(','));
    }
    for (final name in disabled) {
      toolRegistry!.disable(name);
    }
    toolDisabled = disabled;
    if (disabled.isNotEmpty) {
      Log().info('[BOOT] 已禁用工具: ${disabled.toList()}');
    }
    return _ok();
  }

  /// Agent 会话/事件流/Controller/HttpServer。
  Future<Result<void>> _stepAgentController() async {
    final session = agent.Session();
    final sink = agent.StreamEventSink();
    final controller = agent.Controller(
      provider: _agentProvider!,
      registry: toolRegistry!,
      sink: sink,
      session: session,
      skillIndex: skillIndex,
    );

    agentServer = AgentHttpServer(
      controller: controller,
      eventSink: sink,
      session: session,
      registry: toolRegistry!,
      portFile: p.join(projectRoot, '.agent_port'),
      memoryStore: memoryStore,
      skillIndex: skillIndex,
    );
    this.session = session;
    eventSink = sink;
    this.controller = controller;
    Log().info('[BOOT] AgentHttpServer 就绪 (DeepSeek v4-pro)');
    return _ok();
  }

  /// 启动各 HttpServer + SIGINT 清理 + 端口发现文件。
  Future<Result<void>> _stepServersStart() async {
    servers = {
      'Core': coreServer,
      'Config': configServer,
      'Data': dataServer,
      'Theme': themeServer,
      'Agent': agentServer,
    };

    // 注册进程退出时清理所有端口
    ProcessSignal.sigint.watch().listen((_) {
      Log().info('[BOOT] 收到 SIGINT，关闭所有服务...');
      for (final entry in servers.entries) {
        try {
          (entry.value as dynamic).stop();
        } catch (_) {}
      }
      exit(0);
    });

    for (final entry in servers.entries) {
      try {
        final r = (entry.value as dynamic).start();
        final pVal = (r is Future) ? await r : (entry.value as dynamic).port;
        final port = pVal is int ? pVal : 0;
        ports[entry.key] = port;
        // 统一写入端口发现文件到 projectRoot
        final portFileName = '.${entry.key.toLowerCase()}_port';
        File(p.join(projectRoot, portFileName)).writeAsStringSync('$port');
        Log().info('[BOOT] ${entry.key}HttpServer → port $port → $portFileName');
      } catch (e) {
        Log().error('[BOOT] 启动 ${entry.key}HttpServer 失败: $e', error: e);
        ports[entry.key] = 0;
      }
    }
    return _ok();
  }

  /// 扫描 V2 原始清单（独立于 ModuleLoader，用于 HTML 渲染）。
  Future<Result<void>> _stepV2Scan() async {
    final manifests = <String, Map<String, dynamic>>{};
    _scanV2Manifests(pluginsDir, manifests);
    v2Manifests = manifests;
    Log().info('[BOOT] V2 清单: ${manifests.keys.toList()}');
    return _ok();
  }

  /// 扫描数据插件 → 注册 DataType（CLI fetcher，模块加载前完成）。
  Future<Result<void>> _stepDataSources() async {
    Log().info('[BOOT] 开始扫描数据插件: pluginsDir=$pluginsDir');
    _scanAndRegisterDataSources(pluginsDir, orchestrator!);
    Log().info('[BOOT] 数据插件扫描完成');
    return _ok();
  }

  /// 模块注册中心（HttpServer 就绪后再启动 .exe，确保端口文件已存在）。
  Future<Result<void>> _stepModules() async {
    final registry = ModuleRegistry();
    final loaders = await scanAndLoadModules(pluginsDir, registry,
        projectRoot: projectRoot);
    for (final loader in loaders) {
      if (loader.isRunning && loader.port != null) {
        ports[loader.manifest.id] = loader.port!;
        Log().info('[BOOT] 模块 ${loader.manifest.id} → http://127.0.0.1:${loader.port}');
      }
    }
    registry.seal();
    this.registry = registry;
    Log().info('[BOOT] 模块注册完毕: ${registry.modules.map((m) => m.id).toList()}');
    return _ok();
  }

  /// ModuleHttpServer（registry 创建后启动）。
  Future<Result<void>> _stepModuleServer() async {
    final server = ModuleHttpServer(registry!, port: 0);
    try {
      final mp = await server.start();
      ports['Module'] = mp;
    } catch (e) {
      Log().error('[BOOT] 启动 ModuleHttpServer 失败: $e', error: e);
      ports['Module'] = 0;
    }
    moduleServer = server;
    return _ok();
  }

  /// 选取默认主题（上次选择 > default > dark > 首个已注册）。
  Future<Result<void>> _stepDefaultTheme() async {
    final store = themeStore!;
    ThemeDescriptor? defaultTheme;
    final savedId = prefs!.getString('active_theme_id');
    if (savedId != null && savedId.isNotEmpty) {
      defaultTheme = store.findById(savedId);
    }
    defaultTheme ??= store.findById('default') ??
        store.findById('dark') ??
        (store.all.isNotEmpty ? store.all.first : null);
    if (defaultTheme != null) {
      store.activeTheme = defaultTheme;
    }
    return _ok();
  }

  /// UI 启动：runApp + ProviderScope 注入全部构建产物。
  Future<Result<void>> _stepUiLaunch() async {
    runApp(
      ProviderScope(
        overrides: [
          // SharedPreferences（agent 运行时、设置等依赖）
          sharedPreferencesProvider.overrideWith((ref) => prefs!),

          // 模块注册中心
          moduleRegistryProvider.overrideWith((ref) => registry!),

          // 数据谱仪器
          dataOrchestratorProvider.overrideWith((ref) => orchestrator!),

          // 配置层 HTTP 服务器（供热注册配置项）
          configHttpServerProvider.overrideWith((ref) => configServer!),

          // 插件目录（供渲染层构造模块工作目录）
          pluginsDirProvider.overrideWith((ref) => pluginsDir),

          // 模块端口映射（供渲染层通过 HTTP 与模块 .exe 通信）
          modulePortsProvider.overrideWith((ref) => ports),

          // Agent Controller——Chat 视图通过此 provider 发送消息
          agentControllerProvider.overrideWith((ref) => controller!),

          // Agent 工具注册表——供工具管理面板读取/控制
          toolRegistryProvider.overrideWith((ref) => toolRegistry!),

          // 已禁用的工具名称——持久化状态
          toolDisabledProvider.overrideWith((ref) => toolDisabled),

          // Agent 事件流——Chat 视图订阅此流以接收响应
          agentEventStreamProvider.overrideWith((ref) => eventSink!.stream),

          // 记忆 & Skill 目录路径
          memoriesDirProvider.overrideWith((ref) => greenixMemoriesDir),
          skillsDirProvider.overrideWith((ref) => greenixSkillsDir),

          // 全局记忆存储——供全局记忆页面读写
          memoryStoreProvider.overrideWith((ref) => memoryStore!),

          // 会话持久化存储——供会话列表/切换/创建使用
          sessionStoreProvider.overrideWith((ref) => sessionStore!),

          // Skill 索引——供技能管理页面列举
          skillIndexProvider.overrideWith((ref) => skillIndex!),

          // 主题存储——ChangeNotifierProvider，HTTP 切换主题后自动通知 UI 刷新
          themeStoreProvider.overrideWith((ref) => themeStore!),

          // V2 原始 manifest JSON（HTML 渲染引擎使用）
          v2ManifestProvider.overrideWith((ref) => v2Manifests),
        ],
        child: const EvergreenApp(),
      ),
    );
    return _ok();
  }

  /// 窗口显示（Flutter UI 就绪后，避免启动白屏）。
  Future<Result<void>> _stepWindowShow() async {
    if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      return _ok();
    }
    try {
      await windowManager.show();
    } catch (e) {
      Log().warn('[BOOT] windowManager.show() 失败: $e', error: e);
    }
    return _ok();
  }

  // ═══════════ 私有工具函数（自 main.dart 迁入） ═══════════

  /// 扫描 plugins/ 下所有 module/manifest.json，提取 schemaVersion="2.0" 的原始 JSON。
  /// 结果存入 [out] map，key 为模块 id。同时扫描 data 插件 manifest.json 注册
  /// DataType（CLI fetcher），在模块加载前调用，避免组件渲染时数据源未注册的时序问题。
  ///
  /// 注册逻辑委托给 [registerDataSourcesFromManifest]（与运行期热注册同一份契约）。
  void _scanAndRegisterDataSources(String pluginsDir, DataOrchestrator orch) {
    final dir = Directory(pluginsDir);
    Log().info(
        '[BOOT] _scanAndRegisterDataSources: pluginsDir=$pluginsDir, exists=${dir.existsSync()}');
    if (!dir.existsSync()) {
      Log().warn('[BOOT] ⚠ 插件目录不存在，跳过数据源扫描');
      return;
    }

    final entries = dir.listSync();
    Log().info('[BOOT] 插件目录子项数: ${entries.length}');
    for (final entity in entries) {
      if (entity is! Directory) continue;
      Log().info('[BOOT] 检查插件子目录: ${p.basename(entity.path)}');
      final names = registerDataSourcesFromManifest(
        orch: orch,
        pluginDir: entity.path,
        projectRoot: projectRoot,
      );
      if (names.isNotEmpty) {
        Log().info(
            '[BOOT] DataSource 扫描完成: plugin=${p.basename(entity.path)}, count=${names.length}, types=$names');
      }
    }
  }

  /// ZJU 凭证安全网——直接操作 [greenixConfigPath] JSON 文件，确保
  /// `ZJU_USERNAME` 和 `ZJU_PASSWORD` 两个 key 一定存在。
  ///
  /// 绕开 ConfigHttpServer._dynamicSettings / syncConfigToGreenix 链路，
  /// 直接读写 config.json 实现兜底，避免 scraper `_get_config()` 三级降级全失败。
  void _ensureZjuCredentialsInGreenixConfig(
      String configPath, SharedPreferences prefs) {
    Log().info('[ZJU-SAFETY] ═══════ 安全网启动 ═══════ '
        'configPath=$configPath (len=${configPath.length})');

    const requiredKeys = ['ZJU_USERNAME', 'ZJU_PASSWORD'];

    // 防护：空路径
    if (configPath.isEmpty) {
      Log().error('[ZJU-SAFETY] ❌ FATAL: configPath 为空！安全网中止。');
      return;
    }

    try {
      final file = File(configPath);

      // 步骤 1：确认文件存在
      if (!file.existsSync()) {
        Log().warn('[ZJU-SAFETY] ⚠ config.json 不存在！创建空文件...');
        file.parent.createSync(recursive: true);
        file.writeAsStringSync('{}');
      }

      // 步骤 2：读取现有内容
      Map<String, dynamic> config;
      try {
        final raw = file.readAsStringSync();
        Log().info('[ZJU-SAFETY] 读取 ${raw.length} 字节');
        config = jsonDecode(raw) as Map<String, dynamic>;
      } catch (e) {
        Log().warn('[ZJU-SAFETY] ⚠ JSON 解析失败: $e，重置为空字典');
        config = {};
      }

      Log().info(
          '[ZJU-SAFETY] 读取前 keys(${config.length}): ${config.keys.toList()}');

      // 步骤 3：检查并补充缺失或为空的 key。
      // ⚠️ 必须先于 syncConfigToGreenix() 执行，否则后者会覆写导致 containsKey=true 但值为空。
      int added = 0;
      for (final key in requiredKeys) {
        final existing = config[key];
        final isEmpty = existing == null ||
            (existing is String && existing.isEmpty) ||
            (existing is List && existing.isEmpty);
        if (isEmpty) {
          // 尝试从 SharedPreferences 取值，否则空字符串
          final val = prefs.getString(key) ?? '';
          config[key] = val;
          added++;
          Log().info(
              '[ZJU-SAFETY] ✅ 补充 key: $key="${val.isNotEmpty ? val : '(空)'}"');
        } else {
          Log().info(
              '[ZJU-SAFETY] ✓ 已有非空值: $key len=${existing.toString().length}');
        }
      }

      // 步骤 4：写回文件
      if (added > 0) {
        file.writeAsStringSync(jsonEncode(config));
        Log().info('[ZJU-SAFETY] 💾 写入完成: $added 个 key 已补充');
      } else {
        Log().info('[ZJU-SAFETY] ✓ 无需补充，所有 key 已就绪');
      }

      // 步骤 5：读回验证
      final verifyRaw = file.readAsStringSync();
      final verifyConfig = jsonDecode(verifyRaw) as Map<String, dynamic>;
      final hasAll = requiredKeys.every((k) => verifyConfig.containsKey(k));
      Log().info(
          '[ZJU-SAFETY] 🧪 验证: ${hasAll ? "✅ 全部到位" : "❌ 仍然缺失！"}');
      Log().info(
          '[ZJU-SAFETY] 验证后 keys(${verifyConfig.length}): ${verifyConfig.keys.toList()}');
    } catch (e, st) {
      Log().error('[ZJU-SAFETY] ❌ 安全网异常: $e', error: e, stack: st);
    }

    Log().info('[ZJU-SAFETY] ═══════ 安全网完成 ═══════');
  }

  void _scanV2Manifests(String pluginsDir, Map<String, Map<String, dynamic>> out) {
    final dir = Directory(pluginsDir);
    if (!dir.existsSync()) return;
    for (final entity in dir.listSync()) {
      if (entity is! Directory) continue;
      final manifestFile = File(p.join(entity.path, 'module', 'manifest.json'));
      if (!manifestFile.existsSync()) continue;
      try {
        final map = jsonDecode(manifestFile.readAsStringSync())
            as Map<String, dynamic>;
        if (map['type'] != 'module') continue;
        if (map['schemaVersion'] == '2.0') {
          out[map['id'] as String] = map;
        }
      } catch (e) {
        Log().warn('[BOOT] V2 清单解析失败 ${manifestFile.path}: $e');
      }
    }
  }
}
