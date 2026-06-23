/// Palace 快速捕捉服务 —— 捕捉管线的编排核心。
///
/// 执行流程：
///   ① 创建 ConsciousnessEvent（rawContent 已填，aiSummary=null）
///   ② 调 DeepSeekProvider → 生成 aiSummary → 回填到 event
///   ③ 调 AutoTagger → 生成标签建议（如果用户未手动打标签）
///   ④ 调 LessonExtractor → 生成 StructuredLesson 草稿
///   ⑤ 调 QuestionGenerator → 生成 3 个追问
///   ⑥ event 完整落盘 + lesson 草稿落盘
///
/// 所有步骤同步执行（用户等待加载动画）。
library;

import '../../agent/message.dart';
import '../../agent/provider.dart' show Provider, ProviderEventKind;
import '../models/consciousness_event.dart';
import '../models/context_snapshot.dart';
import '../models/structured_lesson.dart';
import '../refinery/auto_tagger.dart';
import '../refinery/lesson_extractor.dart';
import '../refinery/question_generator.dart';
import '../storage/event_store.dart';

/// 一次捕捉的完整结果。
class CaptureResult {
  /// 已落盘的完整事件。
  final ConsciousnessEvent event;

  /// AI 提取的教训草稿（可能为 null——AI 认为无法提炼）。
  final StructuredLesson? lesson;

  /// AI 生成的 3 个追问。
  final List<String> followUpQuestions;

  const CaptureResult({
    required this.event,
    this.lesson,
    this.followUpQuestions = const [],
  });
}

/// 快速捕捉服务——编排整个写入 → AI 补全 → 追问管线。
class QuickCaptureService {
  final EventStore _store;
  final LessonExtractor _lessonExtractor;
  final QuestionGenerator _questionGenerator;
  final AutoTagger _autoTagger;
  final Provider _llm;

  QuickCaptureService({
    required EventStore store,
    required LessonExtractor lessonExtractor,
    required QuestionGenerator questionGenerator,
    required AutoTagger autoTagger,
    required Provider llm,
  })  : _store = store,
        _lessonExtractor = lessonExtractor,
        _questionGenerator = questionGenerator,
        _autoTagger = autoTagger,
        _llm = llm;

  /// 执行完整的捕捉流程。
  ///
  /// [onProgress] 在每阶段开始时回调，用于 UI 更新加载文案。
  Future<CaptureResult> capture({
    required String rawContent,
    required EventType type,
    required SourceTool source,
    double? emotionalValence,
    List<String> tags = const [],
    ContextSnapshot? context,
    void Function(String stage)? onProgress,
  }) async {
    // ① 创建初步事件
    var event = ConsciousnessEvent.create(
      type: type,
      source: source,
      rawContent: rawContent,
      tagIds: tags,
      context: context,
      emotionalValence: emotionalValence,
    );

    // ② AI 摘要
    onProgress?.call('正在生成摘要...');
    final summary = await _generateSummary(rawContent);
    event = event.copyWith(aiSummary: summary);

    // ③ 自动标签（仅当用户未手动打标签时）
    if (tags.isEmpty) {
      final suggested = await _autoTagger.suggest(rawContent);
      if (suggested.isNotEmpty) {
        event = event.copyWith(tagIds: suggested);
      }
    }

    // ④ 保存事件（不等待教训）
    await _store.save(event);

    // ⑤ 提取教训
    onProgress?.call('正在提取教训...');
    StructuredLesson? lesson;
    try {
      lesson = await _lessonExtractor.extract(event);
    } catch (_) {
      // 教训提取失败不阻塞事件写入
    }

    // ⑥ 生成追问
    onProgress?.call('正在生成追问...');
    List<String> questions = [];
    if (lesson != null) {
      try {
        questions = await _questionGenerator.generate(lesson);
      } catch (_) {
        // 追问生成失败不阻塞
      }
    }

    return CaptureResult(
      event: event,
      lesson: lesson,
      followUpQuestions: questions,
    );
  }

  /// 使用 LLM 生成事件摘要。
  Future<String> _generateSummary(String rawContent) async {
    final prompt = '请用一句话摘要（不超过 100 字）概括以下内容的'
        '核心洞察或关键信息。只输出摘要，不要引号和其他文字。\n\n$rawContent';

    final buf = StringBuffer();
    try {
      await for (final event in _llm.chat(
        messages: [
          Message.system('你是摘要专家。用一句话概括用户输入的核心内容。'),
          Message.user(prompt),
        ],
      )) {
        if (event.kind == ProviderEventKind.content && event.text != null) {
          buf.write(event.text);
        }
      }
    } catch (_) {
      return '';
    }
    return buf.toString().trim();
  }
}
