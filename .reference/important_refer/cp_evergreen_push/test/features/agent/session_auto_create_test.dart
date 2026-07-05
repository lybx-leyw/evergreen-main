import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:evergreen_multi_tools/core/agent/agent.dart' as agent;
import 'package:evergreen_multi_tools/features/agent/providers/agent_provider.dart';
import '../../mocks/fake_path_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // 为 path_provider 提供 platform channel mock（避免 MissingPluginException）
    PathProviderPlatform.instance = FakePathProviderPlatform();
  });

  group('Session auto-create', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('初始无活动会话 → activeSessionId 为 null', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(activeSessionIdProvider), isNull);
    });

    test('createSessionProvider 创建新会话 → activeSessionId 非空', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(createSessionProvider)('测试对话');
      // activeSessionId 是同步设置的（在 async 之前）
      expect(container.read(activeSessionIdProvider), isNotNull);
    });

    test('createSessionProvider 多次创建产生不同的会话ID', () {
      // 两个独立的 ProviderContainer，各自创建一次，验证 ID 不会因跨容器缓存而碰撞
      final c1 = ProviderContainer();
      addTearDown(c1.dispose);
      c1.read(createSessionProvider)('会话A');
      final idA = c1.read(activeSessionIdProvider);
      expect(idA, isNotNull);

      final c2 = ProviderContainer();
      addTearDown(c2.dispose);
      c2.read(createSessionProvider)('会话B');
      final idB = c2.read(activeSessionIdProvider);
      expect(idB, isNotNull);
      expect(idB, isNot(idA));
    });

    test('activeSessionTitleProvider 无会话时返回默认值', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(activeSessionTitleProvider), 'AI 助手');
    });

    test('deleteSessionProvider 删除当前会话后 activeSessionId 变 null', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(createSessionProvider)('待删除');
      final id = container.read(activeSessionIdProvider);
      expect(id, isNotNull);

      container.read(deleteSessionProvider)(id!);
      // deleteSessionProvider 已改为同步清空 activeSessionId
      expect(container.read(activeSessionIdProvider), isNull);
    });

    test('chatMessagesProvider 创建会话后清空', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // 添加一条旧消息
      container.read(chatMessagesProvider.notifier).addUser('旧消息');
      expect(container.read(chatMessagesProvider).length, 1);

      // 创建新会话 → 清空
      container.read(createSessionProvider)('新会话');
      expect(container.read(chatMessagesProvider).length, 0);
    });
  });

  group('ChatMessagesNotifier', () {
    test('addNotice 添加系统通知消息', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(chatMessagesProvider.notifier).addNotice('🧠 记忆已更新：新增 2 条');
      final messages = container.read(chatMessagesProvider);
      expect(messages.length, 1);
      expect(messages.first.role, agent.Role.system);
      expect(messages.first.content, contains('记忆已更新'));
    });

    test('addNotice 可多次调用', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(chatMessagesProvider.notifier);
      notifier.addNotice('第一条通知');
      notifier.addNotice('第二条通知');
      final messages = container.read(chatMessagesProvider);
      expect(messages.length, 2);
      expect(messages[0].role, agent.Role.system);
      expect(messages[1].role, agent.Role.system);
    });

    test('addUser + addNotice 混合消息保持顺序', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(chatMessagesProvider.notifier);
      notifier.addUser('用户消息');
      notifier.addNotice('🧠 系统通知');
      final messages = container.read(chatMessagesProvider);
      expect(messages.length, 2);
      expect(messages[0].role, agent.Role.user);
      expect(messages[1].role, agent.Role.system);
    });

    test('addAssistant 正常添加助手消息', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(chatMessagesProvider.notifier).addAssistant('助手回复');
      final messages = container.read(chatMessagesProvider);
      expect(messages.length, 1);
      expect(messages.first.role, agent.Role.assistant);
      expect(messages.first.content, '助手回复');
    });

    test('addAssistant 带 reasoning 参数', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(chatMessagesProvider.notifier).addAssistant(
        '助手回复',
        reasoning: '思考过程...',
      );
      final messages = container.read(chatMessagesProvider);
      expect(messages.first.reasoningContent, '思考过程...');
    });

    test('updateLastAssistant 当列表为空时追加', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(chatMessagesProvider.notifier).updateLastAssistant('新消息');
      final messages = container.read(chatMessagesProvider);
      expect(messages.length, 1);
      expect(messages.first.content, '新消息');
    });

    test('updateLastAssistant 当最后一条是助手消息时追加内容（流式合并）', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(chatMessagesProvider.notifier);
      notifier.addAssistant('原始内容');
      notifier.updateLastAssistant('更新后的内容');
      final messages = container.read(chatMessagesProvider);
      expect(messages.length, 1);
      expect(messages.first.content, '原始内容更新后的内容');
    });

    test('replaceLastAssistant 替换最后一条助手消息内容', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(chatMessagesProvider.notifier);
      notifier.addAssistant('旧内容旧内容');
      notifier.replaceLastAssistant('新内容');
      final messages = container.read(chatMessagesProvider);
      expect(messages.length, 1);
      expect(messages.first.content, '新内容');
    });

    test('replaceLastAssistant 当最后一条是用户消息时追加', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(chatMessagesProvider.notifier);
      notifier.addUser('用户');
      notifier.replaceLastAssistant('新助手');
      final messages = container.read(chatMessagesProvider);
      expect(messages.length, 2);
      expect(messages.last.content, '新助手');
    });

    test('updateLastAssistant 当最后一条是用户消息时追加新消息', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(chatMessagesProvider.notifier);
      notifier.addUser('用户消息');
      notifier.updateLastAssistant('助手新消息');
      final messages = container.read(chatMessagesProvider);
      expect(messages.length, 2);
      expect(messages.last.content, '助手新消息');
    });

    test('ChatMessage 带 isToolCall 标记', () {
      const msg = ChatMessage(
        role: agent.Role.assistant,
        content: '工具调用',
        isToolCall: true,
      );
      expect(msg.isToolCall, isTrue);
      expect(msg.isToolResultCard, isFalse);
    });

    test('ChatMessage 带 isToolResultCard 标记', () {
      const msg = ChatMessage(
        role: agent.Role.assistant,
        content: '工具结果',
        isToolResultCard: true,
      );
      expect(msg.isToolCall, isFalse);
      expect(msg.isToolResultCard, isTrue);
    });

    test('ChatMessage 默认标记为 false', () {
      const msg = ChatMessage(role: agent.Role.user, content: 'hello');
      expect(msg.isToolCall, isFalse);
      expect(msg.isToolResultCard, isFalse);
    });
  });
}
