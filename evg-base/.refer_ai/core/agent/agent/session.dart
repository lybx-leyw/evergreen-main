/// Session — 对话会话管理。
///
/// 对应 reasonix/internal/agent/session.go。
/// 管理消息历史、token 统计、元数据。
library;

import 'package:uuid/uuid.dart';

import '../message.dart';
import '../event.dart';

/// 会话状态。
class Session {
  /// 消息历史（完整无损）。
  final List<Message> messages = [];

  /// 会话元数据。
  String id;
  String title;
  DateTime createdAt;
  DateTime updatedAt;

  /// Token 统计（累计）。
  int totalPromptTokens = 0;
  int totalCompletionTokens = 0;
  int totalCacheHitTokens = 0;
  int totalCacheMissTokens = 0;

  /// 当前回合的 token 用量（最后一次 LLM 调用）。
  TokenUsage? lastUsage;

  Session({
    String? id,
    this.title = '',
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? _generateId(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// 添加一条消息到历史。
  void add(Message message) {
    messages.add(message);
    updatedAt = DateTime.now();
  }

  /// 添加多条消息。
  void addAll(List<Message> msgs) {
    messages.addAll(msgs);
    updatedAt = DateTime.now();
  }

  /// 获取最后 N 条消息。
  List<Message> last(int n) {
    if (n >= messages.length) return List.from(messages);
    return messages.sublist(messages.length - n);
  }

  /// 获取系统提示消息（第一条 role=system 的消息）。
  Message? get systemMessage {
    try {
      return messages.firstWhere((m) => m.role == Role.system);
    } catch (_) {
      return null;
    }
  }

  /// 移除第一条系统提示消息（用于替换）。
  void removeSystemMessage() {
    messages.removeWhere((m) => m.role == Role.system);
  }

  /// 更新系统提示消息（替换已有的或追加到开头）。
  void setSystemMessage(String content) {
    removeSystemMessage();
    messages.insert(0, Message.system(content));
  }

  /// 累计 token 用量。
  void accumulateUsage(TokenUsage usage) {
    totalPromptTokens += usage.promptTokens;
    totalCompletionTokens += usage.completionTokens;
    totalCacheHitTokens += usage.promptCacheHitTokens ?? 0;
    totalCacheMissTokens += usage.promptCacheMissTokens ?? 0;
    lastUsage = usage;
  }

  /// 缓存的命中率（累计）。
  double get cacheHitRate {
    final total = totalCacheHitTokens + totalCacheMissTokens;
    if (total == 0) return 0;
    return totalCacheHitTokens / total;
  }

  /// 总 token 数。
  int get totalTokens => totalPromptTokens + totalCompletionTokens;

  /// 消息数量。
  int get messageCount => messages.length;

  /// 估算的上下文 token 数（近似，用于压实判断）。
  int get estimatedContextTokens {
    int total = 0;
    for (final msg in messages) {
      total += msg.content.length ~/ 2; // 粗略估算：~2 chars/token for Chinese
      total += msg.reasoningContent.length ~/ 2;
      if (msg.hasToolCalls) {
        for (final tc in msg.toolCalls) {
          total += tc.name.length ~/ 2;
          total += tc.arguments.length ~/ 2;
        }
      }
    }
    return total;
  }

  /// 创建快照（用于序列化/持久化）。
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'messages': messages.map((m) => m.toJson()).toList(),
        'total_prompt_tokens': totalPromptTokens,
        'total_completion_tokens': totalCompletionTokens,
        'total_cache_hit_tokens': totalCacheHitTokens,
        'total_cache_miss_tokens': totalCacheMissTokens,
      };

  /// 从快照恢复。
  factory Session.fromJson(Map<String, dynamic> json) {
    final session = Session(
      id: json['id']?.toString(),
      title: json['title']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? ''),
    );
    final msgs = json['messages'] as List? ?? [];
    for (final m in msgs) {
      final msg = m as Map<String, dynamic>;
      final role = Role.values.firstWhere(
          (r) => r.value == msg['role'],
          orElse: () => Role.user);
      session.messages.add(Message(
        role: role,
        content: msg['content']?.toString() ?? '',
        reasoningContent: msg['reasoning_content']?.toString() ?? '',
        toolCalls: (msg['tool_calls'] as List?)
                ?.map((tc) => ToolCall.fromJson(tc as Map<String, dynamic>))
                .toList() ??
            [],
        toolCallId: msg['tool_call_id']?.toString() ?? '',
        name: msg['name']?.toString() ?? '',
      ));
    }
    session.totalPromptTokens = json['total_prompt_tokens'] ?? 0;
    session.totalCompletionTokens = json['total_completion_tokens'] ?? 0;
    session.totalCacheHitTokens = json['total_cache_hit_tokens'] ?? 0;
    session.totalCacheMissTokens = json['total_cache_miss_tokens'] ?? 0;
    return session;
  }

  static final _uuid = Uuid();

  static String _generateId() {
    return 'session_${_uuid.v4()}';
  }
}
