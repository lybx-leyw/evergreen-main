// 验证 slot（嵌入）版 AI 助手具备完整工具能力（Bug 1 修复）。
//
// 运行：cd evg-base && flutter test test/embedded_agent_tools_test.dart
//
// 回归点：
// - 此前 ChatControllerView._initEmbeddedAgent 调用 AgentAssembly.fromConfig 时
//   未传 seedTools，导致嵌入 Agent 注册表为空、preset research-full 的
//   tools:{mode:all} 在空注册表上等价于"启用 0 个工具"，无法工具调用循环。
// - AgentAssembly.buildStandardTools 提供与全局 AgentRuntime 一致的标准工具集。

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:evergreen_base/core/agent/agent.dart' as agent;
import 'package:evergreen_base/core/agent/agent_factory.dart';
import 'package:evergreen_base/core/agent/memory/file_memory_store.dart';
import 'package:evergreen_base/core/agent/skill/skill.dart';
import 'package:evergreen_base/core/utils/greenix_path.dart';

void main() {
  test('buildStandardTools 返回与全局 Runtime 一致的标准工具集', () {
    final store = FileMemoryStore(greenixMemoriesDir);
    final provider = agent.DeepSeekProvider(dio: Dio(), apiKey: 'test-key');
    final skillIndex = SkillIndex();

    final tools = AgentAssembly.buildStandardTools(
      globalStore: store,
      provider: provider,
      skillIndex: skillIndex,
    );

    expect(tools, isNotEmpty, reason: '标准工具集不应为空');
    final names = tools.map((t) => t.name).toSet();
    // 全局 Runtime 注册的核心工具
    for (final expected in const [
      'get_user_info',
      'read_global_memory',
      'write_global_memory',
      'read_file',
      'write_file',
      'run_skill',
      'list_skills',
      'web_search',
      'web_fetch',
    ]) {
      expect(names, contains(expected),
          reason: '标准工具集应含 $expected');
    }
  });

  test('嵌入 Agent 用 research-full 预设应启用工具（可工具调用循环）', () {
    final store = FileMemoryStore(greenixMemoriesDir);
    final provider = agent.DeepSeekProvider(dio: Dio(), apiKey: 'test-key');
    final skillIndex = SkillIndex();

    final seedTools = AgentAssembly.buildStandardTools(
      globalStore: store,
      provider: provider,
      skillIndex: skillIndex,
    );

    final assembly = AgentAssembly.fromConfig(
      moduleId: 'test/embedded',
      config: const {'preset': 'research-full'},
      sharedProvider: provider,
      globalSkillIndex: skillIndex,
      globalMemoryStore: store,
      seedTools: seedTools,
    );

    // 修复前：注册表为空 → enabled() 为 0，无法工具调用。
    expect(assembly.registry.enabled().length, greaterThan(0),
        reason: '嵌入 Agent 必须启用工具以支持工具调用循环');
    // research-full 预设 tools mode=all → 全部候选工具启用
    expect(assembly.registry.enabled().length, equals(seedTools.length),
        reason: 'research-full 的 tools:{mode:all} 应启用全部标准工具');
  });

  test('嵌入 Agent 用 qa-basic 预设应禁用全部工具（纯对话）', () {
    final store = FileMemoryStore(greenixMemoriesDir);
    final provider = agent.DeepSeekProvider(dio: Dio(), apiKey: 'test-key');
    final skillIndex = SkillIndex();

    final seedTools = AgentAssembly.buildStandardTools(
      globalStore: store,
      provider: provider,
      skillIndex: skillIndex,
    );

    final assembly = AgentAssembly.fromConfig(
      moduleId: 'test/embedded-qa',
      config: const {'preset': 'qa-basic'},
      sharedProvider: provider,
      globalSkillIndex: skillIndex,
      globalMemoryStore: store,
      seedTools: seedTools,
    );

    expect(assembly.registry.enabled().length, equals(0),
        reason: 'qa-basic 的 tools:{mode:none} 应禁用全部工具');
  });
}
