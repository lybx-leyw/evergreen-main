import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/result.dart';
import '../../../core/config/app_config.dart';
import '../../../core/utils/file_utils.dart';
import '../providers/notes_provider.dart';
import '../../../features/classroom/providers/classroom_provider.dart';
import '../../../features/classroom/services/classroom_crawler.dart';
import '../../../widgets/error_card.dart';
import '../../../widgets/markdown_renderer.dart';
import '../../../widgets/flashcard_view.dart';
import '../../../widgets/toast.dart';

/// AI Notes screen — Keshav 3-pass + SQ3R + lecture summary.
///
/// Uses Riverpod NotesNotifier for state management.
class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key});
  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen> {
  final _inputController = TextEditingController();
  void Function(FlutterErrorDetails)? _prevErrorHandler;
  bool _markdownFailed = false;
  bool _markdownErrorHandled = false;
  bool _showAsFlashcards = false;

  @override
  void initState() {
    super.initState();
    _prevErrorHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      final msg = details.exceptionAsString();
      if (!_markdownErrorHandled &&
          msg.contains('_inlines.isEmpty') && msg.contains('flutter_markdown')) {
        _markdownErrorHandled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _markdownFailed = true);
        });
        return;
      }
      _prevErrorHandler?.call(details);
    };
  }

  @override
  void dispose() {
    FlutterError.onError = _prevErrorHandler;
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notesState = ref.watch(notesProvider);

    // 监听 OCR 安装请求
    ref.listen<NotesState>(notesProvider, (prev, next) {
      final req = next.ocrInstallRequest;
      if (req == null || req == prev?.ocrInstallRequest) return;
      _showOcrInstallDialog(req);
    });

    // Sync controller with provider state (provider is source of truth)
    if (_inputController.text != notesState.inputContent) {
      _inputController.text = notesState.inputContent;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 笔记'),
        actions: [
          // 导出笔记为文件
          if (notesState.result.isNotEmpty && !notesState.isLoading)
            IconButton(
              icon: const Icon(Icons.file_download),
              tooltip: '导出笔记',
              onPressed: () => _exportNote(),
            ),
          // 保存当前笔记
          if (notesState.result.isNotEmpty && !notesState.isLoading)
            IconButton(
              icon: const Icon(Icons.save),
              tooltip: '保存笔记',
              onPressed: () => _showSaveDialog(),
            ),
          // 查看已保存笔记列表
          if (notesState.savedNotes.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.bookmark),
              tooltip: '已保存笔记 (${notesState.savedNotes.length})',
              onPressed: () => _showSavedNotes(),
            ),
          // 切换闪卡模式（仅快闪卡片模式可用）
          if (notesState.mode == 'cards' && notesState.result.isNotEmpty)
            IconButton(
              icon: Icon(_showAsFlashcards ? Icons.article : Icons.style),
              tooltip: _showAsFlashcards ? '卡片视图' : '闪卡翻面模式',
              onPressed: () {
                final cards = parseFlashcards(notesState.result);
                if (cards.length >= 2) {
                  setState(() => _showAsFlashcards = !_showAsFlashcards);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('未识别到卡片结构，无法切换')),
                  );
                }
              },
            ),
          IconButton(
            icon: const Icon(Icons.video_library),
            tooltip: '从智云课堂选择',
            onPressed: _pickClassroomVideo,
          ),
        ],
      ),
      body: Column(
        children: [
          // Mode selector (隐藏当查看已保存笔记时)
          if (notesState.viewingNote == null)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  _modeChip('学霸笔记', 'summary', notesState.mode),
                  _modeChip('快闪卡片', 'cards', notesState.mode),
                  const SizedBox(width: 12),
                  FilterChip(
                    label: const Text('严谨', style: TextStyle(fontSize: 12)),
                    selected: notesState.strict,
                    onSelected: (v) => ref.read(notesProvider.notifier).setStrict(v),
                    visualDensity: VisualDensity.compact,
                    selectedColor: Theme.of(context).colorScheme.primaryContainer,
                    checkmarkColor: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
            ),
          // Input area (隐藏当查看已保存笔记时)
          if (notesState.viewingNote == null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        hintText: '粘贴文本内容，或点右上角从智云课堂选择视频...',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) =>
                          ref.read(notesProvider.notifier).setInput(v),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.auto_fix_high),
                    onPressed: notesState.inputContent.isEmpty || notesState.isLoading
                        ? null
                        : () => ref.read(notesProvider.notifier).cleanInput(),
                    tooltip: 'AI 清洗',
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: notesState.isLoading
                        ? null
                        : () => ref.read(notesProvider.notifier).generate(),
                    tooltip: '生成',
                  ),
                ],
              ),
            ),
          // AI 清洗特效面板 / Result area / Saved note viewer
          Expanded(
            child: notesState.viewingNote != null
                ? _buildSavedNoteViewer(notesState.viewingNote!)
                : notesState.isCleaning
                    ? _buildCleaningPanel(notesState)
                    : notesState.isLoading && notesState.result.isEmpty
                        ? _buildProgress(notesState)
                        : notesState.error != null && notesState.result.isEmpty
                            ? ErrorCard(
                                message: '生成失败',
                                detail: notesState.error,
                                onRetry: () => ref.read(notesProvider.notifier).generate(),
                              )
                            : notesState.result.isEmpty
                                ? const Center(
                                    child: Text('输入内容并选择模式开始',
                                        style: TextStyle(color: Colors.grey)))
                                : notesState.mode == 'cards' && _showAsFlashcards
                                    ? _buildFlashcardView(notesState.result)
                                    : _buildResult(notesState.result),
          ),
        ],
      ),
    );
  }

  /// 渲染 AI 结果，默认使用 MarkdownRenderer。
  Widget _buildResult(String text) {
    return MarkdownRenderer(
      text: text,
      markdownFailed: _markdownFailed,
      useCard: false,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
    );
  }

  /// 渲染为交互式闪卡视图。
  Widget _buildFlashcardView(String text) {
    final cards = parseFlashcards(text);
    if (cards.length < 2) {
      return const Center(child: Text('卡片数量不足'));
    }
    return FlashcardView(cards: cards);
  }

  /// AI 清洗特效面板——流式输出，自动滚到底部。
  Widget _buildCleaningPanel(NotesState state) {
    final controller = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (controller.hasClients) {
        controller.jumpTo(controller.position.maxScrollExtent);
      }
    });
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8), topRight: Radius.circular(8)),
            ),
            child: Row(children: [
              const SizedBox(
                width: 12, height: 12,
                child: CircularProgressIndicator(strokeWidth: 1.5),
              ),
              const SizedBox(width: 8),
              Text('AI 清洗中...', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            ]),
          ),
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.all(12),
              children: state.cleaningContent.isEmpty
                  ? [const Text('正在连接 AI...', style: TextStyle(color: Colors.grey, fontSize: 12))]
                  : state.cleaningContent.split('\n').map((line) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(line, style: const TextStyle(fontSize: 12, height: 1.5)),
                    )).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgress(NotesState state) {
    final label = state.progressPhase == 'deps'
        ? '安装 OCR 依赖中...'
        : state.progressPhase == 'ocr'
            ? 'OCR 识别中 ${(state.progressValue * 100).round()}%...'
            : state.progressPhase == 'slides'
                ? '下载幻灯片中...'
                : state.progressPhase == 'subtitles'
                    ? '解析语音字幕...'
                    : state.progressPhase == 'cleaning'
                        ? 'AI 清洗错别字中...'
                        : state.progressPhase == 'done'
                            ? '处理完成'
                            : '加载中...';

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(label, style: const TextStyle(fontSize: 14)),
            if (state.progressPhase == 'cleaning') ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ] else if (state.progressValue > 0 && state.progressValue < 1) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: state.progressValue),
            ],
          ],
        ),
      ),
    );
  }

  Widget _modeChip(String label, String mode, String current) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: current == mode,
        onSelected: (_) => ref.read(notesProvider.notifier).setMode(mode),
      ),
    );
  }

  void _showOcrInstallDialog(OcrInstallRequest req) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('安装 Tesseract OCR 引擎'),
        content: const Text(
          'PPT 文字识别需要 Tesseract OCR 引擎。\n\n'
          '请下载并安装:\n'
          '1. 打开 https://github.com/UB-Mannheim/tesseract/wiki\n'
          '2. 下载 tesseract-ocr-w64-setup-5.x.x.exe\n'
          '3. 安装时勾选 "Chinese Simplified" 语言包\n\n'
          '安装后重启应用即可。',
        ),
        actions: [
          TextButton(
            onPressed: () {
              ref.read(notesProvider.notifier).dismissOcrInstall();
              Navigator.of(ctx, rootNavigator: true).pop();
            },
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () {
              ref.read(notesProvider.notifier).dismissOcrInstall();
              Navigator.of(ctx, rootNavigator: true).pop();
            },
            child: const Text('打开下载页'),
          ),
        ],
      ),
    );
  }

  void _pickClassroomVideo() {
    final coursesAsync = ref.read(classroomCoursesProvider);
    coursesAsync.whenData((result) {
      result.fold((courses) {
        if (!context.mounted) return;
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('选择课程'),
            content: SizedBox(
              width: 300,
              height: 400,
              child: ListView.builder(
                itemCount: courses.length,
                itemBuilder: (_, i) => ListTile(
                  title: Text(courses[i].title),
                  onTap: () {
                    Navigator.of(context, rootNavigator: true).pop();
                    _pickVideo(courses[i].id);
                  },
                ),
              ),
            ),
          ),
        );
      }, (_) => null); // Error — silently skip
    });
  }

  void _pickVideo(int courseId) {
    final videosAsync = ref.read(classroomVideosProvider(courseId));
    videosAsync.whenData((result) {
      result.fold((videos) {
        if (!context.mounted) return;
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('选择视频'),
            content: SizedBox(
              width: 300,
              height: 400,
              child: ListView.builder(
                itemCount: videos.length,
                itemBuilder: (_, i) => ListTile(
                  title: Text(videos[i].title),
                  onTap: () {
                    Navigator.of(context, rootNavigator: true).pop();
                    ref.read(notesProvider.notifier).fetchClassroomContent(
                          courseId,
                          videos[i].subId,
                          videos[i].title,
                        );
                  },
                ),
              ),
            ),
          ),
        );
      }, (_) => null); // Error — silently skip
    });
  }

  /// 导出笔记为 Markdown 文件到下载目录。
  Future<void> _exportNote() async {
    final content = ref.read(notesProvider).result;
    if (content.isEmpty) return;

    final dlDir = AppConfig.downloadPath;
    if (dlDir == null || dlDir.isEmpty) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('未配置下载目录'),
          content: const Text('请先在设置中配置下载路径，之后笔记将导出到该目录。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return;
    }

    try {
      final dir = Directory(dlDir);
      if (!await dir.exists()) await dir.create(recursive: true);
      final ts = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .substring(0, 19);
      final filePath = '$dlDir${Platform.pathSeparator}笔记_$ts.md';
      await File(filePath).writeAsString(content);
      if (!mounted) return;
      Toast.success(context, '笔记已导出');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('笔记已导出到下载目录'),
          action: SnackBarAction(
            label: '打开文件夹',
            onPressed: () => openInFileManager(filePath),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Toast.error(context, '导出失败', detail: e.toString());
    }
  }

  /// 弹窗输入笔记标题并保存。
  void _showSaveDialog() {
    final controller = TextEditingController(text: '笔记 ${ref.read(notesProvider).savedNotes.length + 1}');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('保存笔记'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '笔记标题',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              ref.read(notesProvider.notifier).saveCurrentNote(controller.text.trim());
              Navigator.of(ctx, rootNavigator: true).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('笔记已保存'), duration: Duration(seconds: 2)),
              );
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  /// 显示已保存的笔记列表。
  void _showSavedNotes() {
    final saved = ref.read(notesProvider).savedNotes;
    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        expand: false,
        builder: (_, scrollController) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('已保存笔记', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('关闭'),
                  ),
                ],
              ),
              const Divider(),
              if (saved.isEmpty)
                const Expanded(
                  child: Center(child: Text('暂无已保存的笔记', style: TextStyle(color: Colors.grey))),
                )
              else
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: saved.length,
                    itemBuilder: (_, i) {
                      final note = saved[saved.length - 1 - i]; // 最新的在前
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text(note.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                note.preview,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${note.mode == 'summary' ? '学霸笔记' : '快闪卡片'} · ${note.createdAt.toString().substring(0, 10)}',
                                style: const TextStyle(fontSize: 11, color: Colors.grey),
                              ),
                            ],
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20),
                            onPressed: () {
                              ref.read(notesProvider.notifier).deleteSavedNote(note.id);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('笔记已删除'), duration: Duration(seconds: 2)),
                              );
                            },
                          ),
                          onTap: () {
                            Navigator.of(ctx).pop();
                            ref.read(notesProvider.notifier).viewSavedNote(note);
                          },
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 已保存笔记的查看器。
  Widget _buildSavedNoteViewer(SavedNote note) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(note.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    Text(
                      '${note.mode == 'summary' ? '学霸笔记' : '快闪卡片'} · ${note.createdAt.toString().substring(0, 16)}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  ref.read(notesProvider.notifier).closeViewer();
                  ref.read(notesProvider.notifier).setInput(note.content);
                },
                icon: const Icon(Icons.edit, size: 16),
                label: const Text('编辑'),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => ref.read(notesProvider.notifier).closeViewer(),
              ),
            ],
          ),
        ),
        Expanded(child: _buildResult(note.content)),
      ],
    );
  }
}
