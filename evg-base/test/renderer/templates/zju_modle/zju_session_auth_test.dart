// zju fetcher 会话自动重登（AuthInterceptor）链路测试——纯离线，不触网。
//
// 背景（2026-08-13 运行时日志）：`ensureZjuSession` 的 Dio 此前只挂
// CookieManager，SSO 会话过期时：
//   - education.cmc.zju.edu.cn 直接回 401/403 → classroom_service 报
//     「课程列表无权限——SSO 会话可能已过期，请重新登录」
// 参考实现（cp_evergreen_push）在 Dio 上挂 AuthInterceptor（会话过期 →
// onRelogin → 原请求重放）+ RetryInterceptor。本测试锁定该契约：
//   1. 901/401/403 触发 onRelogin 并重放成功
//   2. 非会话错误（500）不触发重登
//   3. ZjuClassroomService 经拦截器自动恢复
//
// 注（B4-fix）：ZDBK 已改 HttpClient 手动两步 cookie 版（对齐参考实现），
// 不再经过 Dio 拦截器——其会话过期由 service 内部 `_withAutoRelogin` 处理，
// 故此处不再包含 ZDBK 的 Dio 拦截器测试。
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:evergreen_base/renderer/templates/zju_modle/classroom/services/classroom_service.dart';
import 'package:evergreen_base/renderer/templates/zju_modle/zju_auth/auth_interceptor.dart';
import 'package:evergreen_base/renderer/templates/zju_modle/zju_auth/zju_session.dart';
import 'package:flutter_test/flutter_test.dart';

/// 按序返回预置状态码的 adapter：首次 901/401 → 重放后 200。
class _SequenceAdapter implements HttpClientAdapter {
  _SequenceAdapter(this.statuses);

  final List<int> statuses;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final i = calls++;
    final code = statuses[i % statuses.length];
    return ResponseBody.fromString(
      _bodyFor(code),
      code,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  static String _bodyFor(int code) {
    // 必须返回合法 JSON：Dio 默认 responseType=json，会在状态码校验前先
    // decode body；非法 JSON → FormatException 包成 DioException(unknown)，
    // err.response 丢失导致状态码判空，拦截器无法识别会话过期。
    if (code == 200) return '{"items":[],"params":{"result":{"data":[]}}}';
    return '{"error":"session expired"}';
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late Directory tmp;
  late PersistCookieJar jar;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('zju_auth_jar_test');
    jar = PersistCookieJar(storage: FileStorage('${tmp.path}/.cookies'));
  });

  tearDown(() async {
    // 静态全局回调，避免污染其他测试。
    AuthInterceptor.onRelogin = null;
    await tmp.delete(recursive: true);
  });

  group('AuthInterceptor 会话过期自动重登（对齐参考 dioClientProvider）', () {
    for (final code in [901, 401, 403]) {
      test('$code → 触发 onRelogin 并重放原请求成功', () async {
        final adapter = _SequenceAdapter([code, 200]);
        final dio = Dio()..httpClientAdapter = adapter;
        var relogins = 0;
        AuthInterceptor.onRelogin = () async {
          relogins++;
          return true;
        };
        dio.interceptors.add(AuthInterceptor(dio, jar));

        final res = await dio.get('/zdbk/query');
        expect(res.statusCode, 200);
        expect(relogins, 1, reason: '$code 应触发一次自动重登');
        expect(adapter.calls, 2, reason: '原请求应被重放一次');
      });
    }

    test('301/302 重定向仍触发重登（参考实现原有契约）', () async {
      final adapter = _SequenceAdapter([302, 200]);
      final dio = Dio()..httpClientAdapter = adapter;
      var relogins = 0;
      AuthInterceptor.onRelogin = () async {
        relogins++;
        return true;
      };
      dio.interceptors.add(AuthInterceptor(dio, jar));

      final res = await dio.get('/cas/login');
      expect(res.statusCode, 200);
      expect(relogins, 1);
    });

    test('非会话错误（500）不触发重登，错误原样透传', () async {
      final adapter = _SequenceAdapter([500]);
      final dio = Dio()..httpClientAdapter = adapter;
      var relogins = 0;
      AuthInterceptor.onRelogin = () async {
        relogins++;
        return true;
      };
      dio.interceptors.add(AuthInterceptor(dio, jar));

      await expectLater(dio.get('/x'), throwsA(isA<DioException>()));
      expect(relogins, 0);
      expect(adapter.calls, 1);
    });

    test('onRelogin 返回 false → 原错误透传，不重放', () async {
      final adapter = _SequenceAdapter([901]);
      final dio = Dio()..httpClientAdapter = adapter;
      var relogins = 0;
      AuthInterceptor.onRelogin = () async {
        relogins++;
        return false;
      };
      dio.interceptors.add(AuthInterceptor(dio, jar));

      await expectLater(dio.get('/x'), throwsA(isA<DioException>()));
      expect(relogins, 1);
      expect(adapter.calls, 1, reason: '重登失败不应重放');
    });
  });

  group('service 层经拦截器自动恢复（运行时 401/901 链路）', () {
    test('ZjuClassroomService.listCourses：401 → 自动重登 → 200 空列表', () async {
      final adapter = _SequenceAdapter([401, 200]);
      final dio = Dio()..httpClientAdapter = adapter;
      AuthInterceptor.onRelogin = () async => true;
      dio.interceptors.add(AuthInterceptor(dio, jar));

      final courses = await const ZjuClassroomService().listCourses(dio);
      expect(courses, isEmpty);
      expect(adapter.calls, 2);
    });

  });

  group('zjuVideoHttpHeaders 视频流鉴权头（media_kit 黑屏修复）', () {
    test('jar 有 CMC 域 cookie → 拼出 Cookie + Referer + UA', () async {
      // 写入 CMC 域会话 cookie（模拟 loginClassroom 后的 jar 状态）。
      final uri = Uri.parse('https://tgmedia.cmc.zju.edu.cn/');
      await jar.saveFromResponse(uri, [
        Cookie('SESSION_CMC', 'abc123')..domain = '.cmc.zju.edu.cn',
        Cookie('JSESSIONID', 'sess456')..domain = '.cmc.zju.edu.cn',
      ]);

      final headers = await zjuVideoHttpHeaders(jar: jar);

      expect(headers['Cookie'], isNotNull);
      expect(headers['Cookie'], contains('SESSION_CMC=abc123'));
      expect(headers['Cookie'], contains('JSESSIONID=sess456'));
      expect(headers['Referer'], 'https://classroom.zju.edu.cn/');
      expect(headers['User-Agent'], contains('Mozilla/5.0'));
    });

    test('空 jar → 返回空 Map（播放器按原样请求，UI 错误兜底）', () async {
      final headers = await zjuVideoHttpHeaders(jar: jar);
      expect(headers, isEmpty);
    });

    test('cookie 拼接不重复（多域命中同一 cookie 去重）', () async {
      // 同一 cookie 同时匹配 yjapi 与 tgmedia 两域时只出现一次。
      await jar.saveFromResponse(
        Uri.parse('https://yjapi.cmc.zju.edu.cn/'),
        [Cookie('iPlanetDirectoryPro', 'sso-v1')..domain = '.zju.edu.cn'],
      );
      final headers = await zjuVideoHttpHeaders(jar: jar);
      final cookie = headers['Cookie']!;
      expect('iPlanetDirectoryPro=sso-v1'.allMatches(cookie).length, 1,
          reason: '同一 cookie 跨域命中只应出现一次: $cookie');
    });
  });
}
