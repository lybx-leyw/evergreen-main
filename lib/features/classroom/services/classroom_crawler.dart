import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import '../../../core/result.dart';
import '../../../core/errors.dart';
import '../../../core/log.dart';
import '../../../core/storage/database.dart';
import '../models/ppt_slide.dart';
import '../models/subtitle.dart';
import '../models/classroom_video.dart';
import '../models/course_content.dart';

class FetchProgress {
  final String phase;
  final int completed;
  final int total;
  final int elapsedMs;
  const FetchProgress({
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

typedef OnFetchProgress = void Function(FetchProgress progress);

/// Classroom Crawler — fetches PPT slides, ASR subtitles, and video URLs.
class ClassroomCrawler {
  final Dio _dio;

  ClassroomCrawler(this._dio);

  static final _sw = Stopwatch();
  static void _d(String tag, String msg) {
    Log().debug('CCrawl:$tag', data: {'msg': msg});
  }

  /// List courses from 智云课堂.
  Future<Result<List<ClassroomCourse>>> listCourses() async {
    _d('L3', 'listCourses() start');
    _sw.reset();
    _sw.start();

    // 缓存优先：若新鲜文件缓存存在，直接返回
    try {
      final db = WebCacheDatabase.instanceOrNull;
      if (db != null) {
        final fresh = db.getFreshCachedWebPage('classroom_courses', const Duration(hours: 1));
        if (fresh != null) {
          final cached = db.getCachedList('classroom_courses');
          if (cached.isNotEmpty) {
            final courses = cached
                .map((c) => ClassroomCourse(
                      id: int.tryParse(c['Id']?.toString() ?? '') ?? 0,
                      title: c['Title']?.toString() ?? '',
                      teacher: c['Teacher']?.toString(),
                    ))
                .toList();
            _d('L3', 'listCourses() → ${courses.length} courses (cache)');
            return Ok(courses);
          }
        }
      }
    } catch (_) { /* 缓存读取失败 → 走网络 */ }

    const url =
        'https://education.cmc.zju.edu.cn/personal/courseapi/vlabpassportapi/v1/account-profile/course?nowpage=1&per-page=100&force_mycourse=1';

    try {
      final res = await _dio.get(url);
      _d('L1', 'listCourses status=${res.statusCode}');

      final data = res.data;
      final rawList = data?['params']?['result']?['data'] as List?;

      final courses = (rawList ?? [])
          .map((c) => ClassroomCourse(
                id: int.tryParse(c['Id']?.toString() ?? '') ?? 0,
                title: c['Title']?.toString() ?? '',
                teacher: c['Teacher']?.toString(),
              ))
          .toList();

      // 写入缓存
      try {
        final db = await WebCacheDatabase.getInstance();
        final jsonList = courses
            .map((c) => {'Id': c.id.toString(), 'Title': c.title, 'Teacher': c.teacher})
            .toList();
        await db.setCachedWebPage('classroom_courses', jsonEncode(jsonList));
      } catch (_) {}

      _d('L3',
          'listCourses() → ${courses.length} courses in ${_sw.elapsedMilliseconds}ms');
      return Ok(courses);
    } catch (e, stack) {
      Log().warn('ClassroomCrawler.listCourses failed', error: e);
      // 回退缓存
      try {
        final db = await WebCacheDatabase.getInstance();
        final cached = db.getCachedList('classroom_courses');
        if (cached.isNotEmpty) {
          final courses = cached
              .map((c) => ClassroomCourse(
                    id: int.tryParse(c['Id']?.toString() ?? '') ?? 0,
                    title: c['Title']?.toString() ?? '',
                    teacher: c['Teacher']?.toString(),
                  ))
              .toList();
          Log().info('Classroom: using cached ${courses.length} courses');
          return Ok(courses);
        }
      } catch (_) {}
      return Err(AppError.networkUnreachable('education.cmc.zju.edu.cn'));
    }
  }

  /// List videos for a course.
  Future<Result<List<ClassroomVideo>>> listVideos(int courseId) async {
    _d('L3', 'listVideos(courseId=$courseId) start');
    _sw.reset();
    _sw.start();

    // 缓存优先
    final cacheKey = 'classroom_videos_$courseId';
    try {
      final db = WebCacheDatabase.instanceOrNull;
      if (db != null) {
        final fresh = db.getFreshCachedWebPage(cacheKey, const Duration(hours: 1));
        if (fresh != null) {
          final cached = db.getCachedList(cacheKey);
          if (cached.isNotEmpty) {
            final videos = cached
                .map((e) => ClassroomVideo.fromJson(e as Map<String, dynamic>))
                .toList();
            _d('L3', 'listVideos() → ${videos.length} videos (cache)');
            return Ok(videos);
          }
        }
      }
    } catch (_) { /* 缓存读取失败 → 走网络 */ }

    final url =
        'https://yjapi.cmc.zju.edu.cn/courseapi/v2/course/catalogue?course_id=$courseId';

    try {
      final res = await _dio.get(url);
      _d('L1', 'listVideos status=${res.statusCode}');

      final data = res.data;
      final rawList = data?['result']?['data'] as List?;

      final videos = (rawList ?? [])
          .where((v) => v['status']?.toString() == '6')
          .map((v) {
            final subId =
                int.tryParse(v['sub_id']?.toString() ?? '') ?? 0;
            final courseIdFromData =
                int.tryParse(v['course_id']?.toString() ?? '') ?? 0;
            final title = v['title']?.toString() ?? '';
            final startAt = v['start_at']?.toString();

            String? videoUrl;
            try {
              final contentRaw = v['content'];
              final parsed = contentRaw is String
                  ? jsonDecode(contentRaw)
                  : contentRaw;
              final playback = parsed?['playback'];
              videoUrl = playback?['url']?.toString() ??
                  parsed?['video_url']?.toString();
            } catch (_) {}

            return ClassroomVideo(
              id: '${courseIdFromData}_$subId',
              courseId: courseIdFromData,
              subId: subId,
              title: title,
              startAt: startAt,
              videoUrl: videoUrl,
            );
          })
          .toList();

      // 写入缓存
      try {
        final db = await WebCacheDatabase.getInstance();
        await db.setCachedWebPage(
            cacheKey, jsonEncode(videos.map((v) => v.toJson()).toList()));
      } catch (_) {}

      _d('L3',
          'listVideos() → ${videos.length} videos in ${_sw.elapsedMilliseconds}ms');
      return Ok(videos);
    } catch (e, stack) {
      Log().warn('ClassroomCrawler.listVideos failed',
          error: e);
      // 回退过期缓存
      try {
        final db = await WebCacheDatabase.getInstance();
        final cached = db.getCachedList(cacheKey);
        if (cached.isNotEmpty) {
          final videos = cached
              .map((e) => ClassroomVideo.fromJson(e as Map<String, dynamic>))
              .toList();
          Log().info('Classroom: using cached ${videos.length} videos');
          return Ok(videos);
        }
      } catch (_) {}
      return Err(
          AppError.networkUnreachable('yjapi.cmc.zju.edu.cn'));
    }
  }

  /// Fetch PPT slides for a video.
  Future<Result<List<PptSlide>>> fetchSlides(int courseId, int subId,
      {OnFetchProgress? onProgress}) async {
    _d('L3', 'fetchSlides(courseId=$courseId subId=$subId) start');
    _sw.reset();
    _sw.start();

    // 缓存优先
    final cacheKey = 'classroom_slides_${courseId}_$subId';
    try {
      final db = WebCacheDatabase.instanceOrNull;
      if (db != null) {
        final fresh = db.getFreshCachedWebPage(cacheKey, const Duration(hours: 1));
        if (fresh != null) {
          final cached = db.getCachedList(cacheKey);
          if (cached.isNotEmpty) {
            final slides = cached
                .map((e) => PptSlide.fromJson(e as Map<String, dynamic>))
                .toList();
            _d('L3', 'fetchSlides() → ${slides.length} slides (cache)');
            return Ok(slides);
          }
        }
      }
    } catch (_) { /* 缓存读取失败 → 走网络 */ }

    final items = <PptSlide>[];
    final seenUrls = <String>{};
    int rawCount = 0;

    for (var page = 1; page <= 20; page++) {
      final url = 'https://classroom.zju.edu.cn/pptnote/v1/schedule/search-ppt'
          '?course_id=$courseId&sub_id=$subId&page=$page&per_page=100';

      try {
        final res = await _dio.get(url);
        var rawBody = res.data;
        if (rawBody is String) {
          try {
            rawBody = jsonDecode(rawBody);
          } catch (_) {}
        }
        if (rawBody is! Map) break;

        final list = rawBody['list'] as List? ?? [];
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

          if (imageUrl == null ||
              imageUrl.isEmpty ||
              seenUrls.contains(imageUrl)) {
            continue;
          }
          seenUrls.add(imageUrl);

          items.add(PptSlide(
            page: items.length + 1,
            imageUrl: imageUrl,
            text: slideText,
          ));
        }

        onProgress?.call(FetchProgress(
          phase: 'slides',
          completed: items.length,
          total: rawCount + (list.length < 100 ? 0 : 50),
          elapsedMs: _sw.elapsedMilliseconds,
        ));

        if (list.length < 100) break;
      } catch (e) {
        Log().warn('ClassroomCrawler.fetchSlides page=$page failed',
            error: e);
        break;
      }
    }

    // 写入缓存
    if (items.isNotEmpty) {
      try {
        final db = await WebCacheDatabase.getInstance();
        await db.setCachedWebPage(
            cacheKey, jsonEncode(items.map((s) => s.toJson()).toList()));
      } catch (_) {}
    }

    _d('L3',
        'fetchSlides() → ${items.length} slides in ${_sw.elapsedMilliseconds}ms');
    return Ok(items);
  }

  /// Fetch ASR subtitles.
  Future<Result<List<Subtitle>>> fetchSubtitles(int courseId, int subId) async {
    _d('L3', 'fetchSubtitles(courseId=$courseId subId=$subId) start');
    _sw.reset();
    _sw.start();

    // 缓存优先
    final cacheKey = 'classroom_subtitles_${courseId}_$subId';
    try {
      final db = WebCacheDatabase.instanceOrNull;
      if (db != null) {
        final fresh = db.getFreshCachedWebPage(cacheKey, const Duration(hours: 1));
        if (fresh != null) {
          final cached = db.getCachedList(cacheKey);
          if (cached.isNotEmpty) {
            final subs = cached
                .map((e) => Subtitle.fromJson(e as Map<String, dynamic>))
                .toList();
            _d('L3', 'fetchSubtitles() → ${subs.length} subtitles (cache)');
            return Ok(subs);
          }
        }
      }
    } catch (_) { /* 缓存读取失败 → 走网络 */ }

    try {
      const base =
          'https://yjapi.cmc.zju.edu.cn/courseapi/v3/web-socket/search-trans-result';
      final url = '$base?sub_id=$subId&format=json';

      final res = await _dio.get(url);
      var rawData = res.data;

      if (rawData is String) {
        try {
          rawData = jsonDecode(rawData);
        } catch (_) {
          return Ok(<Subtitle>[]);
        }
      }
      if (rawData is! Map) return Ok(<Subtitle>[]);

      final list = (rawData['list'] as List? ?? []);
      if (list.isEmpty) return Ok(<Subtitle>[]);

      final subs = <Subtitle>[];
      for (final item in list) {
        if (item is! Map) continue;
        final allContent = item['all_content'];
        if (allContent is! List) continue;

        for (final c in allContent) {
          if (c is! Map) continue;
          final beginSecStr = c['BeginSec']?.toString() ?? '';
          final text = (c['Text']?.toString() ?? '').trim();
          if (text.isEmpty) continue;

          subs.add(Subtitle(
            startMs: ((double.tryParse(beginSecStr) ?? 0.0) * 1000).toInt(),
            endMs: 0,
            text: text,
          ));
        }
      }

      // 写入缓存
      if (subs.isNotEmpty) {
        try {
          final db = await WebCacheDatabase.getInstance();
          await db.setCachedWebPage(
              cacheKey, jsonEncode(subs.map((s) => s.toJson()).toList()));
        } catch (_) {}
      }

      _d('L3',
          'fetchSubtitles() → ${subs.length} subtitles in ${_sw.elapsedMilliseconds}ms');
      return Ok(subs);
    } catch (e) {
      Log().warn('ClassroomCrawler.fetchSubtitles failed', error: e);
      // 回退过期缓存
      try {
        final db = await WebCacheDatabase.getInstance();
        final cached = db.getCachedList(cacheKey);
        if (cached.isNotEmpty) {
          final subs = cached
              .cast<Map<String, dynamic>>()
              .map((e) => Subtitle.fromJson(e))
              .toList();
          Log().info('Classroom: using cached ${subs.length} subtitles');
          return Ok(subs);
        }
      } catch (_) {}
      return Ok(<Subtitle>[]);
    }
  }

  /// Fetch all content for a video.
  Future<Result<CourseContent>> fetchCourseContent(int courseId, int subId,
      {bool includeSlides = true,
      bool includeSubtitles = true,
      OnFetchProgress? onProgress}) async {
    _d('L3',
        'fetchCourseContent(courseId=$courseId subId=$subId) start');
    _sw.reset();
    _sw.start();

    // 缓存优先：课程内容聚合了 slides + subtitles
    final cacheKey = 'classroom_content_${courseId}_$subId';
    try {
      final db = WebCacheDatabase.instanceOrNull;
      if (db != null) {
        final fresh = db.getFreshCachedWebPage(cacheKey, const Duration(hours: 1));
        if (fresh != null) {
          final cached = db.getCachedList(cacheKey);
          if (cached.isNotEmpty) {
            final content = CourseContent.fromJson(
                cached.first as Map<String, dynamic>);
            _d('L3', 'fetchCourseContent() → slides=${content.slides.length}, subtitles=${content.subtitles.length} (cache)');
            return Ok(content);
          }
        }
      }
    } catch (_) { /* 缓存读取失败 → 走网络 */ }

    final results = await Future.wait([
      includeSlides
          ? fetchSlides(courseId, subId, onProgress: onProgress)
          : Future.value(Ok(<PptSlide>[])),
      includeSubtitles
          ? fetchSubtitles(courseId, subId)
          : Future.value(Ok(<Subtitle>[])),
    ]);

    final slides = (results[0] as Result<List<PptSlide>>).fold(
      (s) => s,
      (_) => <PptSlide>[],
    );
    final subtitles = (results[1] as Result<List<Subtitle>>).fold(
      (s) => s,
      (_) => <Subtitle>[],
    );

    final content = CourseContent(slides: slides, subtitles: subtitles);

    // 写入缓存
    try {
      final db = await WebCacheDatabase.getInstance();
      await db.setCachedWebPage(cacheKey, jsonEncode([content.toJson()]));
    } catch (_) {}

    onProgress?.call(FetchProgress(
      phase: 'done',
      completed: slides.length,
      total: subtitles.length,
      elapsedMs: _sw.elapsedMilliseconds,
    ));

    return Ok(content);
  }

  /// Extract video direct URL.
  Future<String?> extractVideoUrl(int courseId, int subId) async {
    _d('L3', 'extractVideoUrl(courseId=$courseId subId=$subId) start');
    _sw.reset();
    _sw.start();

    final result = await listVideos(courseId);
    if (result.isErr) return null;

    final videos = (result as Ok<List<ClassroomVideo>>).value;
    final video = videos.where((v) => v.subId == subId).firstOrNull;
    return video?.videoUrl;
  }
}

class ClassroomCourse {
  final int id;
  final String title;
  final String? teacher;
  const ClassroomCourse({required this.id, required this.title, this.teacher});
}
