import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../services/deepseek_client.dart';

/// Provider for DeepSeek client.
final deepseekClientProvider = Provider<DeepSeekClient>((ref) {
  final dio = ref.read(dioClientProvider);
  return DeepSeekClient(dio);
});

/// Provider for streaming chat state.
class StreamingChatNotifier extends StateNotifier<StreamingChatState> {
  final DeepSeekClient _client;
  String _fullContent = '';

  StreamingChatNotifier(this._client) : super(const StreamingChatState());

  String get fullContent => _fullContent;

  Future<void> sendMessage(List<Map<String, dynamic>> messages) async {
    state = const StreamingChatState(isStreaming: true);
    _fullContent = '';

    try {
      await for (final chunk in _client.streamChat(messages)) {
        if (chunk.type == StreamChunkType.content) {
          _fullContent += chunk.content!;
          state = StreamingChatState(
            isStreaming: true,
            content: _fullContent,
            reasoning: state.reasoning,
          );
        } else if (chunk.type == StreamChunkType.reasoning) {
          state = StreamingChatState(
            isStreaming: true,
            content: _fullContent,
            reasoning: '${state.reasoning ?? ''}${chunk.content!}',
          );
        } else if (chunk.type == StreamChunkType.error) {
          state = StreamingChatState(
            isStreaming: false,
            content: _fullContent.isNotEmpty ? _fullContent : null,
            error: chunk.content ?? chunk.error?.userMessage ?? 'AI 请求失败',
          );
          return;
        } else if (chunk.type == StreamChunkType.done) {
          state = StreamingChatState(
            isStreaming: false,
            content: _fullContent,
            reasoning: state.reasoning,
            usage: chunk.usage,
          );
        }
      }
    } catch (e) {
      state = StreamingChatState(
        isStreaming: false,
        content: _fullContent.isNotEmpty ? _fullContent : null,
        error: e.toString(),
      );
    }
  }

  void clear() {
    _fullContent = '';
    state = const StreamingChatState();
  }
}

class StreamingChatState {
  final bool isStreaming;
  final String? content;
  final String? reasoning;
  final Usage? usage;
  final String? error;

  const StreamingChatState({
    this.isStreaming = false,
    this.content,
    this.reasoning,
    this.usage,
    this.error,
  });
}

final streamingChatProvider =
    StateNotifierProvider<StreamingChatNotifier, StreamingChatState>((ref) {
  final client = ref.read(deepseekClientProvider);
  return StreamingChatNotifier(client);
});
