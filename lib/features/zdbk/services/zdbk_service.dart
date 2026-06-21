import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';


import '../../../core/result.dart';
import '../../../core/errors.dart';
import '../../../core/log.dart';
import '../../../core/storage/database.dart';
import '../../../core/models/grade.dart';
import '../../../core/models/course_offering.dart';
import '../../../core/models/timetable_session.dart';
import '../../../core/utils/html_parser.dart';
import '../../../core/utils/gpa_calculator.dart';
import '../../../core/models/zdbk_notification.dart';
import 'zdbk_patterns.dart';

/// ZDBK (教务管理系统) Service — full port of Celechron's zdbk.dart.
///
/// All public methods return [Result<T>] instead of throwing exceptions.
/// Internal helpers still use exceptions for control flow (caught by
/// [_withAutoRelogin]), but public API surfaces only typed [AppError]s.
class ZdbkService {
  final WebCacheDatabase _db;

  Cookie? _jSessionId;
  Cookie? _route;
  Cookie? _iPlanetDirectoryPro;
  HttpClient? _httpClient;
  int _reloginAttempts = 0;
  static const int _maxReloginAttempts = 2;

  ZdbkService(this._db);

  // ── Login ──────────────────────────────────────────────────────────

  /// Login to ZDBK using an iPlanetDirectoryPro SSO cookie.
  Future<bool> login(HttpClient httpClient, Cookie iPlanetDirectoryPro) async {
    _iPlanetDirectoryPro = iPlanetDirectoryPro;
    _httpClient = httpClient;

    try {
      // Step 1: CAS service validation
      final req1 = await httpClient
          .getUrl(Uri.parse(
              'https://zjuam.zju.edu.cn/cas/login'
              '?service=https%3A%2F%2Fzdbk.zju.edu.cn%2Fjwglxt%2Fxtgl%2Flogin_ssologin.html'))
          .timeout(const Duration(seconds: 10));
      req1.followRedirects = false;
      req1.cookies.add(iPlanetDirectoryPro);
      final res1 = await req1.close().timeout(const Duration(seconds: 10));
      await res1.drain();

      var location = res1.headers.value('location');
      if (location == null) {
        Log().warn('ZDBK login: no CAS redirect — cookie may be invalid');
        return false;
      }
      if (location.startsWith('http://')) {
        location = location.replaceFirst('http://', 'https://');
      }

      // Step 2: Follow redirect to ZDBK
      final req2 = await httpClient
          .getUrl(Uri.parse(location))
          .timeout(const Duration(seconds: 10));
      req2.followRedirects = false;
      final res2 = await req2.close().timeout(const Duration(seconds: 10));
      await res2.drain();

      // Step 3: Extract cookies
      try {
        _jSessionId = res2.cookies.firstWhere(
            (c) => c.name == 'JSESSIONID' && c.path == '/jwglxt');
      } catch (_) {
        Log().warn('ZDBK login: no JSESSIONID cookie');
        return false;
      }

      try {
        _route = res2.cookies.firstWhere((c) => c.name == 'route');
      } catch (_) {
        Log().warn('ZDBK login: no route cookie');
        return false;
      }

      _reloginAttempts = 0;
      Log().info('ZDBK login succeeded');
      return true;
    } on SocketException catch (e) {
      Log().warn('ZDBK login: network error', error: e);
      return false;
    } on TimeoutException {
      Log().warn('ZDBK login: timeout');
      return false;
    }
  }

  // ── Transcript ─────────────────────────────────────────────────────

  /// Get transcript (all semesters grades).
  ///
  /// Falls back to file cache on non-auth errors, with proper [Grade]
  /// deserialization (unlike the generic `_withAutoRelogin` cache fallback
  /// which returns raw `List<Map>`).
  Future<Result<List<Grade>>> getTranscript(HttpClient httpClient) async {
    // 缓存优先：新鲜缓存直接返回，避免网络请求
    final cached = _tryFreshCache('zdbk_Transcript', CacheTtl.transcript, (list) {
      final grades = list.cast<Map<String, dynamic>>()
          .where((e) => e['xkkh'] != null)
          .map((e) => Grade.fromJson(e))
          .toList();
      return grades.isNotEmpty ? grades : null;
    });
    if (cached != null) return Ok(cached);

    final result = await _withAutoRelogin(() async {
      final htmlResult = await _zdbkPost(httpClient,
          'https://zdbk.zju.edu.cn/jwglxt/cxdy/xscjcx_cxXscjIndex.html'
          '?doType=query&queryModel.showCount=5000');

      if (htmlResult.isErr) {
        final err = (htmlResult as Err<String>).error;
        // Session expired → propagate for retry
        if (err is AuthError) return Err<List<Grade>>(err);
        return Err<List<Grade>>(err);
      }
      final html = (htmlResult as Ok<String>).value;

      final items = HtmlParser.extractItems(html);
      if (items.isEmpty) {
        Log().warn('Transcript: empty items',
            data: {'htmlPreview': html.substring(0, min(html.length, 200))});
        return Err<List<Grade>>(AppError.parseHtml(html, 'grade items'));
      }

      Log().debug('Transcript parsed', data: {'count': items.length});
      _db.setCachedWebPage('zdbk_Transcript', jsonEncode(items));
      final grades = items
          .where((e) => e['xkkh'] != null)
          .map((e) => Grade.fromJson(e))
          .toList();
      return Ok(grades);
    }); // No fallbackKey — handled below with proper deserialization

    // Type-safe cache fallback: parse cached raw items into Grade objects.
    return result.fold(
      (grades) => Ok(grades),
      (error) {
        if (error is AuthError) return Err(error);
        final cached = _db.getCachedList('zdbk_Transcript');
        if (cached.isEmpty) return Err(error);
        try {
          final grades = cached
              .cast<Map<String, dynamic>>()
              .where((e) => e['xkkh'] != null)
              .map((e) => Grade.fromJson(e))
              .toList();
          if (grades.isNotEmpty) {
            Log().info('ZDBK transcript: using cached data',
                data: {'count': grades.length});
            return Ok(grades);
          }
        } catch (e) {
          Log().warn('ZDBK transcript: cache deserialization failed', error: e);
        }
        return Err(error);
      },
    );
  }

  // ── Major Grade ────────────────────────────────────────────────────

  /// Get major grades with GPA calculation.
  Future<Result<MajorGradesResult>> getMajorGrade(
      HttpClient httpClient) async {
    return _withAutoRelogin(() async {
      final htmlResult = await _zdbkPost(httpClient,
          'https://zdbk.zju.edu.cn/jwglxt/zycjtj/xszgkc_cxXsZgkcIndex.html'
          '?doType=query&queryModel.showCount=5000');

      if (htmlResult.isErr) {
        final err = (htmlResult as Err<String>).error;
        if (err is AuthError) return Err(err);
        return Err(err);
      }
      final html = (htmlResult as Ok<String>).value;

      final items = HtmlParser.extractItems(html);
      if (items.isEmpty) {
        return Err(AppError.parseHtml(html, 'major grade items'));
      }

      _db.setCachedWebPage('zdbk_MajorGrade', jsonEncode(items));
      final grades = items
          .where((e) => e['xkkh'] != null)
          .map((e) => Grade.fromJson(e)..major = true)
          .toList();
      return Ok(MajorGradesResult(
          grades: grades, gpa: GpaCalculator.calculateGpa(grades)));
    }, fallbackKey: 'zdbk_MajorGrade');
  }

  // ── Exams ──────────────────────────────────────────────────────────

  /// Get exam schedule from ZDBK.
  Future<Result<List<Map<String, dynamic>>>> getExams(
      HttpClient httpClient) async {
    // 缓存优先
    final cached = _tryFreshCache('zdbk_exams', CacheTtl.exams,
        (list) => list.cast<Map<String, dynamic>>());
    if (cached != null) return Ok(cached);

    return _withAutoRelogin(() async {
      final htmlResult = await _zdbkPost(httpClient,
          'https://zdbk.zju.edu.cn/jwglxt/xskscx/kscx_cxXsgrksIndex.html'
          '?doType=query&queryModel.showCount=5000');

      if (htmlResult.isErr) {
        final err = (htmlResult as Err<String>).error;
        if (err is AuthError) return Err(err);
        return Err(err);
      }
      final html = (htmlResult as Ok<String>).value;

      final items = HtmlParser.extractItems(html);
      if (items.isEmpty) {
        return Err(AppError.parseHtml(html, 'exam items'));
      }

      Log().debug('Exams parsed', data: {'count': items.length});
      _db.setCachedWebPage('zdbk_exams', jsonEncode(items));
      return Ok(items);
    }, fallbackKey: 'zdbk_exams');
  }

  // ── Course Offerings ───────────────────────────────────────────────

  /// Get course offerings (开课情况) from ZDBK.
  Future<Result<List<CourseOffering>>> getCourseOfferings(
    HttpClient httpClient, {
    int year = 2024,
    int semester = 12,
  }) async {
    Log().debug('getCourseOfferings', data: {'year': year, 'semester': semester});
    final cacheKey = 'zdbk_courseOfferings_${year}_$semester';

    // 缓存优先
    final cached = _tryFreshCache(cacheKey, CacheTtl.courseOfferings, (list) {
      final result = list
          .map((e) => CourseOffering.fromJson(e as Map<String, dynamic>))
          .toList();
      return result;
    });
    if (cached != null) return Ok(cached);

    return _withAutoRelogin(() async {
      final url =
          'https://zdbk.zju.edu.cn/jwglxt/jxzlpj/jszlpj_cxKkqkIndex.html'
          '?gnmkdm=N159035&doType=query';

      final zjuSemCode = semester == 3 ? '1' : '2';
      final semesterRange = '$year-${year + 1}$zjuSemCode';

      final queryUrl = '$url&tjksxq=$semesterRange&tjjsxq=$semesterRange'
          '&cxType=jxrw&queryModel.showCount=10000';
      final htmlResult = await _zdbkPost(httpClient, queryUrl);

      if (htmlResult.isErr) {
        final err = (htmlResult as Err<String>).error;
        if (err is AuthError) return Err(err);
        return Err(err);
      }
      final html = (htmlResult as Ok<String>).value;

      Map<String, dynamic> json;
      try {
        json = jsonDecode(html) as Map<String, dynamic>;
      } catch (e) {
        Log().warn('Course offerings: jsonDecode failed',
            error: e,
            data: {'preview': html.substring(0, min(html.length, 200))});
        return Err(AppError.parseJson(html, 'course offerings response'));
      }

      final items = json['items'] as List? ?? json['data'] as List? ?? [];
      Log().debug('Course offerings', data: {
        'count': items.length,
        'totalCount': json['totalCount'],
      });

      if (items.isEmpty) {
        return Ok(<CourseOffering>[]);
      }

      _db.setCachedWebPage(cacheKey, jsonEncode(items));

      try {
        final result = (items)
            .map((e) => CourseOffering.fromJson(e as Map<String, dynamic>))
            .toList();
        return Ok(result);
      } catch (e) {
        Log().error('Course offerings: model conversion failed', error: e);
        return Err(AppError.dataIntegrity(
            'zdbk/courseOfferings', 'items[*]', 'CourseOffering', e.toString()));
      }
    }, fallbackKey: cacheKey);
  }

  // ── Training Plans (培养方案) ──────────────────────────────────────

  /// 查询培养方案列表。
  Future<Result<List<Map<String, dynamic>>>> getTrainingPlans(
    HttpClient httpClient, {
    String query = '',
    int grade = 0, // 0 = 全部年级
  }) async {
    Log().debug('getTrainingPlans', data: {'query': query, 'grade': grade});

    // 缓存优先
    final cached = _tryFreshCache('zdbk_trainingPlans', CacheTtl.trainingPlans,
        (list) => list.cast<Map<String, dynamic>>());
    if (cached != null) return Ok(cached);

    return _withAutoRelogin(() async {
      // 先 GET 页面以建立该模块的会话
      try {
        final initReq = await httpClient
            .getUrl(Uri.parse(
                'https://zdbk.zju.edu.cn/jwglxt/pyfagl/pyfaxxcx_cxPyfaxscxIndex.html'
                '?gnmkdm=N153020&layout=default'))
            .timeout(const Duration(seconds: 10));
        _zdbkSetHeaders(initReq);
        if (_jSessionId != null) initReq.cookies.add(_jSessionId!);
        if (_route != null) initReq.cookies.add(_route!);
        initReq.followRedirects = true;
        final initRes = await initReq.close().timeout(const Duration(seconds: 10));
        await initRes.drain<List<int>>();
      } catch (_) {}

      // 然后 POST 查询数据（不传 nj 参数——API 不支持，年级筛选在客户端完成）
      const url =
          'https://zdbk.zju.edu.cn/jwglxt/pyfagl/pyfaxxcx_cxPyfaxscxIndex.html'
          '?gnmkdm=N153020&layout=default&doType=query&queryModel.showCount=5000';
      Log().debug('getTrainingPlans URL', data: {'url': url});
      final htmlResult = await _zdbkPost(httpClient, url);

      if (htmlResult.isErr) {
        return Err((htmlResult as Err<String>).error);
      }
      final html = (htmlResult as Ok<String>).value;

      if (html.isEmpty) {
        Log().warn('Training plans: empty response',
            data: {'grade': grade, 'url': url});
        return Ok(<Map<String, dynamic>>[]);
      }

      Log().debug('Training plans raw response',
          data: {'length': html.length, 'preview': html.length > 300 ? '${html.substring(0, 300)}...' : html});

      // 尝试 JSON 解析
      Map<String, dynamic>? json;
      try {
        json = jsonDecode(html) as Map<String, dynamic>;
      } catch (_) {
        // 不是 JSON，可能是 HTML → 尝试从 HTML 中提取表格数据
        Log().debug('Training plans: response is HTML, extracting items');
        final items = HtmlParser.extractItems(html);
        if (items.isNotEmpty) {
          _db.setCachedWebPage('zdbk_trainingPlans', jsonEncode(items));
          return Ok(items);
        }
        // 真的无法解析
        return Err(AppError.parseHtml(html, 'training plans response'));
      }

      final items = json['items'] as List? ?? json['data'] as List? ?? [];
      Log().debug('Training plans JSON', data: {'count': items.length});

      if (items.isEmpty) {
        return Ok(<Map<String, dynamic>>[]);
      }

      try {
        final result = items.cast<Map<String, dynamic>>();
        _db.setCachedWebPage('zdbk_trainingPlans', jsonEncode(items));
        return Ok(result);
      } catch (e) {
        Log().error('Training plans: data conversion failed', error: e);
        return Err(AppError.dataIntegrity(
            'zdbk/trainingPlans', 'items[*]', 'Map', e.toString()));
      }
    }, fallbackKey: 'zdbk_trainingPlans');
  }

  // ── Search Course Offerings ───────────────────────────────────────

  /// Search course offerings (RAG for Agent).
  Future<Result<List<CourseOffering>>> searchCourseOfferings(
    HttpClient httpClient, {
    required String query,
    int year = 2025,
    int semester = 12,
  }) async {
    Log().debug('searchCourseOfferings',
        data: {'query': query, 'year': year, 'semester': semester});

    return _withAutoRelogin(() async {
      final url =
          'https://zdbk.zju.edu.cn/jwglxt/jxzlpj/jszlpj_cxKkqkIndex.html'
          '?gnmkdm=N159035&doType=query';
      final zjuSemCode = semester == 3 ? '1' : '2';
      final semesterRange = '$year-${year + 1}$zjuSemCode';

      final queryUrl = '$url&tjksxq=$semesterRange&tjjsxq=$semesterRange'
          '&kcmc=${Uri.encodeComponent(query)}'
          '&cxType=jxrw&queryModel.showCount=50';
      final htmlResult = await _zdbkPost(httpClient, queryUrl);

      if (htmlResult.isErr) {
        final err = (htmlResult as Err<String>).error;
        if (err is AuthError) return Err(err);
        return Err(err);
      }
      final html = (htmlResult as Ok<String>).value;

      if (html.length < 10) {
        return Ok(<CourseOffering>[]);
      }

      Map<String, dynamic> json;
      try {
        json = jsonDecode(html) as Map<String, dynamic>;
      } catch (e) {
        return Ok(<CourseOffering>[]);
      }

      final items = json['items'] as List? ?? [];
      try {
        return Ok((items)
            .map((e) => CourseOffering.fromJson(e as Map<String, dynamic>))
            .toList());
      } catch (e) {
        return Err(AppError.dataIntegrity(
            'zdbk/searchCourseOfferings', 'items[*]', 'CourseOffering', e.toString()));
      }
    });
  }

  // ── Timetable ──────────────────────────────────────────────────────

  /// Get current semester timetable.
  Future<Result<List<TimetableSession>>> getTimetable(
    HttpClient httpClient, {
    int year = 2024,
    int semester = 12,
  }) async {
    Log().debug('getTimetable', data: {'year': year, 'semester': semester});
    final cacheKey = 'zdbk_Timetable${year}_$semester';

    // 缓存优先
    final cached = _tryFreshCache(cacheKey, CacheTtl.timetable, (list) {
      final filteredRaw = list
          .where((e) => (e as Map<String, dynamic>)['kcb'] != null &&
              e['sfyjskc'] != '1')
          .toList();
      if (filteredRaw.isEmpty) return null;
      return filteredRaw
          .map((e) => TimetableSession.fromZdbkJson(e as Map<String, dynamic>))
          .toList();
    });
    if (cached != null) return Ok(cached);

    return _withAutoRelogin(() async {
      final url = 'https://zdbk.zju.edu.cn/jwglxt/kbcx/xskbcx_cxXsKb.html';

      final request = await httpClient
          .postUrl(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      _zdbkSetHeaders(request);
      request.headers.contentType = ContentType(
          'application', 'x-www-form-urlencoded', charset: 'utf-8');
      if (_jSessionId != null) request.cookies.add(_jSessionId!);
      if (_route != null) request.cookies.add(_route!);
      request.followRedirects = false;
      request.add(utf8.encode('xnm=$year&xqm=$semester'));

      final response = await request.close().timeout(const Duration(seconds: 10));
      final responseText = await response.transform(utf8.decoder).join();

      // Check session expired
      if (HtmlParser.isSessionExpired(responseText)) {
        return Err(AppError.sessionExpired('ZDBK'));
      }

      if (responseText == 'null') {
        Log().debug('Timetable: null response — no courses');
        return Ok(<TimetableSession>[]);
      }

      final timetableJson =
          ZdbkPatterns.timetableKbList.firstMatch(responseText)?.group(0);

      if (timetableJson == null) {
        Log().warn('Timetable: cannot parse kbList',
            data: {
              'preview': responseText.substring(
                  0, min(responseText.length, 300))
            });
        return Err(AppError.parseHtml(responseText, 'kbList'));
      }

      try {
        final rawList = jsonDecode(timetableJson) as List<dynamic>;
        if (rawList.isNotEmpty) {
          final first = rawList.first as Map<String, dynamic>;
          Log().debug('Timetable raw keys',
              data: {'keys': first.keys.join(', ')});
        }
        final filteredRaw = rawList
            .where((e) => e['kcb'] != null && e['sfyjskc'] != '1')
            .toList();
        final sessions = filteredRaw
            .map((e) =>
                TimetableSession.fromZdbkJson(e as Map<String, dynamic>))
            .toList();

        _db.setCachedWebPage(cacheKey, jsonEncode(filteredRaw));

        Log().debug('Timetable parsed',
            data: {
              'sessions': sessions.length,
              'uniqueCourses':
                  sessions.map((s) => s.courseName).toSet().length,
            });
        return Ok(sessions);
      } catch (e) {
        Log().error('Timetable: model conversion failed', error: e);
        return Err(AppError.dataIntegrity(
            'zdbk/timetable', 'kbList[*]', 'TimetableSession', e.toString()));
      }
    }, fallbackKey: cacheKey);
  }

  // ── Practice Scores ────────────────────────────────────────────────

  /// Get practice scores (第二/三/四课堂).
  Future<Result<Map<String, double>>> getPracticeScores(
      HttpClient httpClient, String studentId) async {
    return _withAutoRelogin(() async {
      final request = await httpClient
          .getUrl(Uri.parse(
              'https://zdbk.zju.edu.cn/jwglxt/dessktgl/dessktcx_cxDessktcxIndex.html'
              '?gnmkdm=N108001&layout=default&su=$studentId'))
          .timeout(const Duration(seconds: 10));
      _zdbkSetHeaders(request);
      if (_jSessionId != null) request.cookies.add(_jSessionId!);
      if (_route != null) request.cookies.add(_route!);
      request.followRedirects = false;
      final response =
          await request.close().timeout(const Duration(seconds: 10));

      final html = await response.transform(utf8.decoder).join();
      if (HtmlParser.isSessionExpired(html)) {
        return Err(AppError.sessionExpired('ZDBK'));
      }

      _db.setCachedWebPage('zdbk_practiceScores', html);

      final scores = <String, double>{'pt2': 0.0, 'pt3': 0.0, 'pt4': 0.0};
      for (final match in ZdbkPatterns.practiceScoreRow.allMatches(html)) {
        final type = match.group(1)?.trim();
        final scoreStr = match.group(2)?.trim();
        if (type == null || scoreStr == null) continue;
        final score = double.tryParse(scoreStr);
        if (score == null) continue;
        if (type.contains('第二课堂')) scores['pt2'] = score;
        if (type.contains('第三课堂')) scores['pt3'] = score;
        if (type.contains('第四课堂')) scores['pt4'] = score;
      }

      return Ok(scores);
    }, fallbackKey: 'zdbk_practiceScores');
  }

  // ── Notifications ───────────────────────────────────────────────

  /// 获取 ZDBK 通知公告列表（含缓存 + 失败回退）。
  Future<Result<List<ZdbkNotification>>> getNotifications(
      HttpClient httpClient, String studentId) async {
    // 缓存优先
    final cached = _tryFreshCache('zdbk_notifications', CacheTtl.notifications,
        (list) => list
            .map((e) {
              final m = e as Map<String, dynamic>;
              return ZdbkNotification(
                id: '${m['id'] ?? ''}',
                title: '${m['title'] ?? ''}',
                publisher: m['publisher'] as String?,
                publishDate: m['publishDate'] as String?,
                content: m['content'] as String?,
              );
            })
            .toList());
    if (cached != null) return Ok(cached);

    return _withAutoRelogin(() async {
      final time = DateTime.now().millisecondsSinceEpoch.toString();
      final url = 'https://zdbk.zju.edu.cn/jwglxt/xtgl/index_cxTctxNews.html'
          '?time=$time&gnmkdm=index&su=$studentId';

      final request = await httpClient
          .postUrl(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      _zdbkSetHeaders(request);
      if (_jSessionId != null) request.cookies.add(_jSessionId!);
      if (_route != null) request.cookies.add(_route!);
      request.followRedirects = true;
      final response =
          await request.close().timeout(const Duration(seconds: 10));
      final rawHtml = await response.transform(utf8.decoder).join();

      if (rawHtml.trim().isEmpty) return Ok(<ZdbkNotification>[]);

      final notifications = parseZdbkNotifications(rawHtml);
      // 缓存（序列化为简单 JSON 列表）
      _db.setCachedWebPage('zdbk_notifications',
          jsonEncode(notifications.map((n) => {
            'id': n.id, 'title': n.title, 'publisher': n.publisher,
            'publishDate': n.publishDate, 'content': n.content,
          }).toList()));
      return Ok(notifications);
    }, fallbackKey: 'zdbk_notifications');
  }

  // ── Everything (orchestration) ─────────────────────────────────────

  /// Get everything (grades + exams + GPA).
  ///
  /// If [getTranscript] fails and no cache fallback is available, the error
  /// is propagated so the caller can fall back to its own cache rather than
  /// displaying empty data.  Partial success (exams OK but transcript failed)
  /// still returns [Ok] with empty grades — the caller decides how to handle it.
  Future<Result<EverythingResult>> getEverything(
      HttpClient httpClient) async {
    final results = await Future.wait([
      getTranscript(httpClient),
      getExams(httpClient),
    ]);

    final transcriptResult = results[0] as Result<List<Grade>>;
    final examsResult = results[1] as Result<List<Map<String, dynamic>>>;

    // Both failed → propagate the transcript error (most critical data source)
    if (transcriptResult.isErr && examsResult.isErr) {
      Log().warn('ZDBK getEverything: both transcript and exams fetch failed');
      return Err((transcriptResult as Err<List<Grade>>).error);
    }

    // Transcript failed but exams succeeded → warn, proceed with empty grades
    if (transcriptResult.isErr) {
      Log().warn('ZDBK getEverything: transcript fetch failed, grades will be empty');
    }

    final grades = transcriptResult.fold(
      (g) => g,
      (_) => <Grade>[],
    );
    final exams = examsResult.fold(
      (e) => e,
      (_) => <Map<String, dynamic>>[],
    );

    final domesticGpa =
        GpaCalculator.calculateGpa(GpaCalculator.pickFirstAttempt(grades));
    final abroadGpa =
        GpaCalculator.calculateGpa(GpaCalculator.pickHighestAttempt(grades));

    return Ok(EverythingResult(
      grades: grades,
      exams: exams,
      domesticGpa: domesticGpa,
      abroadGpa: abroadGpa,
    ));
  }

  // ── Internal helpers ───────────────────────────────────────────────

  /// POST to ZDBK, returning [Result<String>] with the response body.
  /// Session expiry is NOT checked here — callers use [_checkSession].
  Future<Result<String>> _zdbkPost(HttpClient httpClient, String url) async {
    try {
      final request = await httpClient
          .postUrl(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      _zdbkSetHeaders(request);
      if (_jSessionId != null) request.cookies.add(_jSessionId!);
      if (_route != null) request.cookies.add(_route!);
      request.followRedirects = false;
      final response =
          await request.close().timeout(const Duration(seconds: 10));

      final body = await response.transform(utf8.decoder).join();

      // Check session expiry inline
      if (HtmlParser.isSessionExpired(body)) {
        return Err(AppError.sessionExpired('ZDBK'));
      }

      return Ok(body);
    } on SocketException catch (e) {
      Log().warn('ZDBK POST: network error', error: e, data: {'url': url});
      return Err(AppError.networkUnreachable(url));
    } on TimeoutException {
      Log().warn('ZDBK POST: timeout', data: {'url': url});
      return Err(AppError.timeout(10, url));
    } catch (e, stack) {
      Log().error('ZDBK POST: unexpected error',
          error: e, stack: stack, data: {'url': url});
      return Err(AppError.unknown(e));
    }
  }

  /// POST with URL-encoded form body.
  Future<Result<String>> _zdbkPostWithBody(
      HttpClient httpClient, String url, Map<String, String> formData) async {
    try {
      final request = await httpClient
          .postUrl(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      _zdbkSetHeaders(request);
      request.headers.contentType = ContentType(
          'application', 'x-www-form-urlencoded', charset: 'utf-8');
      if (_jSessionId != null) request.cookies.add(_jSessionId!);
      if (_route != null) request.cookies.add(_route!);
      request.followRedirects = false;
      request.add(utf8.encode(formData.entries
          .map((e) =>
              '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
          .join('&')));
      final response =
          await request.close().timeout(const Duration(seconds: 10));
      final body = await response.transform(utf8.decoder).join();

      if (HtmlParser.isSessionExpired(body)) {
        return Err(AppError.sessionExpired('ZDBK'));
      }

      return Ok(body);
    } on SocketException catch (e) {
      return Err(AppError.networkUnreachable(url));
    } on TimeoutException {
      return Err(AppError.timeout(10, url));
    } catch (e, stack) {
      Log().error('ZDBK POST (body): unexpected error',
          error: e, stack: stack, data: {'url': url});
      return Err(AppError.unknown(e));
    }
  }

  /// 下载培养方案 PDF，返回本地文件路径。
  Future<Result<String>> downloadPlanPdf(
    HttpClient httpClient,
    String planNo,
  ) async {
    return _withAutoRelogin(() async {
      final url =
          'https://zdbk.zju.edu.cn/jwglxt/pyfagl/pyfayl_cxPyfaylPdf.html'
          '?id=$planNo&doType=query';

      // 直接 GET（不用 _zdbkPost，其 utf8 解码会损坏 PDF）
      final request = await httpClient
          .getUrl(Uri.parse(url))
          .timeout(const Duration(seconds: 30));
      _zdbkSetHeaders(request);
      request.headers.set('Accept', 'application/pdf,*/*');
      if (_jSessionId != null) request.cookies.add(_jSessionId!);
      if (_route != null) request.cookies.add(_route!);
      request.followRedirects = true;
      final response =
          await request.close().timeout(const Duration(seconds: 30));
      final bytes = await consolidateHttpClientResponseBytes(response);

      if (bytes.isEmpty) {
        return Err(AppError.downloadFailed(url, reason: '空响应'));
      }
      // 检查是否是真正的 PDF（%PDF 文件头）
      if (bytes.length < 4 || bytes[0] != 0x25 || bytes[1] != 0x50 ||
          bytes[2] != 0x44 || bytes[3] != 0x46) {
        return Err(AppError.downloadFailed(url, reason: '响应不是 PDF（可能需登录）'));
      }

      final tmpFile = File(
          '${Directory.systemTemp.path}${Platform.pathSeparator}pyfa_$planNo.pdf');
      await tmpFile.writeAsBytes(bytes);
      return Ok(tmpFile.path);
    });
  }

  /// Set standard ZDBK request headers.
  void _zdbkSetHeaders(HttpClientRequest request) {
    request.headers
      ..add('Referer',
          'https://zdbk.zju.edu.cn/jwglxt/xtgl/index_initMenu.html')
      ..set('Connection', 'close')
      ..add('User-Agent',
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36')
      ..add('Accept', 'application/json, text/javascript, */*; q=0.01')
      ..add('X-Requested-With', 'XMLHttpRequest');
  }

  /// 缓存优先：若 [key] 对应的文件缓存未过期，解析并返回；否则返回 null。
  ///
  /// [parser] 负责将 `List<dynamic>` 反序列化为目标类型 [T]。
  /// 返回 null 表示缓存中无有效数据，应发起网络请求。
  T? _tryFreshCache<T>(String key, Duration ttl, T? Function(List<dynamic> list) parser) {
    final raw = _db.getFreshCachedWebPage(key, ttl);
    if (raw == null) return null;
    try {
      return parser(jsonDecode(raw) as List<dynamic>);
    } catch (_) {
      return null; // 解析失败 → 走网络
    }
  }

  /// Execute an action with auto-relogin on session expiry.
  ///
  /// The action returns [Result<T>]. If it's an [AuthError] (session expired),
  /// this method triggers re-login and retries. Falls back to cached data
  /// on network errors if [fallbackKey] is set.
  Future<Result<T>> _withAutoRelogin<T>(
    Future<Result<T>> Function() action, {
    String? fallbackKey,
  }) async {
    for (var i = 0; i < _maxReloginAttempts; i++) {
      try {
        if (_jSessionId == null || _route == null) {
          await _relogin();
        }
        final result = await action();
        if (result.isOk) return result;

        // Check if the error is session-related → retry
        final err = (result as Err<T>).error;
        if (err is AuthError) {
          Log().info('ZDBK session expired, re-logging in (attempt ${i + 1})');
          await _relogin();
          continue;
        }

        // Other errors — try cache fallback
        if (fallbackKey != null) {
          final cached = _db.getCachedList(fallbackKey);
          if (cached.isNotEmpty) {
            Log().info('ZDBK: using cached data for $fallbackKey',
                data: {'count': cached.length});
            try {
              return Ok(cached.cast<Map<String, dynamic>>()) as Result<T>;
            } catch (_) {
              // Cache type mismatch — fall through to return original error
            }
          }
        }
        return result;
      } catch (e) {
        // Unexpected exception from _relogin() itself
        Log().error('ZDBK _withAutoRelogin: unexpected exception',
            error: e);
        if (i < _maxReloginAttempts - 1) {
          await _relogin();
          continue;
        }
        return Err(AppError.unknown(e)
          ..recoveryHint = '请稍后重试，或尝试重新登录');
      }
    }
    return Err(AppError.sessionExpired('ZDBK')
      ..recoveryHint = '会话已过期且自动重登失败，请尝试重新登录');
  }

  Future<void> _relogin() async {
    if (_iPlanetDirectoryPro == null || _httpClient == null) {
      throw Exception('会话已过期，请重新登录');
    }
    final ok = await login(_httpClient!, _iPlanetDirectoryPro!);
    if (!ok) {
      throw Exception('ZDBK 自动重登失败');
    }
  }

  bool get isLoggedIn => _jSessionId != null && _route != null;

  void logout() {
    _jSessionId = null;
    _route = null;
  }
}

// ── Domain result types (kept for multi-value returns) ──────────────

class MajorGradesResult {
  final List<Grade> grades;
  final GpaResult gpa;

  const MajorGradesResult({required this.grades, required this.gpa});
}

class EverythingResult {
  final List<Grade> grades;
  final List<Map<String, dynamic>> exams;
  final GpaResult domesticGpa;
  final GpaResult abroadGpa;

  const EverythingResult({
    required this.grades,
    required this.exams,
    required this.domesticGpa,
    required this.abroadGpa,
  });
}
