/// ZjuClassroomService — 智云课堂（education.cmc.zju.edu.cn / yjapi.cmc.zju.edu.cn
/// / classroom.zju.edu.cn）数据拉取服务。
///
/// B3-classroom（2026-08-12）自参考工程 `cp_evergreen_push/lib/features/
/// classroom/services/classroom_crawler.dart` 移植，改造要点：
/// - 去掉 WebCacheDatabase 本地缓存层——元数据（课程列表）由数据中枢
///   web_cache JSON + TTL 统一接管；PPT/字幕/视频为二进制或即时数据，
///   按规划 §5.3 不进中枢，UI 侧按需直连本 service；
/// - 去掉 Result 包装（fetcher 契约：直接返回数据或抛异常，中枢捕获置状态）；
/// - 网络层用共享 Dio（`ensureZjuSession` 提供，PersistCookieJar 自动携带
///   iPlanetDirectoryPro SSO cookie——域 `.zju.edu.cn` 覆盖三个接口域）。
///
/// 本 service 只做「取数 + 解析」，无状态、可注入 mock Dio 单测。
library;

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import 'package:evergreen_base/core/log.dart';

import '../../shared/models/zju_classroom_course.dart';
import '../../shared/models/zju_classroom_video.dart';
import '../../shared/models/zju_course_content.dart';
import '../../shared/models/zju_ppt_slide.dart';
import '../../shared/models/zju_subtitle.dart';

/// 抓取进度（PPT 页下载 / 字幕解析 / 完成）。
class ZjuFetchProgress {
  final String phase;
  final int completed;
  final int total;
  final int elapsedMs;

  const ZjuFetchProgress({
    required this.phase,
    required this.completed,
    required this.total,
    required this.elapsedMs,
  });

  String get label {
    switch (phase) {
      case 'slides':
        return '下载 PPT: $completed / $total 页';
      case 'subtitles':
        return '解析字幕...';
      case 'done':
        return '完成 ($completed 页 + $total 条字幕)';
      default:
        return '$phase...';
    }
  }

  double get ratio => total > 0 ? completed / total : 0.0;
}

typedef OnFetchProgress = void Function(ZjuFetchProgress progress);

/// 智云课堂数据服务。
class ZjuClassroomService {
  const ZjuClassroomService();

  /// 课程列表（智云课堂课程中心）。
  static const String _coursesUrl =
      'https://education.cmc.zju.edu.cn/personal/courseapi/vlabpassportapi/'
      'v1/account-profile/course?nowpage=1&per-page=100&force_mycourse=1';

  /// 某课程的视频目录（yjapi）。
  static const String _videosBaseUrl =
      'https://yjapi.cmc.zju.edu.cn/courseapi/v2/course/catalogue';

  /// PPT 搜索分页接口。
  static const String _slidesBaseUrl =
      'https://classroom.zju.edu.cn/pptnote/v1/schedule/search-ppt';

  /// ASR 字幕接口。
  static const String _subtitlesBaseUrl =
      'https://yjapi.cmc.zju.edu.cn/courseapi/v3/web-socket/search-trans-result';

  /// PPT 图片直链下载时携带的 Referer。
  static const String _classroomReferer = 'https://classroom.zju.edu.cn/';

  /// 拉取课程列表 → [ZjuClassroomCourse] 列表。
  ///
  /// 返回网页（SSO 过期）或网络失败抛可读 [StateError]。
  Future<List<ZjuClassroomCourse>> listCourses(Dio dio) async {
    try {
      final res = await dio.get(_coursesUrl);
      final data = _safeJsonParse(res, '课程列表');
      final rawList = data['params']?['result']?['data'] as List?;
      final courses = (rawList ?? [])
          .map((c) => ZjuClassroomCourse(
                id: int.tryParse(c['Id']?.toString() ?? '') ?? 0,
                title: c['Title']?.toString() ?? '',
                teacher: c['Teacher']?.toString(),
              ))
          .toList();
      Log().info('[zju/classroom] listCourses 成功', data: {'count': courses.length});
      return courses;
    } on DioException catch (e) {
      throw StateError(_dioError(e, '课程列表'));
    }
  }

  /// 拉取某课程的视频目录 → [ZjuClassroomVideo] 列表。
  ///
  /// 只保留 `status == '6'`（已发布可回看）的条目；`content` 字段可能是
  /// 内嵌 JSON 字符串或对象，解析出直链 `playback.url` / `video_url`。
  Future<List<ZjuClassroomVideo>> listVideos(Dio dio, int courseId) async {
    try {
      final res = await dio.get('$_videosBaseUrl?course_id=$courseId');
      final data = _safeJsonParse(res, '视频目录');
      final rawList = data['result']?['data'] as List?;

      final videos = (rawList ?? [])
          .where((v) => v['status']?.toString() == '6')
          .map((v) {
        final subId = int.tryParse(v['sub_id']?.toString() ?? '') ?? 0;
        final cid = int.tryParse(v['course_id']?.toString() ?? '') ?? 0;
        String? videoUrl;
        try {
          final contentRaw = v['content'];
          final parsed =
              contentRaw is String ? jsonDecode(contentRaw) : contentRaw;
          final playback = parsed?['playback'];
          videoUrl = playback?['url']?.toString() ??
              parsed?['video_url']?.toString();
        } catch (_) {
          /* content 非 JSON → videoUrl 保持 null，viewer 仅看 PPT/字幕 */
        }
        return ZjuClassroomVideo(
          id: '${cid}_$subId',
          courseId: cid,
          subId: subId,
          title: v['title']?.toString() ?? '',
          startAt: v['start_at']?.toString(),
          videoUrl: videoUrl,
        );
      }).toList();
      Log().info('[zju/classroom] listVideos 成功',
          data: {'courseId': courseId, 'count': videos.length});
      return videos;
    } on DioException catch (e) {
      throw StateError(_dioError(e, '视频目录'));
    }
  }

  /// 抓取某录播的全部 PPT 页 → [ZjuPptSlide] 列表。
  ///
  /// 分页拉取（最多 20 页），按图片 URL 去重；空列表返回空（不抛）。
  Future<List<ZjuPptSlide>> fetchSlides(
    Dio dio,
    int courseId,
    int subId, {
    OnFetchProgress? onProgress,
  }) async {
    final items = <ZjuPptSlide>[];
    final seenUrls = <String>{};
    int rawCount = 0;

    for (var page = 1; page <= 20; page++) {
      final url = '$_slidesBaseUrl'
          '?course_id=$courseId&sub_id=$subId&page=$page&per_page=100';
      try {
        final res = await dio.get(url);
        final data = _safeJsonParse(res, 'PPT 列表');
        final list = data['list'] as List? ?? [];
        rawCount += list.length;
        if (list.isEmpty) break;

        for (final item in list) {
          if (item is! Map) continue;
          String? imageUrl;
          String? slideText;
          try {
            final content = item['content'];
            final parsed = content is String
                ? jsonDecode(content)
                : (content is Map ? content : {});
            imageUrl = parsed['pptimgurl']?.toString();
            slideText = parsed['text']?.toString();
          } catch (_) {}
          if (imageUrl == null || imageUrl.isEmpty || seenUrls.contains(imageUrl)) {
            continue;
          }
          seenUrls.add(imageUrl);
          items.add(ZjuPptSlide(
            page: items.length + 1,
            imageUrl: imageUrl,
            text: slideText,
          ));
        }

        onProgress?.call(ZjuFetchProgress(
          phase: 'slides',
          completed: items.length,
          total: rawCount + (list.length < 100 ? 0 : 50),
          elapsedMs: 0,
        ));

        if (list.length < 100) break;
      } on DioException catch (e) {
        Log().warn('[zju/classroom] fetchSlides page=$page 失败',
            data: {'error': e.toString()});
        break; // 单页失败停止翻页，返回已抓取部分
      }
    }

    Log().info('[zju/classroom] fetchSlides 成功',
        data: {'courseId': courseId, 'subId': subId, 'count': items.length});
    return items;
  }

  /// 抓取某录播的 ASR 字幕 → [ZjuSubtitle] 列表。
  ///
  /// 返回网页（SSO 过期）抛可读异常；无字幕 / 非 JSON 返回空列表。
  Future<List<ZjuSubtitle>> fetchSubtitles(Dio dio, int courseId, int subId) async {
    try {
      final res =
          await dio.get('$_subtitlesBaseUrl?sub_id=$subId&format=json');
      var rawData = res.data;
      if (rawData is String) {
        try {
          rawData = jsonDecode(rawData);
        } catch (_) {
          return <ZjuSubtitle>[];
        }
      }
      if (rawData is! Map) return <ZjuSubtitle>[];

      final list = rawData['list'] as List? ?? [];
      if (list.isEmpty) return <ZjuSubtitle>[];

      final subs = <ZjuSubtitle>[];
      for (final item in list) {
        if (item is! Map) continue;
        final allContent = item['all_content'];
        if (allContent is! List) continue;
        for (final c in allContent) {
          if (c is! Map) continue;
          final beginSecStr = c['BeginSec']?.toString() ?? '';
          final text = (c['Text']?.toString() ?? '').trim();
          if (text.isEmpty) continue;
          subs.add(ZjuSubtitle(
            startMs: ((double.tryParse(beginSecStr) ?? 0.0) * 1000).toInt(),
            endMs: 0,
            text: text,
          ));
        }
      }
      Log().info('[zju/classroom] fetchSubtitles 成功',
          data: {'courseId': courseId, 'subId': subId, 'count': subs.length});
      return subs;
    } on DioException catch (e) {
      throw StateError(_dioError(e, '字幕'));
    }
  }

  /// 聚合某录播的完整内容（PPT + 字幕并行拉取）。
  Future<ZjuCourseContent> fetchCourseContent(
    Dio dio,
    int courseId,
    int subId, {
    OnFetchProgress? onProgress,
  }) async {
    final results = await Future.wait([
      fetchSlides(dio, courseId, subId, onProgress: onProgress),
      fetchSubtitles(dio, courseId, subId),
    ]);
    final content = ZjuCourseContent(
      slides: results[0] as List<ZjuPptSlide>,
      subtitles: results[1] as List<ZjuSubtitle>,
    );
    onProgress?.call(ZjuFetchProgress(
      phase: 'done',
      completed: content.slides.length,
      total: content.subtitles.length,
      elapsedMs: 0,
    ));
    return content;
  }

  /// 提取某录播的视频直链（先拉目录再按 subId 匹配）。
  Future<String?> extractVideoUrl(Dio dio, int courseId, int subId) async {
    final videos = await listVideos(dio, courseId);
    for (final v in videos) {
      if (v.subId == subId) return v.videoUrl;
    }
    return null;
  }

  /// 批量下载 PPT 图片到 [destDir]（创建目录，`page_{N}.{ext}` 命名）。
  ///
  /// 返回成功保存的文件路径列表；单页失败跳过不中断。
  /// 全部失败抛 [StateError]（用户可读）。图片直链需携带 classroom Referer。
  Future<List<String>> downloadSlides(
    Dio dio,
    List<ZjuPptSlide> slides,
    String destDir, {
    void Function(int completed, int total)? onProgress,
  }) async {
    final dir = Directory(destDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final savedPaths = <String>[];
    final total = slides.length;

    for (var i = 0; i < total; i++) {
      final slide = slides[i];
      final uri = Uri.tryParse(slide.imageUrl);
      final ext = uri != null && uri.path.contains('.')
          ? '.${uri.path.split('.').last}'
          : '.png';
      final fileName = 'page_${slide.page}$ext';
      final filePath = p.join(destDir, fileName);

      try {
        final response = await dio.get<List<int>>(
          slide.imageUrl,
          options: Options(
            responseType: ResponseType.bytes,
            followRedirects: true,
            headers: {
              'Referer': _classroomReferer,
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            },
          ),
        );
        final file = File(filePath);
        await file.writeAsBytes(response.data!);
        savedPaths.add(filePath);
      } catch (e) {
        Log().warn('[zju/classroom] downloadSlides 第 ${slide.page} 页失败',
            data: {'error': e.toString()});
      }

      onProgress?.call(i + 1, total);
    }

    if (savedPaths.isEmpty) {
      throw StateError('PPT 下载失败：所有页面均未保存成功');
    }
    return savedPaths;
  }

  // ── Internal ───────────────────────────────────────────────────────

  /// 解析 JSON，若返回的是网页（SSO 会话过期）抛可读异常。
  Map<String, dynamic> _safeJsonParse(Response res, String label) {
    final text = res.data is String ? res.data as String : jsonEncode(res.data);
    if (text.trim().startsWith('<')) {
      throw StateError('$label 返回了网页而非数据——SSO 会话可能已过期，请重新登录');
    }
    try {
      if (res.data is Map) return res.data as Map<String, dynamic>;
      return jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      throw StateError('$label 返回了无效数据格式');
    }
  }

  /// Dio 异常 → 用户可读中文消息。
  String _dioError(DioException e, String label) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return '$label拉取超时，请检查网络后重试';
    }
    if (e.type == DioExceptionType.connectionError) {
      return '$label网络连接失败（$label服务不可达）';
    }
    final code = e.response?.statusCode;
    if (code == 401 || code == 403) {
      return '$label无权限——SSO 会话可能已过期，请重新登录';
    }
    return '$label拉取失败：${e.message ?? e.toString()}';
  }
}
