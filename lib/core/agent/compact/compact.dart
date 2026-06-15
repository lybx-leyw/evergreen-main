/// Compact 系统 — AI 驱动的上下文压实。
///
/// 当对话上下文接近 token 上限时，让 LLM 将中间消息总结为摘要，
/// 保留首尾完整消息。
library;

import '../agent/session.dart';
import '../message.dart';
import '../provider.dart';

/// AI 驱动的压实器——让 LLM 总结中间对话。
///
/// [memoryContext] — 全局记忆，压缩时作为关键事实保留参考传入 prompt。
class Compactor {
  final Provider _llm;
  final int contextWindow;
  final double softRatio;
  final double compactRatio;
  final double forceRatio;
  final int recentKeep;
  String _memoryContext = '';

  bool _softNoticed = false;

  Compactor({
    required Provider llm,
    required this.contextWindow,
    this.softRatio = 0.5,
    this.compactRatio = 0.7,
    this.forceRatio = 0.8,
    this.recentKeep = 10,
  }) : _llm = llm;

  /// 设置当前全局记忆（每次压缩前更新）。
  void setMemoryContext(String ctx) => _memoryContext = ctx;

  bool get enabled => contextWindow > 0;

  /// 检查是否需要压实。(should, trigger, isEmergency)
  (bool, String, bool) check(Session session) {
    if (!enabled) return (false, '', false);
    final estimated = session.estimatedContextTokens;
    final ratio = estimated / contextWindow;

    if (ratio >= forceRatio) return (true, 'force', true);
    if (ratio >= compactRatio) return (true, 'normal', false);
    if (ratio >= softRatio && !_softNoticed) {
      _softNoticed = true;
      return (true, 'soft', false);
    }
    return (false, '', false);
  }

  /// AI 驱动的压实——LLM 阅读中间消息，生成摘要替换。
  Future<Session> compact(Session session, String trigger) async {
    final msgCount = session.messages.length;
    if (msgCount <= recentKeep) return session;

    // 保留：系统消息 + 首 2 轮 + 尾 N 轮
    final headCount = 3;
    final tailCount = (recentKeep / 2).ceil();

    if (headCount + tailCount >= msgCount) return session;

    final head = session.messages.take(headCount).toList();
    final tail = session.messages.skip(msgCount - tailCount).toList();
    final middle = session.messages
        .skip(headCount)
        .take(msgCount - headCount - tailCount)
        .toList();

    if (middle.isEmpty) return session;

    // 让 LLM 总结中间内容
    final summary = await _aiSummarize(middle);

    session.messages.clear();
    session.messages.addAll(head);
    session.messages.add(Message.system(summary));
    session.messages.addAll(tail);

    return session;
  }

  Future<String> _aiSummarize(List<Message> messages) async {
    // 构建要总结的文本
    final buf = StringBuffer();
    for (final m in messages) {
      switch (m.role) {
        case Role.user:
          buf.writeln('用户：${_truncate(m.content, 300)}');
        case Role.assistant:
          if (m.hasToolCalls) {
            buf.writeln('助手调用了：${m.toolCalls.map((t) => t.name).join(", ")}');
          }
          if (m.content.isNotEmpty) {
            buf.writeln('助手：${_truncate(m.content, 300)}');
          }
        case Role.tool:
          buf.writeln('[工具结果：${_truncate(m.content, 100)}]');
        default:
          break;
      }
    }

    final memSection = _memoryContext.isNotEmpty
        ? '\n## 必须保留的关键事实（绝对不能丢失）\n$_memoryContext\n'
        : '';

    final prompt = '''请用中文简要总结以下对话历史的核心内容。保留：
- 用户问了什么问题
- 助手调用了哪些工具（如果调用了）
- 关键结论或重要信息
${_memoryContext.isNotEmpty ? '- **务必保留「必须保留的关键事实」中列出的所有信息**' : ''}

不需要逐条复述，一句话概况即可。
$memSection
对话：
${buf.toString()}

总结：''';

    final response = await _callLlm(prompt);
    return '[上下文摘要] ${response.trim()}';
  }

  Future<String> _callLlm(String prompt) async {
    final buf = StringBuffer();
    try {
      await for (final event in _llm.chat(
        messages: [Message.user(prompt)],
      )) {
        if (event.kind == ProviderEventKind.content && event.text != null) {
          buf.write(event.text);
        }
      }
    } catch (_) {
      return '(摘要生成失败)';
    }
    return buf.toString().isEmpty ? '(摘要生成失败)' : buf.toString();
  }

  String _truncate(String text, int maxLen) {
    if (text.length <= maxLen) return text;
    return '${text.substring(0, maxLen)}...';
  }

  void reset() {
    _softNoticed = false;
  }
}

/// 格式化的上下文使用比例。
String contextRatioDescription(int estimated, int window) {
  if (window <= 0) return '压缩已禁用';
  final ratio = estimated / window;
  final pct = (ratio * 100).toStringAsFixed(0);
  return '$pct% ($estimated / $window tok)';
}
