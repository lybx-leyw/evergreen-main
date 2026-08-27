/// AgentAssembly 工厂 —— 按 JSON config 为每个 `ai-assistant` 组件组装隔离 Agent。
///
/// 对应 PLAN_NOW 第十节。与全局 [agentRuntimeProvider] 正交：
/// - 无 `ai-assistant` 配置的模块继续使用全局单例 AgentRuntime
/// - 有 `ai-assistant` 配置的模块通过本工厂创建独立且隔离的 Controller
///
/// # 组件隔离策略
///
/// | 组件 | 共享/隔离 | 原因 |
/// |------|---------|------|
/// | Provider (LLM API) | **共享** | 同一 API Key，复用连接 |
/// | Registry (工具) | **隔离** | 每模块 tool whitelist 不同 |
/// | Session | **隔离** | 不同模块对话历史独立 |
/// | MemoryFacade | **隔离** | 记忆命名空间 `plugin:<name>/` |
/// | SkillIndex | **隔离** | 每模块激活的 skill 不同 |
/// | Controller | **隔离** | 各自的状态机 |
/// | AgentOptions | **隔离** | temperature / contextWindow 等独立 |
/// | Gate | **隔离** | 权限规则不同 |
///
/// # 公开类
///
/// | 类 | 说明 |
/// |---|------|
/// | [AgentAssembly] | 组装结果，提供 Controller + Session + EventSink |
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:evergreen_base/core/agent/agent.dart' as agent;
import 'package:evergreen_base/core/agent/memory/facade.dart';
import 'package:evergreen_base/core/agent/memory/router.dart';
import 'package:evergreen_base/core/agent/memory/in_memory_store.dart';
import 'package:evergreen_base/core/agent/memory/file_memory_store.dart';
import 'package:evergreen_base/core/agent/memory/memory_agent.dart';
import 'package:evergreen_base/core/agent/provider.dart';
import 'package:evergreen_base/core/agent/tool.dart';
import 'package:evergreen_base/core/agent/skill/skill.dart';
import 'package:evergreen_base/core/agent/tools/data_query.dart';
import 'package:evergreen_base/core/agent/tools/agent_process_tools.dart';
import 'package:evergreen_base/core/agent/tools/plugin_bridge.dart';
import 'package:evergreen_base/core/agent/tools/python_runner_tool.dart';
import 'package:evergreen_base/core/agent/tools/read_file.dart';
import 'package:evergreen_base/core/agent/tools/read_global_memory.dart';
import 'package:evergreen_base/core/agent/tools/show_file4u.dart';
import 'package:evergreen_base/core/agent/tools/run_skill.dart';
import 'package:evergreen_base/core/agent/tools/user_info.dart';
import 'package:evergreen_base/core/agent/tools/web_search.dart';
import 'package:evergreen_base/core/agent/tools/write_file.dart';
import 'package:evergreen_base/core/agent/tools/write_global_memory.dart';
import 'package:evergreen_base/core/agent/tools/head_tail.dart';
import 'package:evergreen_base/core/agent/tools/file_info.dart';
import 'package:evergreen_base/core/data/orchestrator.dart';
import 'package:evergreen_base/core/utils/greenix_path.dart';
import 'package:evergreen_base/core/utils/python_env.dart';

/// AgentAssembly —— 为特定模块创建的隔离 Agent 实例。
///
/// 持有 [controller]、[eventSink]、[session]、[memory]、[registry]、
/// [options] 六大组件的隔离副本。
class AgentAssembly {
  /// 模块唯一标识（如 `"vocab-tutor"`）。
  final String moduleId;

  /// 隔离的会话驱动器。
  final agent.Controller controller;

  /// 隔离的事件流（渲染层监听用）。
  final agent.StreamEventSink eventSink;

  /// 隔离的对话会话。
  final agent.Session session;

  /// 隔离的记忆门面（plugin: 命名空间前缀自动注入）。
  final MemoryFacade? memory;

  /// 隔离的工具注册表（按 tools.mode 过滤）。
  final Registry registry;

  /// 从 config 解析的 Agent 配置。
  final agent.AgentOptions options;

  /// 隔离的 Skill 索引（按 skills.mode 过滤）。
  final SkillIndex skillIndex;

  AgentAssembly._({
    required this.moduleId,
    required this.controller,
    required this.eventSink,
    required this.session,
    this.memory,
    required this.registry,
    required this.options,
    required this.skillIndex,
  });

  // ═══════ 预设定义 ═══════

  /// 预设配置表 —— 参见 PLAN_NOW 第六节。
  ///
  /// 预设提供默认值，用户在 `config` 中的显式字段会覆盖预设值。
  static const Map<String, Map<String, dynamic>> _presets = {
    // 预设 1：轻量问答助手
    'qa-basic': {
      'global_memory': false,
      'memory_isolation': 'none',
      'skills': {'mode': 'none'},
      'tools': {'mode': 'none'},
      'multi_session': false,
      'workspace': {'enabled': false},
      'temperature': 0.0,
    },

    // 预设 2：完整研究助手
    'research-full': {
      'global_memory': true,
      'memory_isolation': 'plugin',
      'skills': {'mode': 'all'},
      'tools': {'mode': 'all'},
      'multi_session': true,
      'workspace': {'enabled': true},
      'temperature': 0.3,
    },

    // 预设 3：代码助手
    'code-assistant': {
      'global_memory': true,
      'memory_isolation': 'plugin',
      'skills': {'mode': 'all'},
      'tools': {'mode': 'all'},
      'multi_session': true,
      'workspace': {'enabled': true},
      'context_window': 64000,
    },
  };

  /// 解析预设 + 用户覆盖 → 最终 config。
  ///
  /// 若 config.preset 存在：以预设为基，用户显式字段覆盖同名字段。
  /// 若不存在：直接返回原始 config。
  static Map<String, dynamic> _resolvePreset(Map<String, dynamic> config) {
    final presetName = config['preset'] as String?;
    if (presetName == null) return config;

    final preset = _presets[presetName];
    if (preset == null) {
      debugPrint('[AgentAssembly] ⚠️ 未知预设: "$presetName"，忽略');
      return config;
    }

    debugPrint('[AgentAssembly] 应用预设: "$presetName"');
    // 预设为基础，用户显式字段覆盖（深合并仅合并 tools/skills 对象）
    final merged = Map<String, dynamic>.from(preset);
    for (final entry in config.entries) {
      if (entry.key == 'preset') continue; // 不写入 preset 本身

      // 对 tools / skills 做浅合并（用户指定 allowed 时保留 mode）
      if (entry.key == 'tools' || entry.key == 'skills') {
        final base = merged[entry.key];
        final override = entry.value;
        if (base is Map && override is Map) {
          // Map 覆盖 Map：浅合并，保留 base.mode 与 override.allowed
          merged[entry.key] = {...base, ...override};
        } else if (base is Map && override is List) {
          // 简写 List → 视为 allowed；保留 base.mode（若为 specific/all/none）
          merged[entry.key] = {...base, 'allowed': override};
        } else if (override != null) {
          // 其余类型（含 List → specific）走规整器
          merged[entry.key] = _normalizeToolsConfig(override);
        } else {
          merged[entry.key] = override;
        }
      } else {
        merged[entry.key] = entry.value;
      }
    }

    return merged;
  }

  // ═══════ 标准工具集 ═══════

  /// 构建标准工具集——与全局 [agentRuntimeProvider] 注册的工具**完全一致**。
  ///
  /// 供渲染层（如 [ChatControllerView] 的嵌入模式）创建隔离 [AgentAssembly] 时
  /// 作为 `seedTools` 传入。隔离 Agent 再按 preset 的 `tools` 策略（all/specific/none）
  /// 对这份候选集做白名单过滤，因此这里只负责"提供完整候选"。
  ///
  /// 此方法是标准工具集的唯一权威来源；[agentRuntimeProvider] 亦应保持一致。
  /// 新增全局工具时，请同步此处与 `agent_runtime.dart` 的注册逻辑。
  static List<Tool> buildStandardTools({
    required FileMemoryStore globalStore,
    required Provider provider,
    required SkillIndex skillIndex,
    DataOrchestrator? orchestrator,
  }) {
    final loader = SkillLoader(
      [greenixSkillsDir, resolvePluginsRoot()],
      disabledSkillIds:
          SkillLoader.disabledIdsFromPluginStates(resolvePluginsRoot()),
      pluginsRootForDisabled: resolvePluginsRoot(),
    );
    final registry = Registry();
    for (final t in [
      GetUserInfoTool(),
      ReadGlobalMemoryTool(globalStore),
      WriteGlobalMemoryTool(globalStore),
      ReadFileTool(workspaceDir: greenixWorkspaceDir('ai-assistant')),
      WriteFileTool(workspaceDir: greenixWorkspaceDir('ai-assistant')),
      ReadHeadTool(workspaceDir: greenixWorkspaceDir('ai-assistant')),
      ReadTailTool(workspaceDir: greenixWorkspaceDir('ai-assistant')),
      FileInfoTool(workspaceDir: greenixWorkspaceDir('ai-assistant')),
      RunSkillTool(loader, skillIndex, provider, registry),
      ListSkillsTool(loader, skillIndex),
      WebSearchTool(Dio()),
      WebFetchTool(Dio()),
      // Task 二（R2-5）：搜索统一入口——web_search 经 mode 调用 arxiv/github/
      // crossref（四来源召回）；三个专业检索工具不再独立注册（与 app_bootstrap /
      // agent_runtime / skill-creator 对齐）。
      DataQueryTool(orchestrator: orchestrator),
      // 后台常驻进程管理工具（Task 三决策 3.2）——与 app_bootstrap /
      // agent_runtime 同步注册；共享全局单例 agentProcessRegistry。
      ListProcessesTool(),
      KillProcessTool(),
      // 工作区文件展示工具（Task 七决策 9.2）——与 app_bootstrap /
      // agent_runtime 同步注册；readOnly 纯展示，不列入 essentialToolNames。
      ShowFile4uTool(workspaceDir: greenixWorkspaceDir('ai-assistant')),
    ]) {
      if (!registry.has(t.name)) registry.register(t);
    }

    // 注册 Python Runner — 统一解析（PythonInterpreter 同步探测嵌入式 Python，
    // 与 resolvePythonExe 的 greenix 目录优先级一致；安卓恒有进程内 Chaquopy
    // 解释器 → isSupported=true，哨兵占位 + 执行时内部 sharedPluginRunner）。
    if (PythonRunnerTool.isSupported) {
      if (!registry.has('python_runner')) {
        if (Platform.isAndroid) {
          registry.register(PythonRunnerTool(
            pythonExePath: kChaquopySentinel,
            pythonWorkDir: greenixWorkspaceDir('ai-assistant'),
            workspaceDir: greenixWorkspaceDir('ai-assistant'),
          ));
        } else {
          final bundledPython = PythonInterpreter.bundledPathSync()!;
          registry.register(PythonRunnerTool(
            pythonExePath: bundledPython,
            pythonWorkDir: Directory(bundledPython).parent.path,
            workspaceDir: greenixWorkspaceDir('ai-assistant'),
          ));
        }
      }
    }

    // 插件嫁接桥 —— 自动扫描 plugins/<name>/.exe 并注册
    final pluginsDirObj = Directory(resolvePluginsRoot());
    if (!pluginsDirObj.existsSync()) pluginsDirObj.createSync(recursive: true);
    PluginBridge.registerAll(registry, pluginsDirObj);

    return registry.all();
  }

  // ═══════ 工厂 ═══════

  /// 从模块 ai-assistant [config] 组装隔离的 Agent 实例。
  ///
  /// 若 config 含 `"preset"` 字段，则先应用预设默认值，再用显式字段覆盖。
  ///
  /// [moduleId] — 模块唯一标识（如 `"vocab-tutor"`），用于记忆命名空间。
  /// [config] — `slots.*.config` 中的 ai-assistant 参数（PLAN_NOW 第五节）。
  /// [sharedProvider] — 共享的 LLM Provider（同一 API Key，全局单例）。
  /// [globalSkillIndex] — 全局 Skill 索引（从中按 skills.mode 筛选）。
  /// [globalMemoryStore] — 全局记忆存储（MemoryAgent 写入位置）。
  /// [seedTools] — 可选的种子工具列表（从全局 Registry 复制）。
  factory AgentAssembly.fromConfig({
    required String moduleId,
    required Map<String, dynamic> config,
    required agent.Provider sharedProvider,
    required SkillIndex globalSkillIndex,
    required FileMemoryStore globalMemoryStore,
    List<Tool>? seedTools,
    /// 可选工具权限门控（Phase 1：harness 接线）。
    agent.Gate? gate,
    /// 可选工具钩子（Phase 1：harness 接线）。
    agent.ToolHooks? hooks,
  }) {
    // 解析预设（如果指定了）
    final resolvedConfig = _resolvePreset(config);

    debugPrint('[AgentAssembly] 🏭 创建模块 "$moduleId"');
    debugPrint('[AgentAssembly] config keys: ${resolvedConfig.keys.join(", ")}');

    // ═══ 1. AgentOptions ═══
    final options = agent.AgentOptions(
      maxSteps: resolvedConfig['max_steps'] as int? ?? 50,
      temperature: (resolvedConfig['temperature'] as num?)?.toDouble() ?? 0.0,
      contextWindow: resolvedConfig['context_window'] as int? ?? 0,
    );
    debugPrint('[AgentAssembly] options: maxSteps=${options.maxSteps}'
        ' temp=${options.temperature} ctxWin=${options.contextWindow}');

    // ═══ 2. Registry（工具注册 + 白名单过滤） ═══
    final registry = Registry();
    if (seedTools != null) {
      for (final t in seedTools) {
        if (!registry.has(t.name)) {
          registry.register(t);
        }
      }
    }
    debugPrint('[AgentAssembly] seeded ${registry.all().length} tools');

    // 工具白名单（兼容 List/Map/null 三种形态，详见 _normalizeToolsConfig）
    final toolsConfig = _normalizeToolsConfig(resolvedConfig['tools']);
    _applyToolPolicy(registry, toolsConfig);
    debugPrint('[AgentAssembly] after policy: ${registry.enabled().length} enabled');

    // ═══ 3. Session（隔离会话） ═══
    final session = agent.Session();
    debugPrint('[AgentAssembly] session: ${session.id}');

    // ═══ 4. MemoryFacade（隔离记忆命名空间 plugin:<moduleId>/） ═══
    // conversation scope → InMemoryStore（会话级，不持久）
    // feature scope → InMemoryStore（模块隔离，TODO: 持久化为 FileMemoryStore）
    // global scope → 共享 globalMemoryStore
    final featureStore = InMemoryStore();
    final memoryRouter = MemoryRouter(
      global: globalMemoryStore,
      feature: featureStore,
    );
    final memory = MemoryFacade(memoryRouter);

    // ═══ 5. SkillIndex（按 skills config 筛选） ═══
    final skillIndex = _buildSkillIndex(
        globalSkillIndex, resolvedConfig['skills']);
    final skillsMode = resolvedConfig['skills'] is Map
        ? (resolvedConfig['skills']['mode'] ?? 'none')
        : 'none';
    debugPrint('[AgentAssembly] skillIndex: ${skillIndex.all().length} skills'
        ' (mode=$skillsMode)');

    // ═══ 6. EventSink ═══
    final eventSink = agent.StreamEventSink();

    // ═══ 7. MemoryAgent（仅 global_memory: true 时启用） ═══
    MemoryAgent? memoryAgent;
    if (resolvedConfig['global_memory'] == true) {
      try {
        memoryAgent = MemoryAgent(sharedProvider, greenixMemoriesDir);
        debugPrint('[AgentAssembly] MemoryAgent enabled');
      } catch (e) {
        debugPrint('[AgentAssembly] MemoryAgent init failed: $e');
      }
    }

    // ═══ 8. Controller ═══
    final controller = agent.Controller(
      provider: sharedProvider,
      registry: registry,
      sink: eventSink,
      session: session,
      memory: memory,
      memoryAgent: memoryAgent,
      skillIndexText: skillIndex.indexText(),
      skillIndex: skillIndex,
      moduleId: moduleId,
      gate: gate,
      hooks: hooks,
    );

    // 设置 system_prompt
    final prompt = resolvedConfig['system_prompt'] as String?;
    if (prompt != null && prompt.isNotEmpty) {
      controller.setSystemPrompt(prompt);
      debugPrint('[AgentAssembly] custom system_prompt set:'
          ' ${prompt.substring(0, prompt.length.clamp(0, 60))}...');
    }

    // ═══ 9. 激活 ModuleDescriptor.activateSkills ═══
    // 调用方在构造后根据 ModuleDescriptor.activateSkills 手动调用
    // controller.activateSkill(name)。

    debugPrint('[AgentAssembly] ✅ 模块 "$moduleId" 组装完成');

    return AgentAssembly._(
      moduleId: moduleId,
      controller: controller,
      eventSink: eventSink,
      session: session,
      memory: memory,
      registry: registry,
      options: options,
      skillIndex: skillIndex,
    );
  }

  // ═══════ 工具白名单 ═══════

  /// 将 `config['tools']` 规整为统一 Map<String, dynamic> 形态。
  ///
  /// 接受（向后兼容）：
  /// - `null` / 缺省 → `{'mode': 'all'}`（不限制，全部启用）
  /// - `['web_search', 'run_python']`（List 简写）→ `{'mode': 'specific', 'allowed': [...]}`
  /// - `{'mode': 'all'|'specific'|'none', 'allowed': [...]}`（Map 完整形式）→ 原样
  /// - 其它类型 → 兜底 `{'mode': 'all'}` 并 debugPrint 提示
  ///
  /// 以前直接 `as Map<String, dynamic>?` 会让 List 简写抛出
  /// `type 'List<dynamic>' is not a subtype of type 'Map<String, dynamic>?'`，
  /// 见 P0 修复（2026-07-11）。
  static Map<String, dynamic> _normalizeToolsConfig(dynamic raw) {
    if (raw == null) {
      return {'mode': 'all'};
    }
    if (raw is List) {
      return {
        'mode': 'specific',
        'allowed': raw.map((e) => e.toString()).toList(),
      };
    }
    if (raw is Map) {
      return raw.map((k, v) => MapEntry(k.toString(), v));
    }
    debugPrint('[AgentAssembly] ⚠️ tools 字段类型未知: ${raw.runtimeType}，按 all 处理');
    return {'mode': 'all'};
  }

  /// 根据 `tools` config 应用白名单策略。
  ///
  /// | mode | 行为 |
  /// |------|------|
  /// | `all` | 全部启用（默认） |
  /// | `specific` | 先全部禁用 → 仅启用 allowed 列表中的工具 |
  /// | `none` | 全部禁用（纯对话，无工具） |
  static void _applyToolPolicy(Registry registry, Map<String, dynamic>? toolsConfig) {
    final mode = toolsConfig?['mode'] as String? ?? 'all';

    switch (mode) {
      case 'all':
        // 全部启用 —— 不做任何改变
        debugPrint('[AgentAssembly] tool policy: all (全部启用)');
        break;

      case 'specific':
        // 先全部禁用，再按 allowed 列表启用
        final allowed = (toolsConfig?['allowed'] as List?)
            ?.map((t) => t.toString())
            .toSet();
        debugPrint('[AgentAssembly] tool policy: specific'
            ' allowed=${allowed?.join(", ")}');

        for (final t in registry.all()) {
          registry.disable(t.name);
        }
        if (allowed != null) {
          for (final name in allowed) {
            if (registry.has(name)) {
              registry.enable(name);
            } else {
              debugPrint('[AgentAssembly] ⚠️ tool "$name" 未注册，跳过白名单');
            }
          }
        }
        break;

      case 'none':
        // 全部禁用 —— 纯对话模式
        debugPrint('[AgentAssembly] tool policy: none (纯对话)');
        for (final t in registry.all()) {
          registry.disable(t.name);
        }
        break;

      default:
        debugPrint('[AgentAssembly] ⚠️ 未知 tool mode: "$mode"，回退到 none');
        for (final t in registry.all()) {
          registry.disable(t.name);
        }
    }
  }

  // ═══════ Skill 筛选 ═══════

  /// 根据 `skills` config 从全局 SkillIndex 筛选。
  ///
  /// | mode | 行为 |
  /// |------|------|
  /// | `all` | 全部已注册 skill 可用 |
  /// | `specific` | 仅 allowed 列表中的 skill 可用 |
  /// | `none` | 不注入任何 skill |
  static SkillIndex _buildSkillIndex(SkillIndex global, dynamic skillsConfig) {
    final index = SkillIndex();
    final cfg = skillsConfig as Map<String, dynamic>?;
    final mode = cfg?['mode'] as String? ?? 'none';

    switch (mode) {
      case 'all':
        index.addAll(global.all());
        break;

      case 'specific':
        final allowed = (cfg?['allowed'] as List?)
            ?.map((s) => s.toString())
            .toSet();
        if (allowed != null) {
          for (final skill in global.all()) {
            if (allowed.contains(skill.name)) {
              index.add(skill);
            }
          }
        }
        break;

      case 'none':
        // 不注入任何 skill
        break;

      default:
        debugPrint('[AgentAssembly] ⚠️ 未知 skill mode: "$mode"，回退到 none');
    }

    return index;
  }

  // ═══════ 生命周期 ═══════

  /// 释放资源（取消运行中的 Agent、关闭事件流）。
  void dispose() {
    debugPrint('[AgentAssembly] 释放模块 "$moduleId"');
    controller.dispose();
  }
}
