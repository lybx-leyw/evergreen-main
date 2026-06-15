/// Lightweight token estimator — character-based heuristic.
///
/// 中文字符 ≈ 1.5 tokens，ASCII 字符 ≈ 0.35 tokens。
/// 不引入完整 tokenizer，仅作为上下文的保守估算。
class TokenEstimator {
  static const Map<String, int> modelContextTokens = {
    'deepseek-chat': 65536,
    'deepseek-reasoner': 65536,
    'deepseek-v4-flash': 131072,
    'deepseek-v4-pro': 131072,
  };

  /// 估算单段文本的 token 数量。
  static int estimate(String text) {
    if (text.isEmpty) return 0;

    int ascii = 0;
    int nonAscii = 0;

    for (int i = 0; i < text.length; i++) {
      final code = text.codeUnitAt(i);
      if (code < 0x80) {
        ascii++;
      } else {
        nonAscii++;
      }
    }

    // ASCII ≈ 0.35, 非 ASCII（CJK 等）≈ 1.5
    return (ascii * 0.35).ceil() + (nonAscii * 1.5).ceil();
  }

  /// 估算一个对话的 token 总量（含每条消息 ~4 token role 开销）。
  static int estimateConversation(List<Map<String, dynamic>> messages) {
    int total = 0;
    for (final msg in messages) {
      total += 4;
      final content = msg['content'];
      if (content is String) {
        total += estimate(content);
      } else if (content is List) {
        for (final part in content) {
          if (part is Map && part['text'] != null) {
            total += estimate(part['text'] as String);
          }
        }
      }
      if (msg['tool_calls'] != null) {
        total += estimate(msg['tool_calls'].toString());
      }
      if (msg['reasoning_content'] != null) {
        total += estimate(msg['reasoning_content'].toString());
      }
    }
    return total;
  }
}
