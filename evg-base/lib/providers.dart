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

/// 内置模块根目录——`$projectRoot/lib/core/builtins/`。
final builtinsDirProvider = Provider<String>((ref) {
  throw UnimplementedError(
    'builtinsDirProvider 未注入——请在 main() 的 ProviderScope.overrides 中提供内置模块目录路径。',
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
