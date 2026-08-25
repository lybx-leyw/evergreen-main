/// ZjuZdbkService — 教务管理系统（zdbk.zju.edu.cn）数据拉取服务。
///
/// B4-fix（2026-08-13）自参考工程 `cp_evergreen_push/lib/features/zdbk/services/
/// zdbk_service.dart` **完整对齐**：此前重写为共享 Dio + 自动重定向版，实测
/// 「所有数据拉取基本全挂」。根因：
/// 1. ZDBK 登录链必须用 HttpClient **手动两步**（CAS service validation →
///    跟随 Location 至 zdbk 域）换取 `JSESSIONID` + `route` cookie；
///    Dio 自动重定向无法保证跨域 Set-Cookie 正确收集/携带；
/// 2. 每个查询需手动携带 `_jSessionId`/`_route` 且带标准头
///    （Referer / X-Requested-With / Accept），Dio 版缺头被 ZDBK 拒。
///
/// 改造要点（相对参考）：
/// - 去掉 WebCacheDatabase 本地缓存层——数据链路由数据中枢（web_cache JSON +
///   TTL）统一接管，参考的 `_tryFreshCache` 不再需要；
/// - 去掉 Result 包装（fetcher 契约：直接返回数据或抛异常，中枢捕获置状态）；
/// - 解析逻辑提为 public static 方法（`parse*`），供无网络单测覆盖；
/// - 会话/网络逻辑（login / _zdbkPost / _zdbkSetHeaders / _withAutoRelogin /
///   _relogin）与参考实现逐行一致。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:evergreen_base/core/log.dart';

import '../../shared/models/zju_course_offering.dart';
import '../../shared/models/zju_grade.dart';
import '../../shared/models/zju_timetable_session.dart';
import '../../shared/models/zju_training_plan.dart';
import '../../shared/models/zju_zdbk_notification.dart';
import '../../zju_auth/html_parser.dart';
import '../../zju_auth/zdbk_patterns.dart';

/// ZDBK 会话异常——`_withAutoRelogin` 捕获后触发 CAS 重登；耗尽重登后上抛。
///
/// T9 起改为公开类型：`zju_session.dart` 的 SessionProvider.isSessionExpired
/// 需按此类型识别 zdbk fetcher 的「会话过期」错误（统一接入平台会话中心）。
class ZdbkAuthError implements Exception {
  final String message;
  const ZdbkAuthError(this.message);

  @override
  String toString() => 'ZdbkAuthError: $message';
}

/// 教务管理系统数据服务（有状态：持有 ZDBK 会话 cookie）。
///
/// 用法（参考 `zdbkProvider` 同款）：
/// ```dart
/// final service = await ensureZdbkSession(); // zju_auth，含 login
/// final grades = await service.getTranscript(service.httpClient);
/// ```
class ZjuZdbkService {
  Cookie? _jSessionId;
  Cookie? _route;
  Cookie? _iPlanetDirectoryPro;
  HttpClient? _httpClient;
  int _reloginAttempts = 0;
  static const int _maxReloginAttempts = 2;

  /// 会话是否已落地（JSESSIONID + route 齐备）。
  bool get isLoggedIn => _jSessionId != null && _route != null;

  /// 当前使用的 HttpClient（[login] 时注入，供 fetcher/UI 复用）。
  HttpClient? get httpClient => _httpClient;

  // ── Login ──────────────────────────────────────────────────────────

  /// 使用 SSO `iPlanetDirectoryPro` cookie 登录 ZDBK（参考 `login` 原样）。
  ///
  /// Step 1: GET CAS `/cas/login?service=<zdbk sso 落地页>` 拿 302 Location；
  /// Step 2: 跟随 Location 至 zdbk 域，收集 `JSESSIONID`（path=/jwglxt）与
  ///         `route` cookie。成功后 [isLoggedIn] = true。
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
        Log().warn('[zju-zdbk] login: no CAS redirect — cookie may be invalid');
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
        Log().warn('[zju-zdbk] login: no JSESSIONID cookie');
        return false;
      }

      try {
        _route = res2.cookies.firstWhere((c) => c.name == 'route');
      } catch (_) {
        Log().warn('[zju-zdbk] login: no route cookie');
        return false;
      }

      _reloginAttempts = 0;
      Log().info('[zju-zdbk] login succeeded');
      return true;
    } on SocketException catch (e) {
      Log().warn('[zju-zdbk] login: network error', error: e);
      return false;
    } on TimeoutException {
      Log().warn('[zju-zdbk] login: timeout');
      return false;
    }
  }

  // ── Transcript ─────────────────────────────────────────────────────

  /// 拉取全部学期成绩单 → [ZjuGrade] 列表（参考 `getTranscript` 同款 URL）。
  Future<List<ZjuGrade>> getTranscript(HttpClient httpClient) {
    return _withAutoRelogin(() async {
      final body = await _zdbkPost(httpClient,
          'https://zdbk.zju.edu.cn/jwglxt/cxdy/xscjcx_cxXscjIndex.html'
          '?doType=query&queryModel.showCount=5000');
      final grades = parseGrades(body, what: '成绩单');
      Log().info('[zju-zdbk] 成绩单拉取成功', data: {'count': grades.length});
      return grades;
    });
  }

  // ── Major Grade ────────────────────────────────────────────────────

  /// 拉取主修成绩（zycjtj）→ [ZjuGrade]（`major=true`，参考 `getMajorGrade`）。
  Future<List<ZjuGrade>> getMajorGrades(HttpClient httpClient) {
    return _withAutoRelogin(() async {
      final body = await _zdbkPost(httpClient,
          'https://zdbk.zju.edu.cn/jwglxt/zycjtj/xszgkc_cxXsZgkcIndex.html'
          '?doType=query&queryModel.showCount=5000');
      final grades = parseGrades(body, what: '主修成绩')
        ..forEach((g) => g.major = true);
      Log().info('[zju-zdbk] 主修成绩拉取成功', data: {'count': grades.length});
      return grades;
    });
  }

  // ── Exams ──────────────────────────────────────────────────────────

  /// 拉取考试安排 → 原始 JSON 项列表（参考 `getExams` 同款 URL）。
  Future<List<Map<String, dynamic>>> getExams(HttpClient httpClient) {
    return _withAutoRelogin(() async {
      final body = await _zdbkPost(httpClient,
          'https://zdbk.zju.edu.cn/jwglxt/xskscx/kscx_cxXsgrksIndex.html'
          '?doType=query&queryModel.showCount=5000');
      final items = parseItems(body, what: '考试安排');
      Log().info('[zju-zdbk] 考试安排拉取成功', data: {'count': items.length});
      return items;
    });
  }

  // ── Course Offerings ───────────────────────────────────────────────

  /// 拉取开课情况（jxzlpj）→ [ZjuCourseOffering]（参考 `getCourseOfferings`）。
  ///
  /// [year]/[semester] 为 ZJU 学期码（秋冬 3 / 春夏 12）；学期区间
  /// `$year-${year+1}{1|2}`（zjuSemCode：秋冬 1 / 春夏 2）。
  Future<List<ZjuCourseOffering>> getCourseOfferings(
    HttpClient httpClient, {
    required int year,
    required int semester,
  }) {
    return _withAutoRelogin(() async {
      final url = 'https://zdbk.zju.edu.cn/jwglxt/jxzlpj/jszlpj_cxKkqkIndex.html'
          '?gnmkdm=N159035&doType=query';
      final zjuSemCode = semester == 3 ? '1' : '2';
      final semesterRange = '$year-${year + 1}$zjuSemCode';
      final queryUrl = '$url&tjksxq=$semesterRange&tjjsxq=$semesterRange'
          '&cxType=jxrw&queryModel.showCount=10000';
      final body = await _zdbkPost(httpClient, queryUrl);

      final items = jsonItems(body, what: '开课情况');
      if (items.isEmpty) {
        Log().warn('[zju-zdbk] 开课情况为空',
            data: {'year': year, 'semester': semester});
        return <ZjuCourseOffering>[];
      }
      final offerings = items.map(ZjuCourseOffering.fromJson).toList();
      Log().info('[zju-zdbk] 开课情况拉取成功', data: {'count': offerings.length});
      return offerings;
    });
  }

  // ── Training Plans ─────────────────────────────────────────────────

  /// 拉取培养方案（pyfagl）→ [ZjuTrainingPlan]（参考 `getTrainingPlans`）。
  ///
  /// 与参考一致：先 GET 页面建立模块会话（失败忽略），POST 查询后优先解析
  /// JSON `items`，非 JSON 时回退 HTML `extractItems`。
  Future<List<ZjuTrainingPlan>> getTrainingPlans(HttpClient httpClient) {
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
      } catch (_) {
        // 参考实现：初始化 GET 失败不阻断后续 POST 查询。
      }

      const url =
          'https://zdbk.zju.edu.cn/jwglxt/pyfagl/pyfaxxcx_cxPyfaxscxIndex.html'
          '?gnmkdm=N153020&layout=default&doType=query&queryModel.showCount=5000';
      final body = await _zdbkPost(httpClient, url);
      if (body.trim().isEmpty) return <ZjuTrainingPlan>[];

      final plans = parsePlans(body);
      Log().info('[zju-zdbk] 培养方案拉取成功', data: {'count': plans.length});
      return plans;
    });
  }

  // ── Practice Scores ────────────────────────────────────────────────

  /// 拉取实践成绩（dessktgl，第二/三/四课堂）→ `{pt2, pt3, pt4}`。
  ///
  /// [studentId] 为学号（ZJU_USERNAME），拼接在查询 URL 的 `su` 参数。
  Future<Map<String, double>> getPracticeScores(
      HttpClient httpClient, String studentId) {
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
      _checkSession(html);

      final scores = parsePracticeScores(html);
      Log().info('[zju-zdbk] 实践成绩拉取成功', data: scores);
      return scores;
    });
  }

  // ── Notifications ──────────────────────────────────────────────────

  /// 拉取教务通知（xtgl）→ [ZjuZdbkNotification]。
  ///
  /// [studentId] 为学号（ZJU_USERNAME），拼接在查询 URL 的 `su` 参数。
  Future<List<ZjuZdbkNotification>> getNotifications(
      HttpClient httpClient, String studentId) {
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
      _checkSession(rawHtml);

      if (rawHtml.trim().isEmpty) return <ZjuZdbkNotification>[];
      final notifications = parseZjuZdbkNotifications(rawHtml);
      Log().info('[zju-zdbk] 教务通知拉取成功',
          data: {'count': notifications.length});
      return notifications;
    });
  }

  // ── Timetable ──────────────────────────────────────────────────────

  /// 拉取课表（kbcx）→ [ZjuTimetableSession]（参考 `getTimetable` 原样）。
  ///
  /// [year] 为教务学年起始年（如 2026 表示 2026-2027 学年），[semester] 为
  /// 教务学期码。注意：ZDBK **忽略 xqm 参数**，固定返回整个学年的课表
  /// （参考实现同款行为），UI 侧按 `ZjuTimetableSession.semester` 位掩码
  /// 过滤展示学期（春=1, 夏=2, 短①=4, 秋=8, 冬=16, 短②=32, 暑=64）。
  Future<List<ZjuTimetableSession>> getTimetable(
    HttpClient httpClient, {
    required int year,
    required int semester,
  }) {
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
      _checkSession(responseText);

      // 参考实现：`null` 响应 = 该学年无课程数据。
      if (responseText == 'null') {
        Log().info('[zju-zdbk] 课表空响应（null）——无课程');
        return <ZjuTimetableSession>[];
      }

      final sessions = parseTimetable(responseText);
      Log().info('[zju-zdbk] 课表拉取成功',
          data: {'count': sessions.length, 'year': year});
      return sessions;
    });
  }

  // ── Plan PDF ───────────────────────────────────────────────────────

  /// 下载培养方案 PDF，返回本地临时文件路径（参考 `downloadPlanPdf` 原样）。
  ///
  /// 直接 GET（不用 `_zdbkPost`——其 utf8 解码会损坏 PDF），校验 `%PDF`
  /// 文件头后写入系统临时目录 `pyfa_<planNo>.pdf`。
  Future<String> downloadPlanPdf(HttpClient httpClient, String planNo) {
    return _withAutoRelogin(() async {
      final url = 'https://zdbk.zju.edu.cn/jwglxt/pyfagl/pyfayl_cxPyfaylPdf.html'
          '?id=$planNo&doType=query';

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
        throw StateError('培养方案 PDF 下载失败：空响应');
      }
      // 校验 PDF 文件头（%PDF），非 PDF（如跳登录页）时给出可读错误。
      if (!isPdfBytes(bytes)) {
        Log().warn('[zju-zdbk] 培养方案 PDF 响应不是 PDF',
            data: {'planNo': planNo, 'bytes': bytes.length});
        throw StateError('培养方案 PDF 下载失败：响应不是 PDF（可能需登录）');
      }

      final tmpFile = File(
          '${Directory.systemTemp.path}${Platform.pathSeparator}pyfa_$planNo.pdf');
      await tmpFile.writeAsBytes(bytes, flush: true);
      Log().info('[zju-zdbk] 培养方案 PDF 下载完成',
          data: {'planNo': planNo, 'path': tmpFile.path, 'bytes': bytes.length});
      return tmpFile.path;
    });
  }

  // ── Internal helpers（与参考 `_zdbkPost` / `_zdbkSetHeaders` 一致）──────

  /// POST 到 ZDBK，返回响应体字符串；会话过期抛 [ZdbkAuthError]。
  Future<String> _zdbkPost(HttpClient httpClient, String url) async {
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
      _checkSession(body);
      return body;
    } on SocketException catch (e) {
      Log().warn('[zju-zdbk] POST: network error', error: e, data: {'url': url});
      throw StateError('无法连接教务网 zdbk.zju.edu.cn（可能不在校园网环境）');
    } on TimeoutException {
      Log().warn('[zju-zdbk] POST: timeout', data: {'url': url});
      throw StateError('教务网请求超时，请稍后重试');
    }
  }

  /// 标准 ZDBK 请求头（参考 `_zdbkSetHeaders` 原样）。
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

  /// 会话过期检测：命中 CAS 登录页 → 抛 [ZdbkAuthError]（触发自动重登）。
  void _checkSession(String body) {
    if (HtmlParser.isSessionExpired(body)) {
      throw const ZdbkAuthError('ZDBK 会话过期');
    }
  }

  /// 带自动重登的执行器（参考 `_withAutoRelogin` 逻辑，去 Result 包装）。
  ///
  /// `action` 抛 [ZdbkAuthError]（会话过期）→ CAS 重登后重试；最多
  /// [_maxReloginAttempts] 次。非会话错误直接上抛。
  Future<T> _withAutoRelogin<T>(Future<T> Function() action) async {
    for (var i = 0; i < _maxReloginAttempts; i++) {
      try {
        if (!isLoggedIn) {
          await _relogin();
        }
        return await action();
      } on ZdbkAuthError {
        if (i == _maxReloginAttempts - 1) {
          Log().warn('[zju-zdbk] 重登后仍会话失效');
          rethrow;
        }
        Log().info('[zju-zdbk] 会话过期，自动重登（第 ${i + 1} 次）');
        await _relogin();
      }
    }
    throw const ZdbkAuthError('ZDBK 会话已过期且自动重登失败');
  }

  Future<void> _relogin() async {
    final sso = _iPlanetDirectoryPro;
    final httpClient = _httpClient;
    if (sso == null || httpClient == null) {
      throw const ZdbkAuthError('ZDBK 会话未初始化，请先 login');
    }
    final ok = await login(httpClient, sso);
    if (!ok) {
      throw const ZdbkAuthError('ZDBK 自动重登失败');
    }
  }

  void logout() {
    _jSessionId = null;
    _route = null;
  }

  // ── Static 解析（无网络，供单测直接覆盖）─────────────────────────────

  /// 从 ZDBK HTML 提取 items 数组（正则三步：itemsWithLimit → itemsWithTotalResult）。
  static List<Map<String, dynamic>> parseItems(String html, {required String what}) {
    final items = HtmlParser.extractItems(html);
    if (items.isEmpty) {
      Log().warn('[zju-zdbk] $what解析为空',
          data: {'preview': _preview(html)});
      throw StateError('$what解析为空——教务页面结构可能已变更，请反馈');
    }
    return items;
  }

  /// 成绩单/主修成绩 HTML → [ZjuGrade]（过滤无 xkkh 的占位行）。
  static List<ZjuGrade> parseGrades(String html, {required String what}) {
    return parseItems(html, what: what)
        .where((e) => e['xkkh'] != null)
        .map(ZjuGrade.fromJson)
        .toList();
  }

  /// 从 JSON 响应体提取 items（`items` → `data` 回退，参考实现同款）。
  ///
  /// 非 JSON 或结构异常抛 [StateError]（调用方可回退 HTML 提取）。
  static List<Map<String, dynamic>> jsonItems(String body, {required String what}) {
    Map<String, dynamic> json;
    try {
      json = jsonDecode(body) as Map<String, dynamic>;
    } catch (e) {
      Log().warn('[zju-zdbk] $what 非 JSON 响应',
          data: {'error': e.toString(), 'preview': _preview(body)});
      throw StateError('$what响应解析失败——教务页面结构可能已变更，请反馈');
    }
    final items = (json['items'] as List?) ??
        (json['data'] as List?) ??
        const <dynamic>[];
    return items.whereType<Map<String, dynamic>>().toList();
  }

  /// 培养方案响应体（JSON 或 HTML）→ [ZjuTrainingPlan]。
  ///
  /// 优先 JSON `items`（照抄参考 `json['items'] ?? json['data']`），
  /// 非 JSON 时回退 HTML `extractItems`（参考同款降级）。
  static List<ZjuTrainingPlan> parsePlans(String body) {
    // 1. 优先 JSON `items`。
    try {
      final items = jsonItems(body, what: '培养方案');
      if (items.isEmpty) return <ZjuTrainingPlan>[];
      return items.map(ZjuTrainingPlan.fromJson).toList();
    } on StateError {
      // 2. 非 JSON → HTML 提取回退。
      final items = parseItems(body, what: '培养方案');
      return items.map(ZjuTrainingPlan.fromJson).toList();
    }
  }

  /// 实践成绩 HTML → `{pt2, pt3, pt4}`（正则 `practiceScoreRow`）。
  static Map<String, double> parsePracticeScores(String html) {
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
    return scores;
  }

  /// 课表响应体 → [ZjuTimetableSession]（kbList 正则提取 + 过滤已结束课程）。
  ///
  /// 响应含 kbList（正则 `ZdbkPatterns.timetableKbList` 提取），其中
  /// `sfyjskc=1`（已结束）与缺 `kcb` 的条目被过滤（参考实现同款）。
  static List<ZjuTimetableSession> parseTimetable(String body) {
    final json = ZdbkPatterns.timetableKbList.firstMatch(body)?.group(0);
    if (json == null) {
      Log().warn('[zju-zdbk] 课表 kbList 解析失败',
          data: {'preview': _preview(body)});
      throw StateError('课表解析为空——教务页面结构可能已变更，请反馈');
    }
    final rawList = jsonDecode(json) as List<dynamic>;
    final filteredRaw = rawList
        .where((e) => e is Map && e['kcb'] != null && e['sfyjskc'] != '1')
        .toList();
    return filteredRaw
        .map((e) =>
            ZjuTimetableSession.fromZdbkJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 校验 `%PDF` 文件头（下载防跳登录页）。
  static bool isPdfBytes(List<int> bytes) {
    return bytes.length >= 4 &&
        bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46;
  }

  static String _preview(String s, [int max = 200]) {
    final len = min(s.length, max);
    return s.length <= max ? s : '${s.substring(0, len)}…';
  }
}
