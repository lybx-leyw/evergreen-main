/// Message, ToolCall, ToolSchema — 对话消息数据模型。
///
/// 完整对应 reasonix/internal/provider/provider.go：
///   Message, ToolCall, ToolSchema, SanitizeToolPairing
library;

/// 消息角色，对应 Go 的 provider.Role。
enum Role {
  system,
  user,
  assistant,
  tool;

  String get value {
    switch (this) {
      case Role.system:
        return 'system';
      case Role.user:
        return 'user';
      case Role.assistant:
        return 'assistant';
      case Role.tool:
        return 'tool';
    }
  }
}

/// 一次工具调用请求，由模型发出。
///
/// 对应 Go 的 provider.ToolCall。
class ToolCall {
  final String id;
  final String name;
  final String arguments; // raw JSON string

  const ToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': 'function',
        'function': {
          'name': name,
          'arguments': arguments,
        },
      };

  factory ToolCall.fromJson(Map<String, dynamic> json) {
    // OpenAI/DeepSeek format: { id, type: "function", function: { name, arguments } }
    final func = json['function'] as Map<String, dynamic>? ?? json;
    return ToolCall(
      id: json['id']?.toString() ?? '',
      name: func['name']?.toString() ?? '',
      arguments: func['arguments']?.toString() ?? '{}',
    );
  }

  @override
  String toString() => 'ToolCall($name id=$id)';
}

/// 暴露给模型的工具定义（OpenAI Tool Schema 格式）。
///
/// 对应 Go 的 provider.ToolSchema。
class ToolSchema {
  final String name;
  final String description;
  final Map<String, dynamic> parameters;

  const ToolSchema({
    required this.name,
    required this.description,
    required this.parameters,
  });

  Map<String, dynamic> toJson() => {
        'type': 'function',
        'function': {
          'name': name,
          'description': description,
          'parameters': parameters,
        },
      };
}

/// 单条对话消息。
///
/// 对应 Go 的 provider.Message。
class Message {
  final Role role;
  final String content;
  final String reasoningContent;
  final String reasoningSignature; // opaque provider token; round-tripped
  final List<ToolCall> toolCalls; // assistant side: tool call requests
  final String toolCallId; // tool side: links result to call
  final String name; // tool side: tool name

  const Message({
    required this.role,
    this.content = '',
    this.reasoningContent = '',
    this.reasoningSignature = '',
    this.toolCalls = const [],
    this.toolCallId = '',
    this.name = '',
  });

  bool get hasToolCalls => toolCalls.isNotEmpty;
  bool get isToolResult => role == Role.tool;
  bool get isUser => role == Role.user;
  bool get isAssistant => role == Role.assistant;

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'role': role.value,
    };

    // OpenAI/DeepSeek API 格式要求：
    // - 文本内容: content (可为空字符串)
    // - tool_calls: 仅在 assistant 消息中
    // - reasoning_content: DeepSeek 专用，保存推理过程
    // - tool_call_id + content: 仅在 tool 消息中

    if (role == Role.assistant) {
      if (hasToolCalls) {
        json['content'] = content.isNotEmpty ? content : null;
        json['tool_calls'] = toolCalls.map((t) => t.toJson()).toList();
      } else {
        json['content'] = content;
      }
      if (reasoningContent.isNotEmpty) {
        json['reasoning_content'] = reasoningContent;
      }
    } else if (role == Role.tool) {
      json['tool_call_id'] = toolCallId;
      json['content'] = content;
    } else {
      json['content'] = content;
    }

    return json;
  }

  /// Assistant 消息工厂：纯文本。
  factory Message.assistant(String content, {String reasoning = ''}) {
    return Message(
      role: Role.assistant,
      content: content,
      reasoningContent: reasoning,
    );
  }

  /// Assistant 消息工厂：工具调用。
  factory Message.assistantTool(List<ToolCall> calls) {
    return Message(role: Role.assistant, toolCalls: calls);
  }

  /// Tool 结果消息工厂。
  factory Message.toolResult(String toolCallId, String content, {String name = ''}) {
    return Message(
      role: Role.tool,
      toolCallId: toolCallId,
      content: content,
      name: name,
    );
  }

  /// 用户消息工厂。
  factory Message.user(String content) {
    return Message(role: Role.user, content: content);
  }

  /// 系统消息工厂。
  factory Message.system(String content) {
    return Message(role: Role.system, content: content);
  }

  @override
  String toString() => 'Message(${role.value} ${hasToolCalls ? "tool_calls:${toolCalls.length}" : "content:${content.length}chars"})';
}

/// 修复消息历史的 tool_calls 配对关系。
///
/// OpenAI/DeepSeek API 要求：
///   每个 assistant tool_calls 消息后面必须有对应的 tool 消息回应。
///   孤立的 tool 消息必须被移除。
///
/// 对应 Go 的 provider.SanitizeToolPairing()。
List<Message> sanitizeToolPairing(List<Message> messages) {
  final out = <Message>[];
  for (final msg in messages) {
    if (msg.isToolResult) {
      // 检查前面是否有关联的 assistant tool_calls
      final hasMatchingCall = out.any((m) =>
          m.isAssistant &&
          m.hasToolCalls &&
          m.toolCalls.any((tc) => tc.id == msg.toolCallId));
      if (!hasMatchingCall) {
        // 孤立 tool 消息 — 丢弃
        continue;
      }
    }
    out.add(msg);
  }
  return out;
}

/// 被中断的工具调用的占位结果。
/// 用于修复 session 恢复时未完成的 tool_calls 链。
const String interruptedToolResult =
    '[no result: the previous turn was interrupted before this tool call completed]';
