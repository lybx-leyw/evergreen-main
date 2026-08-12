/// 智云课堂录播查看器（全屏，临时路由打开时保留 Scaffold）。
///
/// B3-classroom（2026-08-12）自参考工程 `cp_evergreen_push/lib/features/
/// classroom/screens/classroom_viewer_screen.dart` 移植，改造要点：
/// - 去掉 AI 笔记入口（`notes_provider` 属 tutor feature，不在本轮范围）；
/// - 去掉 Riverpod family provider——改 state 内 FutureBuilder（PPT/字幕为
///   即时拉取，不进数据中枢）；视频直链经 `extractVideoUrl` 同批获取；
/// - Dio 经 `ensureZjuSession(prefs)` 获取（复用 SSO 持久 cookie），
///   PPT 图片下载带 classroom Referer（直链鉴权）；
/// - 下载目录用 path_provider `getDownloadsDirectory()`（桌面），
///   Android 回退 app 支持目录；打开文件夹复用 `openInFileManager`。
///
/// 三套响应式布局（与参考一致）：桌面 ≥1024（左 PPT 右字幕）/ 平板 600-1024
/// （上 PPT 下字幕）/ 窄屏 <600（TabBar 切换 PPT/字幕）。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:evergreen_base/core/log.dart';
import 'package:evergreen_base/core/utils/file_utils.dart';
import 'package:evergreen_base/providers.dart' show sharedPreferencesProvider;

import '../../shared/models/zju_course_content.dart';
import '../../zju_auth/zju_session.dart';
import '../services/classroom_service.dart';
import '../widgets/ppt_viewer.dart';
import '../widgets/subtitle_timeline.dart';
import '../widgets/video_player_panel.dart';

/// 全屏录播查看器：PPT + 字幕 + 可折叠视频播放。
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

class _ClassroomViewerScreenState extends ConsumerState<ClassroomViewerScreen> {
  static const _service = ZjuClassroomService();

  Future<Dio>? _dioFuture;
  Future<ZjuCourseContent>? _contentFuture;
  Future<String?>? _videoUrlFuture;
  Future<Map<String, String>>? _videoHeadersFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final prefs = ref.read(sharedPreferencesProvider);
    _dioFuture = ensureZjuSession(prefs: prefs);
    final f = _dioFuture!; // 刚赋值，非空
    setState(() {
      _contentFuture = f.then(
          (dio) => _service.fetchCourseContent(dio, widget.courseId, widget.subId));
      _videoUrlFuture = f.then(
          (dio) => _service.extractVideoUrl(dio, widget.courseId, widget.subId));
      // 视频流播放所需 Cookie/Referer（media_kit 独立进程不带 Dio jar）。
      // 依赖 dio future 串行：确保 ensureZjuSession 的 CMC 会话换取
      // （loginClassroom 写入 4 域 cookie）完成后才从 jar 导出。
      _videoHeadersFuture = f.then((_) => zjuVideoHttpHeaders());
    });
  }

  void _retry() => _load();

  /// 下载 PPT 图片字节（二进制，不适合 JSON 缓存）——带 classroom Referer。
  Future<Uint8List?> _loadPptImage(String url) async {
    try {
      final dio = await _dioFuture;
      if (dio == null) return null;
      final response = await dio.get<Uint8List>(
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
      Log().debug('ClassroomViewer: PPT 图片加载失败', data: {'url': url});
      return null;
    }
  }

  /// 下载目录：桌面优先系统下载目录，Android 回退 app 支持目录。
  Future<String> _downloadBaseDir() async {
    final downloads = await getDownloadsDirectory();
    if (downloads != null) return downloads.path;
    final support = await getApplicationSupportDirectory();
    return p.join(support.path, 'downloads');
  }

  /// 下载全部 PPT 到本地（带进度对话框）。
  Future<void> _downloadAllSlides(ZjuCourseContent content) async {
    if (content.slides.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前视频没有 PPT 幻灯片')),
      );
      return;
    }

    final dio = await _dioFuture;
    if (dio == null || !mounted) return;
    final baseDir = await _downloadBaseDir();
    final sanitizedTitle = widget.title
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final destDir = p.join(baseDir, '智云课堂PPT', sanitizedTitle);

    final progressState = _DownloadProgressState(total: content.slides.length);
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _DownloadProgressDialog(state: progressState),
    );

    try {
      final savedPaths = await _service.downloadSlides(
        dio,
        content.slides,
        destDir,
        onProgress: (completed, total) {
          progressState.completed = completed;
          progressState.notifyListeners();
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop(); // 关闭进度对话框
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已保存 ${savedPaths.length} / ${content.slides.length} 页 PPT'),
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: '打开文件夹',
            onPressed: () => openInFileManager(destDir),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('下载失败: $e')));
    }
  }

  /// 下载当前 PPT 页。
  Future<void> _downloadCurrentSlide(
      ZjuCourseContent content, int pageIndex) async {
    if (content.slides.isEmpty ||
        pageIndex < 0 ||
        pageIndex >= content.slides.length) {
      return;
    }
    final dio = await _dioFuture;
    if (dio == null || !mounted) return;

    final slide = content.slides[pageIndex];
    final baseDir = await _downloadBaseDir();
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

      final response = await dio.get<List<int>>(
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('保存失败: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.title,
          style: const TextStyle(fontSize: 16),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: '下载全部 PPT',
            onPressed: () => _contentFuture?.then((c) => _downloadAllSlides(c)),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: '关闭',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: FutureBuilder<ZjuCourseContent>(
        future: _contentFuture,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _buildError(snap.error.toString());
          }
          final content = snap.data;
          if (content == null) {
            return _buildError('内容为空');
          }
          return FutureBuilder<String?>(
            future: _videoUrlFuture,
            builder: (context, vSnap) {
              final videoUrl = vSnap.data;
              return FutureBuilder<Map<String, String>>(
                future: _videoHeadersFuture,
                builder: (context, hSnap) {
                  final videoHeaders = hSnap.data ?? const <String, String>{};
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth >= 1024) {
                        return _DesktopLayout(
                          content: content,
                          imageLoader: _loadPptImage,
                          videoUrl: videoUrl,
                          videoHeaders: videoHeaders,
                          onDownloadAll: () => _downloadAllSlides(content),
                          onDownloadCurrent: (page) =>
                              _downloadCurrentSlide(content, page),
                        );
                      } else if (constraints.maxWidth >= 600) {
                        return _TabletLayout(
                          content: content,
                          imageLoader: _loadPptImage,
                          videoUrl: videoUrl,
                          videoHeaders: videoHeaders,
                          onDownloadAll: () => _downloadAllSlides(content),
                          onDownloadCurrent: (page) =>
                              _downloadCurrentSlide(content, page),
                        );
                      }
                      return _MobileLayout(
                        content: content,
                        imageLoader: _loadPptImage,
                        videoUrl: videoUrl,
                        videoHeaders: videoHeaders,
                        onDownloadAll: () => _downloadAllSlides(content),
                        onDownloadCurrent: (page) =>
                            _downloadCurrentSlide(content, page),
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildError(String message) {
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
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _retry,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Responsive layouts ───────────────────────────────────────────

class _DesktopLayout extends StatefulWidget {
  final ZjuCourseContent content;
  final ImageLoader imageLoader;
  final String? videoUrl;
  final Map<String, String> videoHeaders;
  final VoidCallback? onDownloadAll;
  final ValueChanged<int>? onDownloadCurrent;

  const _DesktopLayout({
    required this.content,
    required this.imageLoader,
    this.videoUrl,
    this.videoHeaders = const {},
    this.onDownloadAll,
    this.onDownloadCurrent,
  });

  @override
  State<_DesktopLayout> createState() => _DesktopLayoutState();
}

class _DesktopLayoutState extends State<_DesktopLayout> {
  int _pptPage = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (widget.videoUrl != null && widget.videoUrl!.isNotEmpty)
          VideoPlayerPanel(
            videoUrl: widget.videoUrl!,
            title: '录播视频',
            httpHeaders: widget.videoHeaders,
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
                  onPageChanged: (p) => setState(() => _pptPage = p),
                  onDownloadAll: widget.onDownloadAll,
                  onDownloadCurrent: widget.onDownloadCurrent != null
                      ? () => widget.onDownloadCurrent!(_pptPage)
                      : null,
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                flex: 2,
                child: SubtitleTimeline(subtitles: widget.content.subtitles),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TabletLayout extends StatefulWidget {
  final ZjuCourseContent content;
  final ImageLoader imageLoader;
  final String? videoUrl;
  final Map<String, String> videoHeaders;
  final VoidCallback? onDownloadAll;
  final ValueChanged<int>? onDownloadCurrent;

  const _TabletLayout({
    required this.content,
    required this.imageLoader,
    this.videoUrl,
    this.videoHeaders = const {},
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
        if (widget.videoUrl != null && widget.videoUrl!.isNotEmpty)
          VideoPlayerPanel(
            videoUrl: widget.videoUrl!,
            title: '',
            httpHeaders: widget.videoHeaders,
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
  final ZjuCourseContent content;
  final ImageLoader imageLoader;
  final String? videoUrl;
  final Map<String, String> videoHeaders;
  final VoidCallback? onDownloadAll;
  final ValueChanged<int>? onDownloadCurrent;

  const _MobileLayout({
    required this.content,
    required this.imageLoader,
    this.videoUrl,
    this.videoHeaders = const {},
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
        if (widget.videoUrl != null && widget.videoUrl!.isNotEmpty)
          VideoPlayerPanel(
            videoUrl: widget.videoUrl!,
            title: '',
            httpHeaders: widget.videoHeaders,
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
