/// 教室模板主视图——课程录播回看（视频 + PPT + 字幕）。
///
/// 数据来源：manifest 模块级 `dataSource.endpoint` = `orch://<type>`（如 orch://courses），
/// 经 [resolveDataSource] 走数据中心拉取；无 endpoint 时展示空态提示（不再内嵌/直连）。
///
/// 字段提取（v5P 核心）：拉取到的整块数据**不**按写死的模型解析，而是按 manifest 的
/// `dataSource.bindings`（语义键 → JSON 键路径）经 [extractPath] 逐项提取，组装为
/// [ClassroomCourse] 等模型驱动 UI。`bindings` 未声明时回退到 [_defaultBindings]。
///
/// 适配自 `.refer_ui/widget/lib/features/classroom`，按 v5P 提升为独立 modle 私有视图，
/// 不再依赖 v4 的 [DataSourceSlot] 基类（取数逻辑自包含于本文件）。
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:crypto/crypto.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/providers.dart';
import 'package:evergreen_base/renderer/atomic/data_source_resolver.dart';
import 'package:evergreen_base/renderer/atomic/json_path.dart';
import 'package:evergreen_base/core/utils/greenix_path.dart';

import 'classroom_models.dart';
import 'widgets/ppt_viewer.dart';
import 'widgets/subtitle_timeline.dart';
import 'widgets/video_player_panel.dart';

/// 教室模板主视图。
///
/// 纯 UI（v5P 原子层之上的 modle 私有组件），取数仅经 [resolveDataSource]（orch://），
/// 不含任何业务逻辑或直连 HTTP。
class ClassroomView extends ConsumerStatefulWidget {
  /// 模块级数据源声明（orch://<type>）；为空则展示空态。
  final DataSourceDescriptor? dataSource;

  /// 模块 id（用于相对资源路径解析）。
  final String moduleId;

  /// 插件目录（资源根）。
  final String? pluginsDir;

  const ClassroomView({
    super.key,
    this.dataSource,
    required this.moduleId,
    this.pluginsDir,
  });

  @override
  ConsumerState<ClassroomView> createState() => _ClassroomViewState();
}

class _ClassroomViewState extends ConsumerState<ClassroomView> {
  ClassroomCourse? _selectedCourse;
  ClassroomVideo? _selectedVideo;
  Future<dynamic>? _future;
  /// 解析结果缓存：FutureBuilder 每次父级重建都会重新执行 builder，
  /// 若每次都重新 _parseCourses 会生成全新 course/video 实例，可能触发子树抖动；
  /// 数据一旦解析即缓存，后续重建复用同一批实例，视频播放器稳定不丢纹理。
  List<ClassroomCourse>? _coursesCache;

  bool get _hasDataSource {
    final ds = widget.dataSource;
    return ds != null && ds.endpoint != null && ds.endpoint!.isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    if (!_hasDataSource) return;
    // 经数据中心拉取（与 v4 DataSourceSlot 同款逻辑，自包含、不再依赖 v4）。
    _future = resolveDataSource(
      ds: widget.dataSource!,
      orch: ref.read(dataOrchestratorProvider),
    );
  }

  /// 字段绑定默认映射（语义键 → 数据 JSON 键路径）。
  ///
  /// manifest 的 `dataSource.bindings` 可覆盖其中任意键；未声明的键回退到此默认，
  /// 故标准 `orch://courses` 形状（courses[].{id,title,teachers,videos[].{...}}）
  /// 即使不写 bindings 也能正确解析。键命名采用「作用域.字段」约定：
  ///   - `courses`：课程列表根（相对整块数据）
  ///   - `course.*`：相对单个课程对象
  ///   - `video.*`：相对单个视频对象
  ///   - `slide.*` / `subtitle.*`：相对单个 PPT 幻灯片 / 字幕对象
  static const Map<String, String> _defaultBindings = {
    'courses': 'courses',
    'course.id': 'id',
    'course.title': 'title',
    'course.teachers': 'teachers',
    'course.videos': 'videos',
    'video.id': 'subId',
    'video.title': 'title',
    'video.videoUrl': 'videoUrl',
    'video.slides': 'slides',
    'video.subtitles': 'subtitles',
    'slide.page': 'page',
    'slide.imageUrl': 'imageUrl',
    'slide.text': 'text',
    'subtitle.startMs': 'startMs',
    'subtitle.endMs': 'endMs',
    'subtitle.text': 'text',
  };

  /// 取某语义键在实际数据中的 JSON 键路径：manifest 绑定优先，否则默认映射。
  String _bindPath(String key) {
    final b = widget.dataSource?.bindings;
    if (b != null && b.containsKey(key)) return b[key]!;
    return _defaultBindings[key] ?? key;
  }

  /// 从 [item] 按绑定路径提取某语义键的值（经 [extractPath]）。
  dynamic _pick(dynamic item, String key) => extractPath(item, _bindPath(key));

  /// 按 bindings 解析课程列表。驱动 UI 的模型从这里产生——完全由数据键路径驱动，
  /// 不依赖写死的 JSON 字段名。
  List<ClassroomCourse> _parseCourses(dynamic data) {
    dynamic rawCourses = extractPath(data, _bindPath('courses'));
    // 兜底：数据源直接返回裸 List（无顶层 courses 键）时也兼容。
    if (rawCourses == null && data is List) rawCourses = data;
    if (rawCourses is! List) return [];
    return rawCourses.whereType<Map>().map((c) {
      final teachersRaw = _pick(c, 'course.teachers');
      final teachers = teachersRaw is List
          ? teachersRaw.map((t) => t.toString()).toList()
          : <String>[];
      final vidsRaw = _pick(c, 'course.videos');
      final videos = vidsRaw is List
          ? vidsRaw.whereType<Map>().map(_parseVideo).toList()
          : <ClassroomVideo>[];
      return ClassroomCourse(
        id: _pick(c, 'course.id')?.toString() ?? '',
        title: _pick(c, 'course.title')?.toString() ?? '',
        teachers: teachers,
        videos: videos,
      );
    }).toList();
  }

  ClassroomVideo _parseVideo(Map c) {
    final slidesRaw = _pick(c, 'video.slides');
    final subsRaw = _pick(c, 'video.subtitles');
    return ClassroomVideo(
      subId: int.tryParse(_pick(c, 'video.id')?.toString() ?? '') ?? 0,
      title: _pick(c, 'video.title')?.toString() ?? '',
      videoUrl: _pick(c, 'video.videoUrl')?.toString(),
      slides: slidesRaw is List
          ? slidesRaw.whereType<Map>().map(_parseSlide).toList()
          : const [],
      subtitles: subsRaw is List
          ? subsRaw.whereType<Map>().map(_parseSubtitle).toList()
          : const [],
    );
  }

  PptSlide _parseSlide(Map s) {
    return PptSlide(
      page: int.tryParse(_pick(s, 'slide.page')?.toString() ?? '') ?? 0,
      imageUrl: _pick(s, 'slide.imageUrl')?.toString() ?? '',
      text: _pick(s, 'slide.text')?.toString(),
    );
  }

  Subtitle _parseSubtitle(Map s) {
    int ms(String k) => int.tryParse(_pick(s, k)?.toString() ?? '') ?? 0;
    return Subtitle(
      startMs: ms('subtitle.startMs'),
      endMs: ms('subtitle.endMs'),
      text: _pick(s, 'subtitle.text')?.toString() ?? '',
    );
  }

  /// 解析单个视频/图片路径：相对路径 → 绝对文件路径。
  String _resolvePath(String raw) {
    return resolvePluginAssetPath(
            raw, widget.moduleId, widget.pluginsDir ?? '') ??
        raw;
  }

  /// 加载 PPT 图片：
  /// - 本地路径（相对插件目录或绝对路径）→ 直接读文件（scraper 已下载到本地的首选路径）；
  /// - 远程 URL → 先看本地缓存，否则带 classroom 登录态 cookie 下载到缓存再读
  ///   （兜底：scraper 未预下载时才走网络，cookie 来自 data/classroom_cookies.json）。
  Future<Uint8List?> _loadImage(String imagePath) async {
    if (!_isRemoteUrl(imagePath)) {
      // 本地路径：scraper 已下载到 plugins/<moduleId>/data/ppt/...
      final file = File(_resolvePath(imagePath));
      if (await file.exists()) return await file.readAsBytes();
      return null;
    }
    // 远程 URL：本地缓存优先，避免重复下载
    final cache = _remoteCacheFile(imagePath);
    if (await cache.exists()) return await cache.readAsBytes();
    final bytes = await _downloadRemote(imagePath);
    if (bytes != null) {
      try {
        await cache.parent.create(recursive: true);
        await cache.writeAsBytes(bytes);
      } catch (_) {
        // 缓存写入失败不致命，仍返回内存字节
      }
    }
    return bytes;
  }

  /// 读取 scraper 持久化的 classroom 会话 cookie（用于远程图兜底下载）。
  Map<String, String>? _loadCookies() {
    final file = File(_resolvePath('data/classroom_cookies.json'));
    if (!file.existsSync()) return null;
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is Map) {
        return Map<String, String>.fromEntries(
          decoded.entries.map(
              (e) => MapEntry(e.key.toString(), e.value.toString())),
        );
      }
    } catch (_) {
      // 解析失败则放弃 cookie，走无 cookie 下载（可能 401，由调用方优雅降级）
    }
    return null;
  }

  /// 远程 URL 的本地缓存文件（按 URL 哈希命名，存于插件 data/ppt_cache/）。
  File _remoteCacheFile(String url) {
    final hash = md5.convert(utf8.encode(url)).toString();
    return File(_resolvePath('data/ppt_cache/$hash.png'));
  }

  bool _isRemoteUrl(String p) =>
      p.startsWith('http://') || p.startsWith('https://');

  /// 带 classroom 登录态 cookie 下载远程图片字节（失败返回 null，不抛）。
  Future<Uint8List?> _downloadRemote(String url) async {
    HttpClient? client;
    try {
      client = HttpClient()
        ..userAgent = _kPptUserAgent
        // 放宽证书校验：对齐 scraper 的 _create_unverified_context（内网教务域证书链不全）
        ..badCertificateCallback = (_, __, ___) => true;
      final req = await client.getUrl(Uri.parse(url));
      final cookies = _loadCookies();
      if (cookies != null && cookies.isNotEmpty) {
        req.headers.set(
          'Cookie',
          cookies.entries.map((e) => '${e.key}=${e.value}').join('; '),
        );
      }
      final resp = await req.close();
      if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
      final chunks = <int>[];
      await for (final chunk in resp) {
        chunks.addAll(chunk);
      }
      return Uint8List.fromList(chunks);
    } catch (e) {
      debugPrint('[ClassroomView] PPT 图下载失败: $url -> $e');
      return null;
    } finally {
      client?.close(force: true);
    }
  }

  static const String _kPptUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0 Safari/537.36';

  /// 保存当前页 PPT 到下载目录（占位：由 ppt_viewer 内部状态维护页码）。
  Future<void> _saveCurrentSlide() async {
    final v = _selectedVideo;
    if (v == null || v.slides.isEmpty) return;
  }

  /// 保存全部 PPT 到下载目录。
  Future<void> _saveAllSlides() async {
    final v = _selectedVideo;
    if (v == null || v.slides.isEmpty) return;
    final destBase =
        '${widget.pluginsDir ?? ''}/${widget.moduleId}/downloads/智云课堂PPT';
    final course = _selectedCourse;
    final dirName = course != null ? course.title : '未分类';
    final dir = Directory('$destBase/$dirName');
    if (!await dir.exists()) await dir.create(recursive: true);

    int saved = 0;
    int failed = 0;
    final errors = <String>[];

    for (final slide in v.slides) {
      try {
        final bytes = await _loadImage(slide.imageUrl);
        if (bytes == null) {
          failed++;
          continue;
        }
        final dest = File(
            '${dir.path}${Platform.pathSeparator}page_${slide.page}.png');
        await dest.writeAsBytes(bytes);
        saved++;
      } catch (e) {
        failed++;
        if (errors.length < 3) errors.add(e.toString());
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(failed == 0
          ? '已保存 $saved 页到 $dirName/'
          : '保存 $saved 页，$failed 页失败'),
      duration: const Duration(seconds: 2),
    ));
  }

  /// AI 笔记按钮：复用全局 AI——跳转到 AI 助手并预填 prompt（orch 之上的纯 UI 跳转）。
  void _onAiNotes() {
    final v = _selectedVideo;
    if (v == null) return;
    final course = _selectedCourse;
    final content = CourseContent(slides: v.slides, subtitles: v.subtitles);
    if (content.isEmpty) return;

    final prompt = content.aiContent;
    final q = 'prompt=${Uri.encodeComponent(prompt)}';
    GoRouter.of(context).go('/ai-assistant?$q');
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasDataSource) {
      return _emptyState(
          '缺少课程数据\n请在 manifest 的 dataSource 中配置 orch://<type> 与 bindings');
    }
    return FutureBuilder<dynamic>(
      future: _future,
      builder: (ctx, snap) {
        // 数据到达后只解析一次并缓存，避免每次重建都生成新实例导致子树抖动。
        final courses = _coursesCache ?? _parseCourses(snap.data);
        if (snap.hasData) _coursesCache = courses;
        return _buildView(courses);
      },
    );
  }

  Widget _buildView(List<ClassroomCourse> courses) {
    // 自动选第一个课程 / 第一视频
    if (courses.isEmpty) {
      return _emptyState(
          '缺少课程数据\n请确认数据源返回 {courses:[...]}，且 bindings 键路径正确（manifest 的 dataSource.bindings）');
    }

    // 选中项必须引用 courses 列表中的同一实例，否则 DropdownButton 按身份(identity)比对
    // value 与 items 时会断言失败（旧实例不在新解析出的列表里，匹配到 0 个）。
    final prevCourseId = _selectedCourse?.id;
    _selectedCourse = courses.firstWhere(
      (c) => c.id == prevCourseId,
      orElse: () => courses.first,
    );

    final selectedVideos = _selectedCourse!.videos;
    final prevVideoId = _selectedVideo?.subId;
    _selectedVideo = selectedVideos.isEmpty
        ? null
        : selectedVideos.firstWhere(
            (v) => v.subId == prevVideoId,
            orElse: () => selectedVideos.first,
          );

    final videos = _selectedCourse!.videos;
    final course = _selectedCourse!;
    final video = _selectedVideo;

    return Column(
      // stretch：让子项（含视频播放面板）横向撑满列宽，确保 Video 拿到有限非零宽度，
      // 避免 center（默认）下视频区固有宽度为 0 → media_kit 纹理 0x0 黑屏。
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 顶栏：课程选择 + 视频选择 + AI 笔记
        _buildTopBar(courses, videos, course),
        if (video != null) ...[
          // 视频播放器（远程录播地址注入登录态 Cookie，否则 media_kit 拉不到流 → 黑屏）
          VideoPlayerPanel(
            key: ValueKey(video.subId),
            videoUrl: video.videoUrl,
            resolvePath: _resolvePath,
            httpHeaders: _loadCookies(),
          ),
          const Divider(height: 1),
          // PPT + 字幕
          Expanded(child: _buildViewer(video)),
        ] else if (videos.isNotEmpty) ...[
          Expanded(child: _emptyState('请选择一个视频')),
        ] else ...[
          Expanded(child: _emptyState('该课程没有视频')),
        ],
      ],
    );
  }

  Widget _buildTopBar(
      List<ClassroomCourse> courses, List<ClassroomVideo> videos, ClassroomCourse course) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: theme.colorScheme.surfaceContainerLow,
      child: Row(
        children: [
          // 课程选择
          // 注：原用 DropdownButtonFormField 在该模块嵌入环境（顶栏 Row/Expanded）
          // 下表现不稳定（点不开/菜单不展开）。改用 PopupMenuButton——同一 app 内
          // 视频倍速菜单已验证可靠：点即弹、长列表自动滚动，且不依赖 DropdownButton
          // 的 identity 匹配与宽度约束。
          if (courses.length > 1)
            Expanded(
              child: PopupMenuButton<ClassroomCourse>(
                tooltip: '选择课程',
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: theme.colorScheme.outlineVariant),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(course.title,
                            style: const TextStyle(fontSize: 13),
                            overflow: TextOverflow.ellipsis),
                      ),
                      const Icon(Icons.arrow_drop_down, size: 18),
                    ],
                  ),
                ),
                itemBuilder: (_) => courses
                    .map((c) => PopupMenuItem(
                          value: c,
                          child: Text(c.title,
                              style: const TextStyle(fontSize: 13),
                              overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onSelected: (c) {
                  setState(() {
                    _selectedCourse = c;
                    _selectedVideo =
                        c.videos.isNotEmpty ? c.videos.first : null;
                  });
                },
              ),
            )
          else ...[
            Expanded(
              child: Text(course.title,
                  style: theme.textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis),
            ),
            if (course.teachers.isNotEmpty)
              Text(' · ${course.teachers.join('、')}',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
          ],
          const SizedBox(width: 8),
          // 视频选择（同课程选择，改用 PopupMenuButton 保证可靠点开）
          if (videos.length > 1)
            Expanded(
              child: PopupMenuButton<ClassroomVideo>(
                tooltip: '选择视频',
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: theme.colorScheme.outlineVariant),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(_selectedVideo?.title ?? '',
                            style: const TextStyle(fontSize: 13),
                            overflow: TextOverflow.ellipsis),
                      ),
                      const Icon(Icons.arrow_drop_down, size: 18),
                    ],
                  ),
                ),
                itemBuilder: (_) => videos
                    .map((v) => PopupMenuItem(
                          value: v,
                          child: Text(v.title,
                              style: const TextStyle(fontSize: 13),
                              overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onSelected: (v) => setState(() => _selectedVideo = v),
              ),
            ),
          // AI 笔记按钮（复用全局 AI）
          if (_selectedVideo != null &&
              (_selectedVideo!.slides.isNotEmpty ||
                  _selectedVideo!.subtitles.isNotEmpty))
            IconButton(
              icon: const Icon(Icons.auto_awesome, size: 18),
              tooltip: '生成 AI 笔记',
              onPressed: _onAiNotes,
            ),
        ],
      ),
    );
  }

  Widget _buildViewer(ClassroomVideo video) {
    final w = MediaQuery.of(context).size.width;
    final useRow = w >= 550; // slot 宽度超过 550px 时左右并排

    final ppt = PptViewer(
      slides: video.slides,
      loadImage: _loadImage,
      onSaveCurrent: _saveCurrentSlide,
      onSaveAll: _saveAllSlides,
    );
    final subs = SubtitleTimeline(subtitles: video.subtitles);

    if (video.slides.isEmpty && video.subtitles.isEmpty) {
      return _emptyState('该视频暂无内容');
    }

    if (video.slides.isEmpty) return subs;
    if (video.subtitles.isEmpty) return ppt;

    if (useRow) {
      return Row(
        children: [
          Expanded(flex: 3, child: ppt),
          const VerticalDivider(width: 1),
          Expanded(flex: 2, child: subs),
        ],
      );
    }
    // 窄屏：TabBar 切换
    return _buildTabbedViewer(ppt, subs);
  }

  Widget _buildTabbedViewer(Widget ppt, Widget subs) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'PPT', icon: Icon(Icons.slideshow, size: 16)),
              Tab(text: '字幕', icon: Icon(Icons.closed_caption, size: 16)),
            ],
            labelStyle: TextStyle(fontSize: 12),
          ),
          Expanded(
            child: TabBarView(
              children: [ppt, subs],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(String msg) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.video_library, size: 48,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(height: 8),
              Text(msg,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      );
}
