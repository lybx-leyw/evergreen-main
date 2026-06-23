/// Palace 捕捉浮窗状态 Provider。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/agent/provider.dart' show DeepSeekProvider;
import '../../../core/palace/capture/quick_capture_service.dart';
import '../../../core/palace/models/consciousness_event.dart';
import '../../../core/palace/models/context_snapshot.dart';
import '../../../core/palace/refinery/auto_tagger.dart';
import '../../../core/palace/refinery/lesson_extractor.dart';
import '../../../core/palace/refinery/question_generator.dart';
import '../../agent/providers/agent_provider.dart' show agentRuntimeProvider;
import 'palace_event_store_provider.dart';
import 'palace_events_provider.dart';
import 'palace_lessons_provider.dart';
import 'palace_tags_provider.dart';

/// 捕捉浮窗状态。
class PalaceCaptureState {
  final bool isOpen;
  final String content;
  final EventType selectedType;
  final double? emotionalValence;
  final List<String> tags;
  final String newTagInput;
  final bool isLoading;
  final String? loadingStage;
  final SourceTool source;
  final ContextSnapshot? context;
  final CaptureResult? lastResult;
  final String? errorMessage;

  const PalaceCaptureState({
    this.isOpen = false,
    this.content = '',
    this.selectedType = EventType.thought,
    this.emotionalValence,
    this.tags = const [],
    this.newTagInput = '',
    this.isLoading = false,
    this.loadingStage,
    this.source = SourceTool.manual,
    this.context,
    this.lastResult,
    this.errorMessage,
  });

  PalaceCaptureState copyWith({
    bool? isOpen,
    String? content,
    EventType? selectedType,
    double? emotionalValence,
    List<String>? tags,
    String? newTagInput,
    bool? isLoading,
    String? loadingStage,
    SourceTool? source,
    ContextSnapshot? context,
    CaptureResult? lastResult,
    String? errorMessage,
    bool clearEmotion = false,
    bool clearResult = false,
  }) {
    return PalaceCaptureState(
      isOpen: isOpen ?? this.isOpen,
      content: content ?? this.content,
      selectedType: selectedType ?? this.selectedType,
      emotionalValence: clearEmotion ? null : (emotionalValence ?? this.emotionalValence),
      tags: tags ?? this.tags,
      newTagInput: newTagInput ?? this.newTagInput,
      isLoading: isLoading ?? this.isLoading,
      loadingStage: loadingStage ?? this.loadingStage,
      source: source ?? this.source,
      context: context ?? this.context,
      lastResult: clearResult ? null : (lastResult ?? this.lastResult),
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class PalaceCaptureNotifier extends StateNotifier<PalaceCaptureState> {
  final Ref _ref;
  QuickCaptureService? _cachedCaptureService;

  PalaceCaptureNotifier(this._ref) : super(const PalaceCaptureState());

  /// 从 Agent 运行时获取共享的 DeepSeekProvider。
  DeepSeekProvider get _llm {
    final runtime = _ref.read(agentRuntimeProvider);
    return runtime.controller.provider as DeepSeekProvider;
  }

  /// 懒创建 QuickCaptureService（复用 Agent 的 DeepSeekProvider）。
  QuickCaptureService get _captureService {
    return _cachedCaptureService ??= QuickCaptureService(
      store: _ref.read(palaceEventStoreProvider),
      lessonExtractor: LessonExtractor(_llm),
      questionGenerator: QuestionGenerator(_llm),
      autoTagger: AutoTagger(_llm),
      llm: _llm,
    );
  }

  void open({
    SourceTool source = SourceTool.manual,
    ContextSnapshot? context,
    String? initialContent,
  }) {
    state = PalaceCaptureState(
      isOpen: true,
      content: initialContent ?? '',
      source: source,
      context: context,
    );
  }

  void close() {
    state = const PalaceCaptureState();
  }

  void updateContent(String text) => state = state.copyWith(content: text);
  void updateType(EventType type) => state = state.copyWith(selectedType: type);
  void updateEmotion(double? valence) =>
      state = state.copyWith(emotionalValence: valence, clearEmotion: valence == null);
  void updateNewTagInput(String input) =>
      state = state.copyWith(newTagInput: input);

  void addTag(String tag) {
    if (tag.isEmpty || state.tags.contains(tag)) return;
    state = state.copyWith(tags: [...state.tags, tag], newTagInput: '');
  }

  void removeTag(String tag) {
    state = state.copyWith(tags: state.tags.where((t) => t != tag).toList());
  }

  Future<void> submit() async {
    if (state.content.trim().isEmpty) {
      state = state.copyWith(errorMessage: '请输入内容');
      return;
    }

    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final result = await _captureService.capture(
        rawContent: state.content,
        type: state.selectedType,
        source: state.source,
        emotionalValence: state.emotionalValence,
        tags: state.tags,
        context: state.context,
        onProgress: (stage) {
          state = state.copyWith(loadingStage: stage);
        },
      );

      state = state.copyWith(
        isLoading: false,
        loadingStage: null,
        lastResult: result,
      );

      _ref.invalidate(palaceEventsProvider);
      _ref.invalidate(palaceTagsProvider);
      _ref.invalidate(palaceLessonsProvider);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        loadingStage: null,
        errorMessage: '写入失败: $e',
      );
    }
  }

  void confirmLesson() {
    final result = state.lastResult;
    if (result?.lesson == null) return;
    final confirmed = result!.lesson!.confirm();
    _ref.read(palaceLessonsProvider.notifier).updateLesson(confirmed);
    state = state.copyWith(
      lastResult: CaptureResult(
        event: result.event,
        lesson: confirmed,
        followUpQuestions: result.followUpQuestions,
      ),
    );
  }

  void dismissLesson() {
    final result = state.lastResult;
    if (result == null) return;
    state = state.copyWith(
      lastResult: CaptureResult(
        event: result.event,
        lesson: null,
        followUpQuestions: result.followUpQuestions,
      ),
    );
  }

  void finish() => state = state.copyWith(clearResult: true);
}

final palaceCaptureProvider =
    StateNotifierProvider<PalaceCaptureNotifier, PalaceCaptureState>((ref) {
  return PalaceCaptureNotifier(ref);
});
