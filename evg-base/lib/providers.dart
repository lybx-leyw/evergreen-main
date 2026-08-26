/// 应用级 Riverpod 提供者——模块注册中心 + SharedPreferences + 插件目录 + 主题 + Agent 运行时 + 记忆 + Skill。
///
/// 渲染层通过本文件获取全局实例，避免循环依赖。
library;

import 'dart:async';

import 'package:evergreen_base/core/agent/controller/controller.dart' as agent;
import 'package:evergreen_base/core/agent/controller/controller.dart' show ControllerState;
import 'package:evergreen_base/core/agent/event.dart' as agent;
import 'package:evergreen_base/core/agent/memory/file_memory_store.dart';
import 'package:evergreen_base/core/agent/provider.dart' as agent;
import 'package:evergreen_base/core/agent/skill/skill.dart';
import 'package:evergreen_base/core/agent/tool.dart' show Registry;
import 'package:evergreen_base/core/config/config_http_server.dart' show ConfigHttpServer;
import 'package:evergreen_base/core/data/orchestrator.dart' show DataOrchestrator;
import 'package:evergreen_base/core/module/module_registry.dart';
import 'package:evergreen_base/core/theme/theme_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 全局模块注册中心——在 main() 中创建、填充、密封后通过 ProviderScope.overrides 注入。
///
/// A-P3 C4：改为 [StateProvider]，使插件设计器在 [ModuleRegistry.reloadModule]
/// 后可通过 `ref.read(moduleRegistryProvider.notifier).state = registry`
/// 触发监听方（侧边栏 [app_shell]、路由表 [app.dart]）实时刷新，
/// 实现"安装/热重载后无需重启即生效"。
final moduleRegistryProvider = StateProvider<ModuleRegistry>((ref) {
  throw UnimplementedError(
    'moduleRegistryProvider 未注入——请在 main() 的 ProviderScope.overrides 中提供已密封的 ModuleRegistry。',
  );
});

/// 全局 SharedPreferences——在 main() 中通过 ProviderScope.overrides 注入。
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'sharedPreferencesProvider 未注入——请在 main() 的 ProviderScope.overrides 中提供 SharedPreferences 实例。',
  );
});

/// 全局插件目录路径——在 main() 中通过 ProviderScope.overrides 注入。
final pluginsDirProvider = Provider<String>((ref) {
  throw UnimplementedError(
    'pluginsDirProvider 未注入——请在 main() 的 ProviderScope.overrides 中提供插件目录路径。',
  );
});

/// 反馈浮珠（🐛 FeedbackFab）显示开关。
///
/// 单一真相源为 StateProvider，SharedPreferences 仅作持久化（键
/// `SHOW_FEEDBACK_FAB`，bool 类型，默认 true）。app_shell 通过本 provider
/// 实时响应设置面板变更，无需重启。SettingsView 改写时同步持久化到 SP。
final showFeedbackFabProvider = StateProvider<bool>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return prefs.getBool('SHOW_FEEDBACK_FAB') ?? true;
});

/// 模块 ID → HTTP 端口映射。
///
/// 由 main() 在启动模块 .exe 后填充，供渲染层通过 HTTP 与模块后端通信。
/// key 为模块 id（如 "settings"、"pomodoro"），value 为监听端口。
final modulePortsProvider = Provider<Map<String, int>>((ref) {
  throw UnimplementedError(
    'modulePortsProvider 未注入——请在 main() 的 ProviderScope.overrides 中提供模块端口映射。',
  );
});

/// .greenix/memories/ 目录路径。
final memoriesDirProvider = Provider<String>((ref) {
  throw UnimplementedError(
    'memoriesDirProvider 未注入——请在 main() 的 ProviderScope.overrides 中提供记忆目录路径。',
  );
});

/// .greenix/skills/ 目录路径。
final skillsDirProvider = Provider<String>((ref) {
  throw UnimplementedError(
    'skillsDirProvider 未注入——请在 main() 的 ProviderScope.overrides 中提供 Skill 目录路径。',
  );
});

// ═══════ Agent 运行时 ═══════

/// 全局 AgentController——Chat 视图通过此 provider 发送消息、控制会话。
final agentControllerProvider = Provider<agent.Controller>((ref) {
  throw UnimplementedError(
    'agentControllerProvider 未注入——请在 main() 的 ProviderScope.overrides 中提供 Controller 实例。',
  );
});

/// Agent 事件流——Chat 视图通过此 provider 订阅 AgentEvent。
final agentEventStreamProvider = Provider<Stream<agent.AgentEvent>>((ref) {
  throw UnimplementedError(
    'agentEventStreamProvider 未注入——请在 main() 的 ProviderScope.overrides 中提供事件流。',
  );
});

/// 主 AI 助手实际使用的 DeepSeekProvider——由 app_bootstrap 注入。
///
/// 主全屏 AI 面板的 effort/thinking 调整，写入 `reasoningEffortProvider`
/// （状态源）后必须再调用本 provider 的 `setThinking` / `setReasoningEffort`，
/// 才能真实作用于请求参数（Task 五 A5 断链①修复）。
///
/// 注意：不要依赖 core/agent/agent_runtime.dart 的 `reasoningEffortProvider`
/// 监听——它只服务于 `agentRuntimeProvider` 自建 provider 实例（全局单例
/// 运行时无人消费，属于历史并行实现）；主路径的接线点在 app_bootstrap。
final agentProviderProvider = Provider<agent.DeepSeekProvider>((ref) {
  throw UnimplementedError(
    'agentProviderProvider 未注入——请在 main() 的 ProviderScope.overrides 中提供主 DeepSeekProvider 实例。',
  );
});

// ═══════ 记忆 + Skill ═══════

/// 全局记忆存储——`FileMemoryStore`，供全局记忆页面读写。
final memoryStoreProvider = Provider<FileMemoryStore>((ref) {
  throw UnimplementedError(
    'memoryStoreProvider 未注入——请在 main() 的 ProviderScope.overrides 中提供 FileMemoryStore 实例。',
  );
});

/// Skill 索引——供 Skill 管理页面列举。
final skillIndexProvider = Provider<SkillIndex>((ref) {
  throw UnimplementedError(
    'skillIndexProvider 未注入——请在 main() 的 ProviderScope.overrides 中提供 SkillIndex 实例。',
  );
});

/// Controller 运行状态——可被 Widget 监听。
final controllerStateProvider = StateProvider<ControllerState>((ref) {
  return ControllerState.idle;
});

// ═══════ 工具管理 ═══════

/// Agent 工具注册表——由 main() 注入，供渲染层读取工具列表和控制启用/禁用。
final toolRegistryProvider = Provider<Registry>((ref) {
  throw UnimplementedError(
    'toolRegistryProvider 未注入——请在 main() 的 ProviderScope.overrides 中提供 Registry 实例。',
  );
});

/// 被用户禁用的工具名称集合——持久化到 SharedPreferences。
/// UI 通过此 provider 响应式获取禁用状态。
final toolDisabledProvider = StateProvider<Set<String>>((ref) => {});

/// Agent 基础功能所必需的工具名称——禁用时会弹出警告。
///
/// | 工具 | 角色 | 禁用影响 |
/// |------|------|---------|
/// | `read_global_memory` | 记忆读取 | Agent 失去跨会话记忆，无法回忆用户偏好 |
/// | `write_global_memory` | 记忆写入 | Agent 无法记住用户特质和偏好 |
/// | `read_file` | 文件读取 | Agent 无法访问工作区文件 |
/// | `write_file` | 文件写入 | Agent 无法创建/编辑/保存文件 |
const essentialToolNames = <String>{
  'read_global_memory',
  'write_global_memory',
  'read_file',
  'write_file',
};

/// 判断工具名是否为 Agent 基础功能所必需。
bool isEssentialTool(String name) => essentialToolNames.contains(name);

// ═══════ 主题 ═══════

/// 全局 [ThemeStore]——主题注册、查询、活跃主题切换。
///
/// 当 [ThemeStore.activeTheme] 变更时（通过 HTTP POST /theme/active 或直接调用），
/// [ChangeNotifierProvider] 自动通知所有 watch 此 provider 的消费者重建。
final themeStoreProvider = ChangeNotifierProvider<ThemeStore>((ref) {
  throw UnimplementedError(
    'themeStoreProvider 未注入——请在 main() 的 ProviderScope.overrides 中提供 ThemeStore 实例。',
  );
});

// ═══════ 数据中枢 ═══════

/// 全局数据谱仪器——由 main() 注入，供渲染层查询数据源状态和拉取数据。
final dataOrchestratorProvider = Provider<DataOrchestrator>((ref) {
  throw UnimplementedError(
    'dataOrchestratorProvider 未注入——请在 main() 的 ProviderScope.overrides 中提供 DataOrchestrator 实例。',
  );
});

// ═══════ 配置层 ═══════

/// 全局 ConfigHttpServer——由 main() 注入，供渲染层热注册配置项。
final configHttpServerProvider = Provider<ConfigHttpServer>((ref) {
  throw UnimplementedError(
    'configHttpServerProvider 未注入——请在 main() 的 ProviderScope.overrides 中提供 ConfigHttpServer 实例。',
  );
});
