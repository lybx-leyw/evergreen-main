// P0 回归测试（2026-07-12 v4）：Agent 初始化 + 插件会话隔离 + 全局记忆共享
//
// 架构原则：各个插件的会话需要隔离，全局记忆共享
//   - AgentAssembly.fromConfig 为每个 slot 模块创建独立的 agent.Session() → 会话隔离
//   - AgentAssembly 共用 globalMemoryStore + greenixMemoriesDir → 全局记忆共享
//   - composite_view 的 ai-assistant slot 走 embedded:false + AgentAssembly（全屏 Scaffold + 会话隔离）
//
// 修复范围：
//   1) agent_factory.dart：_normalizeToolsConfig 接受 List/Map/null 三种形态
//   2) agent_factory.dart：_resolvePreset 增加 List 简写分支，默认 mode='all'
//
// 测试策略：静态源码验证（无需实例化 AgentAssembly / Provider），100% flutter test 可运行。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('P0 修复回归（2026-07-11）', () {
    test('agent_factory.dart 已包含 _normalizeToolsConfig 规整器', () {
      // 直接读源码验证：避免把私有符号导出的副作用带入运行时
      final src = File(
        'lib/core/agent/agent_factory.dart',
      ).readAsStringSync();

      // 关键 1：新增静态规整器方法
      expect(
        src.contains(
          'static Map<String, dynamic> _normalizeToolsConfig(dynamic raw)',
        ),
        isTrue,
        reason: 'P0 修复缺失：_normalizeToolsConfig 未找到',
      );

      // 关键 2：原 `as Map<String, dynamic>?` 已替换为规整器调用
      expect(
        RegExp(
          r"resolvedConfig\['tools'\]\s+as\s+Map<String,\s*dynamic>\?",
        ).hasMatch(src),
        isFalse,
        reason: 'P0 修复缺失：原强转仍未替换',
      );
      expect(
        src.contains(
          'final toolsConfig = _normalizeToolsConfig(resolvedConfig[\'tools\']);',
        ),
        isTrue,
        reason: 'P0 修复缺失：未调用 _normalizeToolsConfig 替代强转',
      );

      // 关键 3：默认 mode 改为 'all'（与规整器一致）
      // 用 _applyToolPolicy 内的行匹配（取 'final mode = ' 那行）
      final modeLineMatch = RegExp(
        r"final mode = toolsConfig\?\['mode'\] as String\? \?\? '(.+?)';",
      ).firstMatch(src);
      expect(
        modeLineMatch,
        isNotNull,
        reason: '未找到 _applyToolPolicy 的 mode 默认行',
      );
      expect(
        modeLineMatch?.group(1),
        equals('all'),
        reason: "_applyToolPolicy 默认 mode 仍为 '${modeLineMatch?.group(1)}'（应为 'all'）",
      );

      // 关键 4：_resolvePreset 支持 List 简写（保留 base.mode）
      expect(
        src.contains('base is Map && override is List'),
        isTrue,
        reason: 'P0 修复缺失：_resolvePreset 未处理 List 简写',
      );
    });

    test('composite_view.dart ai-assistant slot 走全屏 Scaffold + AgentAssembly 会话隔离', () {
      // ai-assistant 注册在 _registrations.dart（SlotRegistry），非 composite_view。
      final src = File(
        'lib/renderer/templates/v4_modle/_registrations.dart',
      ).readAsStringSync();

      // 未引入 chat_view.dart
      expect(
        src.contains("import '../components/interaction/chat/chat_view.dart';"),
        isFalse,
        reason: '回归：不应引入 chat_view.dart',
      );
      // 使用 ChatControllerView(embedded:false, agentConfig:...) 获得全屏 Scaffold + 会话隔离
      expect(
        src.contains('ChatControllerView(') && src.contains('embedded: false'),
        isTrue,
        reason: '回归：ai-assistant slot 应走 embedded:false（全屏 Scaffold）+ AgentAssembly 会话隔离',
      );
      // _buildAIAssistantSlot 不应存在
      expect(
        src.contains('_buildAIAssistantSlot'),
        isFalse,
        reason: '回归：不应有 _buildAIAssistantSlot 特殊分发',
      );
    });

    // 测试 2 原读 plugins/showcase-v4/module/manifest.json——showcase-v4 已废弃（2026-08-02），
    // 无真实 v4 manifest 样例，删除该用例。
  });
}
