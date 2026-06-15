import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/dio_client.dart';
import '../../tutor/providers/notes_provider.dart';
import '../services/classroom_crawler.dart';
import '../providers/classroom_provider.dart';
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
  CourseContent? _content;
  String? _videoUrl;
  String? _error;
  Dio? _sharedDio;

  @override
  void initState() {
    super.initState();
    // Pre-resolve shared Dio for image loading (Step 5)
    try {
      _sharedDio = ref.read(dioClientProvider);
    } catch (_) {
      _sharedDio = null;
    }
    _loadContent();
  }

  /// Download PPT image bytes via shared Dio (with session cookies).
  Future<Uint8List?> _loadPptImage(String url) async {
    if (_sharedDio == null) return null;
    try {
      final response = await _sharedDio!.get<Uint8List>(
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
      debugPrint('[Viewer] PPT image load failed: $e');
      return null;
    }
  }

  /// Navigate to AI Notes — triggers OCR via fetchClassroomContent.
  void _goToAiNotes() {
    // 加 PostFrameCallback 确保不在 build/layout 期间触发 Navigator 操作
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try { Navigator.of(context).pop(); } catch (_) {}
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        try { GoRouter.of(context).go('/notes'); } catch (_) {}
        // 在笔记页中触发带 OCR 的导入
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ref.read(notesProvider.notifier).fetchClassroomContent(
            widget.courseId, widget.subId,
            _content?.slides.firstOrNull?.imageUrl ?? '录播视频',
          );
        });
      });
    });
  }

  Future<void> _loadContent() async {
    debugPrint('[Viewer:D] _loadContent() start'
        ' courseId=${widget.courseId} subId=${widget.subId}');
    try {
      final crawler = ref.read(classroomCrawlerProvider);
      final results = await Future.wait([
        crawler.fetchCourseContent(widget.courseId, widget.subId),
        crawler.extractVideoUrl(widget.courseId, widget.subId),
      ]);
      final videoUrl = results[1] as String?;
      debugPrint('[Viewer:D] _loadContent() done'
          ' videoUrl=${videoUrl != null ? "✅ present(${videoUrl.length} chars)" : "❌ null"}'
          ' slides=${(results[0] as CourseContent).slides.length}'
          ' subs=${(results[0] as CourseContent).subtitles.length}');
      if (mounted) {
        setState(() {
          _content = results[0] as CourseContent;
          _videoUrl = videoUrl;
        });
      }
    } catch (e) {
      debugPrint('[Viewer:D] ❌ _loadContent failed: $e');
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(context),
      body: _buildBody(context),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    final loading = _content == null && _error == null;
    return AppBar(
      title: Text(
        widget.title,
        style: const TextStyle(fontSize: 16),
        overflow: TextOverflow.ellipsis,
      ),
      actions: [
        if (_content != null)
          IconButton(
            icon: const Icon(Icons.auto_awesome),
            tooltip: '生成 AI 笔记',
            onPressed: _goToAiNotes,
          ),
        IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
      bottom: loading
          ? const PreferredSize(
              preferredSize: Size.fromHeight(2),
              child: LinearProgressIndicator(),
            )
          : null,
    );
  }

  Widget _buildBody(BuildContext context) {
    // Loading
    if (_content == null && _error == null) {
      return const Center(child: CircularProgressIndicator());
    }

    // Error
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text('加载失败', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () {
                  setState(() {
                    _content = null;
                    _error = null;
                  });
                  _loadContent();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    // Content loaded — delegate to responsive layout
    final content = _content!;
    final loader = _loadPptImage;
    final videoUrl = _videoUrl;
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = constraints.maxWidth >= 1024 ? 'Desktop' :
                       constraints.maxWidth >= 600  ? 'Tablet' : 'Mobile';
        debugPrint('[Viewer:D] layout=$layout width=${constraints.maxWidth.toStringAsFixed(0)}px'
            ' videoUrl=${videoUrl != null ? "✅" : "❌null"}');
        if (constraints.maxWidth >= 1024) {
          return _DesktopLayout(
            content: content, imageLoader: loader, videoUrl: videoUrl);
        } else if (constraints.maxWidth >= 600) {
          return _TabletLayout(
            content: content, imageLoader: loader, videoUrl: videoUrl);
        } else {
          return _MobileLayout(
            content: content, imageLoader: loader, videoUrl: videoUrl);
        }
      },
    );
  }
}

// ── Responsive layouts ───────────────────────────────────────────

class _DesktopLayout extends StatefulWidget {
  final CourseContent content;
  final ImageLoader imageLoader;
  final String? videoUrl;
  const _DesktopLayout({
    required this.content,
    required this.imageLoader,
    this.videoUrl,
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
  const _TabletLayout({
    required this.content,
    required this.imageLoader,
    this.videoUrl,
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
  const _MobileLayout({
    required this.content,
    required this.imageLoader,
    this.videoUrl,
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
              PptViewer(slides: widget.content.slides, imageLoader: widget.imageLoader),
              SubtitleTimeline(subtitles: widget.content.subtitles),
            ],
          ),
        ),
      ],
    );
  }
}
