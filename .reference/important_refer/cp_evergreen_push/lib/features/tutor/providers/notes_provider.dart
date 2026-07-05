import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/config/app_config.dart';
import '../../../core/config/providers.dart';
import '../../../core/services/ocr_pipeline.dart';
import '../services/deepseek_client.dart';
import '../../classroom/providers/classroom_provider.dart';
import '../../classroom/services/classroom_crawler.dart';

/// OCR 依赖安装请求（由 UI 层消费，弹出安装确认框）。
class OcrInstallRequest {
  /// "pip" → 需要 pip install；"tesseract" → 需要安装 Tesseract 引擎
  final String action;
  final String hint;

  const OcrInstallRequest({required this.action, required this.hint});
}

/// 保存的笔记模型。
class SavedNote {
  final String id;
  final String title;
  final String content;
  final String mode;
  final DateTime createdAt;

  const SavedNote({
    required this.id,
    required this.title,
    required this.content,
    required this.mode,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'content': content,
        'mode': mode,
        'createdAt': createdAt.toIso8601String(),
      };

  factory SavedNote.fromJson(Map<String, dynamic> json) => SavedNote(
        id: json['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
        title: json['title'] as String? ?? '',
        content: json['content'] as String? ?? '',
        mode: json['mode'] as String? ?? 'summary',
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
      );

  String get preview => content.length > 120
      ? '${content.substring(0, 120)}...'
      : content;
}

/// Notes generation state.
String _progressLabel(String phase, {double value = 0}) {
  switch (phase) {
    case 'deps':
      return '安装 OCR 依赖中...';
    case 'slides':
      return '下载幻灯片中...';
    case 'subtitles':
      return '解析语音字幕...';
    case 'ocr':
      return 'OCR 识别中 ${(value * 100).round()}%...';
    case 'cleaning':
      return 'AI 清洗错别字中...';
    case 'done':
      return '处理完成';
    default:
      return phase;
  }
}

class NotesState {
  final String mode; // summary / cards
  final String inputContent;
  final String result;
  final bool isLoading;
  /// 当前进度阶段（slides / subtitles / ocr / done / ''）。
  final String progressPhase;
  /// 当前进度 0.0 ~ 1.0。
  final double progressValue;
  final String? error;

  /// OCR 依赖安装请求（非 null 时 UI 应弹出确认框）。
  final OcrInstallRequest? ocrInstallRequest;

  /// AI 清洗过程中的流式输出（实时显示在特效面板）。
  final String cleaningContent;
  /// AI 清洗是否正在进行。
  final bool isCleaning;

  /// 已保存的笔记列表（持久化）。
  final List<SavedNote> savedNotes;
  /// 当前查看的已保存笔记（非 null 时显示查看器）。
  final SavedNote? viewingNote;
  /// 正在加载保存的笔记。
  final bool isLoadingSaved;

  /// 严谨模式：低 temperature，输出更确定、更结构化。
  final bool strict;

  const NotesState({
    this.mode = 'summary',
    this.inputContent = '',
    this.result = '',
    this.isLoading = false,
    this.progressPhase = '',
    this.progressValue = 0.0,
    this.error,
    this.ocrInstallRequest,
    this.cleaningContent = '',
    this.isCleaning = false,
    this.savedNotes = const [],
    this.viewingNote,
    this.isLoadingSaved = false,
    this.strict = false,
  });

  NotesState copyWith({
    String? mode,
    String? inputContent,
    String? result,
    bool? isLoading,
    String? error,
    String? progressPhase,
    double? progressValue,
    OcrInstallRequest? ocrInstallRequest,
    bool clearOcrInstall = false,
    String? cleaningContent,
    bool? isCleaning,
    bool clearCleaning = false,
    List<SavedNote>? savedNotes,
    SavedNote? viewingNote,
    bool clearViewingNote = false,
    bool? isLoadingSaved,
    bool? strict,
  }) {
    return NotesState(
      mode: mode ?? this.mode,
      inputContent: inputContent ?? this.inputContent,
      result: result ?? this.result,
      isLoading: isLoading ?? this.isLoading,
      progressPhase: progressPhase ?? this.progressPhase,
      progressValue: progressValue ?? this.progressValue,
      error: error,
      ocrInstallRequest: clearOcrInstall ? null : (ocrInstallRequest ?? this.ocrInstallRequest),
      cleaningContent: clearCleaning ? '' : (cleaningContent ?? this.cleaningContent),
      isCleaning: isCleaning ?? this.isCleaning,
      savedNotes: savedNotes ?? this.savedNotes,
      viewingNote: clearViewingNote ? null : (viewingNote ?? this.viewingNote),
      isLoadingSaved: isLoadingSaved ?? this.isLoadingSaved,
      strict: strict ?? this.strict,
    );
  }
}

/// 简单信号量，限制并发任务数为 [maxConcurrent]。
class _ConcurrencyLimiter {
  final int maxConcurrent;
  int _running = 0;
  final List<Completer<void>> _queue = [];

  _ConcurrencyLimiter({this.maxConcurrent = 4});

  /// 等待直到可以执行下一个任务。
  Future<void> acquire() async {
    if (_running < maxConcurrent) {
      _running++;
      return;
    }
    final completer = Completer<void>();
    _queue.add(completer);
    await completer.future;
    _running++;
  }

  /// 释放一个槽位，允许下一个等待的任务执行。
  void release() {
    _running--;
    if (_queue.isNotEmpty) {
      final next = _queue.removeAt(0);
      next.complete();
    }
  }
}

class NotesNotifier extends StateNotifier<NotesState> {
  final DeepSeekClient? _client;
  final Dio _dio;
  final SharedPreferences _prefs;

  NotesNotifier({DeepSeekClient? client, required Dio dio, required SharedPreferences prefs})
      : _client = client, _dio = dio, _prefs = prefs, super(const NotesState()) {
    // 初始化时加载已保存的笔记
    loadSavedNotes();
  }

  void setMode(String mode) => state = state.copyWith(mode: mode);
  void setInput(String content) => state = state.copyWith(inputContent: content);
  void setStrict(bool value) => state = state.copyWith(strict: value);

  // ── 笔记持久化 ──────────────────────────────────────────────────

  /// 从 SharedPreferences 加载已保存的笔记列表。
  void loadSavedNotes() {
    try {
      final raw = _prefs.getStringList('saved_notes') ?? [];
      final notes = raw
          .map((s) {
            try {
              return SavedNote.fromJson(jsonDecode(s) as Map<String, dynamic>);
            } catch (_) {
              return null;
            }
          })
          .whereType<SavedNote>()
          .toList();
      state = state.copyWith(savedNotes: notes, isLoadingSaved: false);
    } catch (_) {
      state = state.copyWith(isLoadingSaved: false);
    }
  }

  /// 保存当前 AI 生成的笔记。
  Future<void> saveCurrentNote(String title) async {
    final content = state.result.trim();
    if (content.isEmpty) return;

    final note = SavedNote(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title.isNotEmpty ? title : '笔记 ${state.savedNotes.length + 1}',
      content: content,
      mode: state.mode,
      createdAt: DateTime.now(),
    );

    final newNotes = [...state.savedNotes, note];
    await _persistNotes(newNotes);
    state = state.copyWith(savedNotes: newNotes);
  }

  /// 删除指定 ID 的笔记。
  Future<void> deleteSavedNote(String id) async {
    final newNotes = state.savedNotes.where((n) => n.id != id).toList();
    await _persistNotes(newNotes);
    state = state.copyWith(
      savedNotes: newNotes,
      clearViewingNote: state.viewingNote?.id == id,
    );
  }

  /// 查看已保存的笔记。
  void viewSavedNote(SavedNote note) {
    state = state.copyWith(viewingNote: note);
  }

  /// 关闭笔记查看器。
  void closeViewer() {
    state = state.copyWith(clearViewingNote: true);
  }

  Future<void> _persistNotes(List<SavedNote> notes) async {
    try {
      final raw = notes.map((n) => jsonEncode(n.toJson())).toList();
      await _prefs.setStringList('saved_notes', raw);
    } catch (_) {
      // 持久化失败静默忽略
    }
  }

  Future<void> generate() async {
    final content = state.inputContent.trim();
    if (content.isEmpty) return;

    if (_client == null) {
      state = state.copyWith(error: '请先在设置中配置 DeepSeek API Key');
      return;
    }

    state = state.copyWith(isLoading: true, result: '', error: null, progressPhase: '');

    try {
      // 严谨模式：低 temperature + 增强 prompt
      final temperature = state.strict ? 0.3 : null;
      final prompt = state.strict ? _getStrictPrompt(state.mode) : _getPrompt(state.mode);
      final messages = [
        {'role': 'system', 'content': prompt},
        {'role': 'user', 'content': content},
      ];
      final resultBuf = StringBuffer();
      int throttleCount = 0;
      final maxTokens = state.mode == 'summary' ? 16384 : 8192;
      await for (final chunk in _client!.streamChat(messages, maxTokens: maxTokens, temperature: temperature)) {
        if (chunk.type == StreamChunkType.content && chunk.content != null) {
          resultBuf.write(chunk.content);
          throttleCount++;
          if (throttleCount >= 15 ||
              chunk.content!.contains('\n') ||
              chunk.content!.contains('。') ||
              chunk.content!.contains('.') ||
              chunk.content!.contains('！') ||
              chunk.content!.contains('？')) {
            state = state.copyWith(result: resultBuf.toString());
            throttleCount = 0;
          }
        } else if (chunk.type == StreamChunkType.error) {
          state = state.copyWith(
            error: chunk.content ?? chunk.error?.userMessage ?? 'AI 请求失败',
            isLoading: false,
            result: state.result.isEmpty ? '生成失败' : state.result,
          );
          return;
        }
      }
      state = state.copyWith(result: resultBuf.toString(), isLoading: false);
    } catch (e) {
      state = state.copyWith(
        error: e.toString(),
        isLoading: false,
        result: state.result.isEmpty ? '生成失败: $e' : state.result,
      );
    }
  }

  /// 手动 AI 清洗：在特效面板中流式显示清洗过程，完成后覆盖输入。
  Future<void> cleanInput() async {
    final raw = state.inputContent.trim();
    if (raw.isEmpty || _client == null) return;
    state = state.copyWith(isCleaning: true, cleaningContent: '');
    try {
      final cleaned = StringBuffer();
      await for (final chunk in _aiCleanStream(raw)) {
        cleaned.write(chunk);
        if (cleaned.length % 10 < chunk.length) {
          state = state.copyWith(cleaningContent: cleaned.toString());
        }
      }
      // 清洗完成：覆盖输入框
      state = state.copyWith(
        inputContent: cleaned.toString(),
        isCleaning: false,
        clearCleaning: true,
      );
    } catch (_) {
      state = state.copyWith(isCleaning: false, clearCleaning: true);
    }
  }

  /// Fetch classroom content and set as input for AI notes generation.
  ///
  /// 流程:
  ///   1. 拉取 PPT 图片 URL + 字幕（报告 slides / subtitles 进度）
  ///   2. 调用 Python OCR 脚本提取 PPT 图片中的文字（报告 ocr 进度）
  ///   3. 合并 OCR 结果 + 字幕 → 设为输入
  Future<void> fetchClassroomContent(int courseId, int subId, String title) async {
    state = state.copyWith(isLoading: true, result: '', error: null, progressPhase: 'slides');

    try {
      final crawler = ClassroomCrawler(_dio);

      // 带进度的拉取
      final contentResult = await crawler.fetchCourseContent(
        courseId, subId,
        onProgress: (progress) {
          state = state.copyWith(
            progressPhase: progress.phase,
            progressValue: progress.ratio,
          );
        },
      );
      final content = contentResult.fold((c) => c, (_) => throw Exception('拉取失败'));

      // — 构建输入内容 —
      final buf = StringBuffer();
      buf.writeln('# $title\n');

      // ① PPT OCR（4 线程并发池，批间更新进度）
      if (content.slides.isNotEmpty) {
        buf.writeln('## PPT 内容\n');
        final urls = content.slides.map((s) => s.imageUrl).toList();
        final limiter = _ConcurrencyLimiter(maxConcurrent: 4);
        final allTexts = List<String>.generate(urls.length, (_) => '');
        const batchSize = 30;

        for (var batchStart = 0; batchStart < urls.length; batchStart += batchSize) {
          final batchEnd = (batchStart + batchSize).clamp(0, urls.length);

          state = state.copyWith(
            progressPhase: 'ocr',
            progressValue: batchStart / urls.length,
          );

          // 4 线程并发池执行 OCR
          await Future.wait(
            List.generate((batchEnd - batchStart).toInt(), (i) async {
              final idx = batchStart + i;
              await limiter.acquire();
              try {
                allTexts[idx] = await _ocrOneSlide(urls[idx]);
              } finally {
                limiter.release();
              }
            }),
          );
        }

        state = state.copyWith(progressValue: 1.0);
        var hasOcrText = false;
        for (var i = 0; i < allTexts.length; i++) {
          if (allTexts[i].trim().isNotEmpty) {
            hasOcrText = true;
            buf.writeln('### 第 ${i + 1} 页\n');
            buf.writeln('${allTexts[i]}\n');
          }
        }
        if (!hasOcrText) {
          buf.writeln('> ⚠️ PPT OCR 未提取到文字\n\n');
          buf.writeln('可能的原因：\n');
          buf.writeln('1. Tesseract OCR 引擎未安装\n');
          buf.writeln('2. Python 缺少依赖，请运行: pip install -r scripts/requirements.txt\n');
          buf.writeln('---\n查看 Debug 控制台中的 [OCR] 日志获取详细错误信息。\n');
        }
      }

      // ② 语音字幕（单次 API 调用，无法报告中间进度）
      state = state.copyWith(progressPhase: 'subtitles', progressValue: 0.0);
      if (content.subtitles.isNotEmpty) {
        buf.writeln('## 语音转录\n');
        for (final s in content.subtitles) {
          final min = (s.startMs / 60000).floor();
          final sec = ((s.startMs % 60000) / 1000).floor();
          buf.writeln('[$min:${sec.toString().padLeft(2, '0')}] ${s.text}');
        }
      }

      // ③ 不再自动 AI 清洗——用户手动触发
      final rawText = buf.toString().trim();
      state = state.copyWith(inputContent: rawText);

      state = state.copyWith(
        progressPhase: 'done',
        progressValue: 1.0,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(error: e.toString(), isLoading: false);
    }
  }

  /// AI 流式清洗：修复 OCR / 语音识别的错别字、数字错误、乱码符号。
  /// 边生成边 yield，前端输入框同步显示。
  Stream<String> _aiCleanStream(String raw) async* {
    const prompt = '以下是课程的 PPT OCR 和上课语音识别结果，可能存在：'
        '- 错别字（如"热雷"应为"热爱"）'
        '- 数字错误（如"40%6"应为"40%"）'
        '- 乱码符号'
        '请基于上下文理解内容并逐字清洗，直接输出结果：';
    final messages = [
      {'role': 'system', 'content': prompt},
      {'role': 'user', 'content': raw},
    ];
    await for (final chunk in _client!.streamChat(messages, maxTokens: 65536)) {
      if (chunk.type == StreamChunkType.content && chunk.content != null) {
        yield chunk.content!;
      } else if (chunk.type == StreamChunkType.error) {
        return; // Error during cleaning — caller will use raw text
      }
    }
  }

  /// 清除 OCR 安装请求（用户关闭弹窗时调用）。
  void dismissOcrInstall() {
    state = state.copyWith(clearOcrInstall: true);
  }

  // ── OCR 纠错词典 ──────────────────────────────────────────────
  /// 常见 OCR 识别错误映射表（`_fixOcrText` 使用）。
  static const _ocrFixMap = {
    '井': '并',
    '从': '从',
    'r1': 'n',
    '丨': '|',
    '0': 'O',
    '亻': '人',
    '兖': '充',
    '劦': '协',
    '吋': '时',
    '嘤': '婴',
    '埒': '时',
    '娼': '始',
    '嬖': '壁',
    '孑': '子',
    '屮': '中',
    '岷': '民',
    '巛': '川',
    '彐': '三',
    '忄': '心',
    '戋': '浅',
    '扌': '手',
    '攵': '文',
    '昜': '易',
    '曱': '由',
    '甴': '由',
    '秌': '秋',
    '竜': '龙',
    '筚': '笔',
    '簋': '鬼',
    '綮': '启',
    '罒': '四',
    '耂': '老',
    '肙': '肖',
    '芈': '半',
    '茻': '共',
    '蓺': '艺',
    '蕓': '芸',
    '蚩': '虫',
    '螅': '息',
    '衤': '衣',
    '覀': '西',
    '讠': '言',
    '豕': '家',
    '贝攵': '败',
    '赉': '来',
    '軎': '再',
    '辶': '走',
    '钅': '金',
    '闩': '门',
    '阝': '耳',
    '雫': '霞',
    '靑': '青',
    '页立': '部',
    '饣': '食',
    '马彳': '行',
    '鱼': '鱼',
    '龵': '手',
  };

  /// 应用 OCR 纠错映射表到文本。
  String _fixOcrText(String text) {
    for (final entry in _ocrFixMap.entries) {
      text = text.replaceAll(entry.key, entry.value);
    }
    return text;
  }

  /// 对单张 PPT 图片运行 OCR，返回提取的文字。
  ///
  /// 优先使用 DeepSeek-OCR（Level 1），失败降级到本地 Tesseract / ML Kit（Level 2）。
  Future<String> _ocrOneSlide(String imageUrl) async {
    try {
      final text = await OcrPipeline(_dio).recognizeUrl(imageUrl);
      if (text.isNotEmpty) return _fixOcrText(text);
    } catch (e) {
      debugPrint('[OCR] Pipeline 异常: $e');
    }

    // Pipeline 返回空（所有 Level 均失败）
    return '';
  }

  String _getPrompt(String mode) {
    // 提示语在 notes_screen.dart 中由用户直接选择，这里只做兜底
    switch (mode) {
      case 'summary':
        return '你是一位顶尖学霸，请将以下课堂内容按康奈尔笔记法整理。\n\n'
            '格式要求：\n'
            '---\n'
            '# 课程标题\n\n'
            '---\n\n'
            '## 📝 康奈尔笔记\n\n'
            '<table>\n'
            '<tr><td style="width:25%"><b>核心概念</b></td><td style="width:75%">详细解释</td></tr>\n'
            '<tr><td style="width:25%"><b>关键公式</b></td><td style="width:75%">公式 + 说明</td></tr>\n'
            '<tr><td style="width:25%"><b>易错点</b></td><td style="width:75%">常见错误</td></tr>\n'
            '</table>\n\n'
            '---\n\n'
            '## 📌 课堂总结\n'
            '用 2-3 句话总结本节课的核心。\n\n'
            '---\n\n'
            '## 🧠 知识结构图\n'
            '用树状图梳理本节课的知识体系，例如：\n'
            '```\n'
            '主题\n'
            '├─ 知识点 1\n'
            '│  ├─ 子概念 A\n'
            '│  └─ 子概念 B\n'
            '├─ 知识点 2\n'
            '└─ 知识点 3\n'
            '```\n\n'
            '注意：\n'
            '- 康奈尔笔记的线索区（窄）和笔记区（宽）用 HTML `<table>` 实现\n'
            '- 用 --- 横线分隔不同区块\n'
            '- 重点内容用 **加粗** 标注（但在 HTML `<table>` 内用 `<b>` 标签，不要用 `**`）\n'
            '- 思维导图用 markdown fenced code block 包裹，语言标记为 mindmap，如：\n'
            '```mindmap\n'
            '中心主题\n'
            '  分支1\n'
            '    子分支A\n'
            '    子分支B\n'
            '  分支2\n'
            '```\n'
            '- 复杂流程图/时序图等可使用 mermaid 语法，语言标记为 mermaid，如：\n'
            '```mermaid\n'
            'graph TD\n'
            '  A[开始] --> B{判断}\n'
            '  B -->|是| C[处理]\n'
            '  B -->|否| D[结束]\n'
            '```';
      case 'cards':
        return '你是一个知识卡片生成助手。请将以下内容转化为问答卡片集。\n\n'
            '格式要求（重要）：\n'
            '每张卡片用 `---` 分隔。每张卡片格式如下：\n'
            '```\n'
            '## ❓ 问题\n'
            '问题内容\n'
            '\n'
            '## 💡 答案\n'
            '答案内容\n'
            '```\n'
            '要求：\n'
            '- 每张卡片一问一答，独立完整\n'
            '- 卡片数量覆盖本节课全部知识点\n'
            '- 问题简洁明了，答案准确全面\n'
            '- 概念用 **加粗** 标注\n'
            '- 代码/公式用 `行内代码` 包裹\n'
            '- 用 `---` 分隔不同的卡片\n'
            '输出示例：\n'
            '---\n'
            '## ❓ 什么是康奈尔笔记法？\n'
            '\n'
            '## 💡 答案\n'
            '康奈尔笔记法是一种将页面分为**线索区**、**笔记区**和**总结区**的笔记方法。\n'
            '\n'
            '---\n'
            '## ❓ 知识卡片的格式要求？\n'
            '\n'
            '## 💡 答案\n'
            '每张卡片用 `---` 分隔，包含 `问题` 和 `答案` 两个部分。';
      default:
        return '请总结以下内容。';
    }
  }

  /// 严谨模式 prompt：temperature=0.3 + 更严格的格式约束。
  String _getStrictPrompt(String mode) {
    final base = _getPrompt(mode);
    return '$base\n\n'
        '【严谨模式】请严格遵守以下规则：\n'
        '1. 必须使用指定的 markdown 格式，不要遗漏任何区块\n'
        '2. 表格必须完整，每行单元格数量一致\n'
        '3. 代码块必须标明语言（mindmap / mermaid / python / c / dart 等）\n'
        '4. 不要输出无关的说明文字，直接输出笔记内容\n'
        '5. 每个知识点必须有具体例子或解释，不要空洞概括\n'
        r'6. 数学公式用 `$$` 包裹，行内公式用 `$` 包裹' + '\n'
        '7. 不要使用 HTML 标签，全部用 markdown 语法\n'
        '8. 内容必须完整覆盖用户提供的全部课堂材料';
  }
}

/// Provider for AI notes generation.
final notesProvider =
    StateNotifierProvider<NotesNotifier, NotesState>((ref) {
  final dio = ref.read(dioClientProvider);
  final prefs = ref.read(sharedPreferencesProvider);
  DeepSeekClient? client;
  try {
    if (AppConfig.hasDeepSeekApiKey) {
      client = DeepSeekClient(dio);
    }
  } catch (_) {
    // DeepSeek API key not configured — client remains null
  }
  return NotesNotifier(client: client, dio: dio, prefs: prefs);
});
