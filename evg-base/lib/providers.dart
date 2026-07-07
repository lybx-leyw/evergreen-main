/// 应用级 Riverpod 提供者——模块注册中心 + SharedPreferences + 插件目录 + Agent 运行时 + 记忆 + Skill。
///
/// 渲染层通过本文件获取全局实例，避免循环依赖。
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:evergreen_base/core/module/module_registry.dart';
import 'package:evergreen_base/core/agent/controller/controller.dart' as agent;
import 'package:evergreen_base/core/agent/event.dart' as agent;
import 'package:evergreen_base/core/agent/memory/file_memory_store.dart';
import 'package:evergreen_base/core/agent/skill/skill.dart';
import 'package:evergreen_base/core/agent/controller/controller.dart' show ControllerState;
import 'package:evergreen_base/core/agent/tool.dart' show Registry;
import 'package:evergreen_base/core/data/orchestrator.dart' show DataOrchestrator;

/// 全局模块注册中心——在 main() 中创建、填充、密封后通过 ProviderScope.overrides 注入。
final moduleRegistryProvider = Provider<ModuleRegistry>((ref) {
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

// ═══════ 数据中枢 ═══════

/// 全局数据谱仪器——由 main() 注入，供渲染层查询数据源状态和拉取数据。
final dataOrchestratorProvider = Provider<DataOrchestrator>((ref) {
  throw UnimplementedError(
    'dataOrchestratorProvider 未注入——请在 main() 的 ProviderScope.overrides 中提供 DataOrchestrator 实例。',
  );
});
