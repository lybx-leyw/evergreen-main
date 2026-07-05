import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import '../../../core/config/app_config.dart';
import '../../../core/log.dart';
import '../../../core/result.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/utils/file_utils.dart';
import '../../tutor/providers/notes_provider.dart';
import '../models/course_content.dart';
import '../providers/classroom_provider.dart';
import '../services/classroom_crawler.dart';
import '../widgets/ppt_viewer.dart';
import '../widgets/subtitle_timeline.dart';
import '../widgets/video_player_panel.dart';

/// Full-screen viewer for 智云课堂 course content.
///
/// Three responsive layouts:
///   Desktop (≥1024px) — left: PPT thumbnail, right: subtitle timeline
///   Tablet  (600-1024) — top: PPT, bottom: subtitles
///   Mobile  (<600px)   — TabBar switching between PPT / subtitles
class ClassroomViewerScreen extends ConsumerStatefulWidget {
  final int courseId;
  final int subId;
  final String title;

  const ClassroomViewerScreen({
    super.key,
    required this.courseId,
    required this.subId,
    required this.title,
  });

  @override
  ConsumerState<ClassroomViewerScreen> createState() =>
      _ClassroomViewerScreenState();
}

class _ClassroomViewerScreenState
    extends ConsumerState<ClassroomViewerScreen> {
  late final Dio _dio;

  @override
  void initState() {
    super.initState();
    _dio = ref.read(dioClientProvider);
  }

  /// Download PPT image bytes（二进制图片，不适合 JSON 缓存）。
  Future<Uint8List?> _loadPptImage(String url) async {
    try {
      final response = await _dio.get<Uint8List>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: true,
          headers: {
            'Referer': 'https://classroom.zju.edu.cn/',
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          },
        ),
      );
      return response.data;
    } catch (e) {
      Log().debug('ClassroomViewer: PPT image load failed', data: {'url': url});
      return null;
    }
  }

  /// Navigate to AI Notes.
  void _goToAiNotes(CourseContent content) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try { Navigator.of(context).pop(); } catch (_) {}
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        try { GoRouter.of(context).go('/notes'); } catch (_) {}
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ref.read(notesProvider.notifier).fetchClassroomContent(
            widget.courseId, widget.subId,
            content.slides.firstOrNull?.imageUrl ?? '录播视频',
          );
        });
      });
    });
  }

  /// Download all PPT slides to local disk.
  Future<void> _downloadAllSlides(CourseContent content) async {
    if (content.slides.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前视频没有 PPT 幻灯片')),
      );
      return;
    }

    // ── Build destination directory ──────────────────────────────────
    final baseDir = AppConfig.getDownloadDirectory();
    // Sanitize title for filesystem use
    final sanitizedTitle = widget.title
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final destDir = p.join(baseDir, '智云课堂PPT', sanitizedTitle);

    // ── Show progress dialog ─────────────────────────────────────────
    final progressState = _DownloadProgressState(total: content.slides.length);
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _DownloadProgressDialog(state: progressState),
    );

    // ── Execute download ─────────────────────────────────────────────
    final crawler = ref.read(classroomCrawlerProvider);
    final result = await crawler.downloadSlides(
      content.slides,
      destDir,
      onProgress: (completed, total) {
        progressState.completed = completed;
        progressState.notifyListeners();
      },
    );

    // ── Handle result ────────────────────────────────────────────────
    if (!mounted) return;
    Navigator.of(context).pop(); // dismiss progress dialog

    result.fold(
      (savedPaths) {
        final count = savedPaths.length;
        final total = content.slides.length;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已保存 $count / $total 页 PPT'),
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: '打开文件夹',
              onPressed: () => openInFileManager(destDir),
            ),
          ),
        );
      },
      (error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('下载失败: ${error.userMessage}')),
        );
      },
    );
  }

  /// Download current PPT page to disk.
  Future<void> _downloadCurrentSlide(CourseContent content, int pageIndex) async {
    if (content.slides.isEmpty || pageIndex < 0 || pageIndex >= content.slides.length) return;

    final slide = content.slides[pageIndex];
    final baseDir = AppConfig.getDownloadDirectory();
    final sanitizedTitle = widget.title
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final destDir = p.join(baseDir, '智云课堂PPT', sanitizedTitle);

    try {
      final dir = Directory(destDir);
      if (!await dir.exists()) await dir.create(recursive: true);

      final uri = Uri.tryParse(slide.imageUrl);
      final ext = uri != null && uri.path.contains('.')
          ? '.${uri.path.split('.').last}'
          : '.png';
      final filePath = p.join(destDir, 'page_${slide.page}$ext');

      final response = await _dio.get<List<int>>(
        slide.imageUrl,
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: true,
          headers: {
            'Referer': 'https://classroom.zju.edu.cn/',
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          },
        ),
      );

      final file = File(filePath);
      await file.writeAsBytes(response.data!);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已保存第 ${slide.page} 页'),
          duration: const Duration(seconds: 2),
          action: SnackBarAction(
            label: '打开文件夹',
            onPressed: () => openInFileManager(destDir),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final contentAsync = ref.watch(courseContentProvider((courseId: widget.courseId, subId: widget.subId)));
    final videosAsync = ref.watch(classroomVideosProvider(widget.courseId));

    final videoUrl = videosAsync.whenOrNull(
      data: (result) => result.fold(
        (videos) => videos.where((v) => v.subId == widget.subId).firstOrNull?.videoUrl,
        (_) => null,
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(fontSize: 16), overflow: TextOverflow.ellipsis),
        actions: [
          if (contentAsync.hasValue && contentAsync.value!.isOk)
            IconButton(
              icon: const Icon(Icons.auto_awesome),
              tooltip: '生成 AI 笔记',
              onPressed: () => _goToAiNotes(contentAsync.value!.fold((c) => c, (_) => throw '')),
            ),
          if (contentAsync.hasValue && contentAsync.value!.isOk)
            IconButton(
              icon: const Icon(Icons.download),
              tooltip: '下载全部 PPT',
              onPressed: () => _downloadAllSlides(contentAsync.value!.fold((c) => c, (_) => throw '')),
            ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
        bottom: contentAsync.isLoading
            ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator())
            : null,
      ),
      body: contentAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text('加载失败', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(err.toString(), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => ref.invalidate(courseContentProvider((courseId: widget.courseId, subId: widget.subId))),
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ]),
          ),
        ),
        data: (result) => result.fold(
          (content) => LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 1024) {
                return _DesktopLayout(
                  content: content,
                  imageLoader: _loadPptImage,
                  videoUrl: videoUrl,
                  onDownloadAll: () => _downloadAllSlides(content),
                  onDownloadCurrent: (page) => _downloadCurrentSlide(content, page),
                );
              } else if (constraints.maxWidth >= 600) {
                return _TabletLayout(
                  content: content,
                  imageLoader: _loadPptImage,
                  videoUrl: videoUrl,
                  onDownloadAll: () => _downloadAllSlides(content),
                  onDownloadCurrent: (page) => _downloadCurrentSlide(content, page),
                );
              } else {
                return _MobileLayout(
                  content: content,
                  imageLoader: _loadPptImage,
                  videoUrl: videoUrl,
                  onDownloadAll: () => _downloadAllSlides(content),
                  onDownloadCurrent: (page) => _downloadCurrentSlide(content, page),
                );
              }
            },
          ),
          (error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                Text(error.userMessage, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => ref.invalidate(courseContentProvider((courseId: widget.courseId, subId: widget.subId))),
                  icon: const Icon(Icons.refresh),
                  label: const Text('重试'),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Responsive layouts ───────────────────────────────────────────

class _DesktopLayout extends StatefulWidget {
  final CourseContent content;
  final ImageLoader imageLoader;
  final String? videoUrl;
  final VoidCallback? onDownloadAll;
  final ValueChanged<int>? onDownloadCurrent;
  const _DesktopLayout({
    required this.content,
    required this.imageLoader,
    this.videoUrl,
    this.onDownloadAll,
    this.onDownloadCurrent,
  });

  @override
  State<_DesktopLayout> createState() => _DesktopLayoutState();
}

class _DesktopLayoutState extends State<_DesktopLayout> {
  int _pptPage = 0;

  void _scrollSubtitleToPptPage(int pptPage) {
    // TODO: Step 5 — sync subtitle highlight with PPT page
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (widget.videoUrl != null)
          VideoPlayerPanel(
            videoUrl: widget.videoUrl!,
            title: widget.content.slides.isNotEmpty ? '录播视频' : '',
          ),
        Expanded(
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: PptViewer(
                  slides: widget.content.slides,
                  initialPage: _pptPage,
                  imageLoader: widget.imageLoader,
                  onPageChanged: (p) => setState(() {
                    _pptPage = p;
                    _scrollSubtitleToPptPage(p);
                  }),
                  onDownloadAll: widget.onDownloadAll,
                  onDownloadCurrent: widget.onDownloadCurrent != null
                      ? () => widget.onDownloadCurrent!(_pptPage)
                      : null,
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                flex: 2,
                child: SubtitleTimeline(
                  subtitles: widget.content.subtitles,
                  onTap: (i) {
                    // TODO: Step 5 — jump to PPT page near this subtitle
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TabletLayout extends StatefulWidget {
  final CourseContent content;
  final ImageLoader imageLoader;
  final String? videoUrl;
  final VoidCallback? onDownloadAll;
  final ValueChanged<int>? onDownloadCurrent;
  const _TabletLayout({
    required this.content,
    required this.imageLoader,
    this.videoUrl,
    this.onDownloadAll,
    this.onDownloadCurrent,
  });

  @override
  State<_TabletLayout> createState() => _TabletLayoutState();
}

class _TabletLayoutState extends State<_TabletLayout> {
  int _pptPage = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (widget.videoUrl != null)
          VideoPlayerPanel(
            videoUrl: widget.videoUrl!,
            title: '',
          ),
        Expanded(
          child: PptViewer(
            slides: widget.content.slides,
            initialPage: _pptPage,
            imageLoader: widget.imageLoader,
            onPageChanged: (p) => setState(() => _pptPage = p),
            onDownloadAll: widget.onDownloadAll,
            onDownloadCurrent: widget.onDownloadCurrent != null
                ? () => widget.onDownloadCurrent!(_pptPage)
                : null,
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: SubtitleTimeline(subtitles: widget.content.subtitles),
        ),
      ],
    );
  }
}

class _MobileLayout extends StatefulWidget {
  final CourseContent content;
  final ImageLoader imageLoader;
  final String? videoUrl;
  final VoidCallback? onDownloadAll;
  final ValueChanged<int>? onDownloadCurrent;
  const _MobileLayout({
    required this.content,
    required this.imageLoader,
    this.videoUrl,
    this.onDownloadAll,
    this.onDownloadCurrent,
  });

  @override
  State<_MobileLayout> createState() => _MobileLayoutState();
}

class _MobileLayoutState extends State<_MobileLayout>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (widget.videoUrl != null)
          VideoPlayerPanel(
            videoUrl: widget.videoUrl!,
            title: '',
          ),
        TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'PPT (${widget.content.slides.length})'),
            Tab(text: '字幕 (${widget.content.subtitles.length})'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              PptViewer(
                slides: widget.content.slides,
                imageLoader: widget.imageLoader,
                onDownloadAll: widget.onDownloadAll,
              ),
              SubtitleTimeline(subtitles: widget.content.subtitles),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Download progress dialog ───────────────────────────────────────

class _DownloadProgressState extends ChangeNotifier {
  final int total;
  int completed = 0;

  _DownloadProgressState({required this.total});

  double get progress => total > 0 ? completed / total : 0.0;
}

class _DownloadProgressDialog extends StatelessWidget {
  final _DownloadProgressState state;
  const _DownloadProgressDialog({required this.state});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        return AlertDialog(
          title: Text('下载中 — ${state.completed} / ${state.total}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: state.progress),
              const SizedBox(height: 16),
              Text('正在下载 PPT 页面，请稍候...',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        );
      },
    );
  }
}
