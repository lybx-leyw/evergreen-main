/// Minimal port of reasonix/internal/provider usage types.
library;

class Usage {
  int promptTokens = 0;
  int completionTokens = 0;
  int totalTokens = 0;
  int? cacheHitTokens;
  int? cacheMissTokens;
  int reasoningTokens = 0;
  bool estimated = false;
  String finishReason = '';
  int requestCount = 0;
  int contextPromptTokens = 0;
  int contextCompletionTokens = 0;
  int contextReasoningTokens = 0;
  int contextCacheHitTokens = 0;
  int contextCacheMissTokens = 0;
  int cacheWriteTokens = 0;
  int cacheWriteBilledTokens = 0;

  /// Latest-attempt prompt size for context-aware runtime decisions; falls
  /// back to [promptTokens] for single-attempt legacy usage.
  int latestPromptTokens() =>
      contextPromptTokens > 0 ? contextPromptTokens : promptTokens;
}

class MemoryCitation {
  String id = '';
  String source = '';
  int lineStart = 0;
  int lineEnd = 0;
  String note = '';
  String kind = '';

  MemoryCitation({
    this.id = '',
    required this.source,
    this.lineStart = 0,
    this.lineEnd = 0,
    this.note = '',
    this.kind = '',
  });
}
