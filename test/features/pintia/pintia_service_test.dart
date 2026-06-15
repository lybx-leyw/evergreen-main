import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/core/result.dart';
import 'package:evergreen_multi_tools/features/pintia/services/pintia_service.dart';
import '../../mocks/mock_dio.dart';

void main() {
  late Dio dio;
  late MockDioAdapter adapter;
  late PersistCookieJar jar;
  late PintiaService service;
  late Directory jarDir;

  setUp(() {
    (dio, adapter) = createMockDio();
    // 每个测试用独立 jar 存储路径，避免 cookie 跨测试干扰
    jarDir = Directory.systemTemp.createTempSync('pintia_test_');
    jar = PersistCookieJar(
      ignoreExpires: true,
      storage: FileStorage(jarDir.path),
    );
    service = PintiaService(dio, jar);
  });

  tearDown(() {
    // 忽略文件锁错误，临时目录会被系统清理
    try { jarDir.deleteSync(recursive: true); } catch (_) {}
  });

  group('PintiaService.login', () {
    test('成功 → Ok(true)', () async {
      adapter.stub(
        'https://passport.pintia.cn/api/users/sessions',
        MockResponse(body: {'cookie': 'PTASession=xxx'}, statusCode: 200),
      );

      final result = await service.login(
          phone: '+8618800000000', password: 'test123');

      expect(result.isOk, isTrue);
      expect(result.unwrap(), isTrue);
    });

    test('HTTP 200 无明确错误 → Ok(true)', () async {
      adapter.stub(
        'https://passport.pintia.cn/api/users/sessions',
        MockResponse(body: {}, statusCode: 200),
      );

      final result = await service.login(
          phone: '+8618800000000', password: 'test123');
      expect(result.isOk, isTrue);
    });

    test('401 → Err(AuthError)', () async {
      adapter.stubError(
        'https://passport.pintia.cn/api/users/sessions',
        DioException(
          requestOptions: RequestOptions(
              path: 'https://passport.pintia.cn/api/users/sessions'),
          response: Response(
            requestOptions: RequestOptions(
                path: 'https://passport.pintia.cn/api/users/sessions'),
            statusCode: 401,
            data: {'error': '密码错误'},
          ),
          type: DioExceptionType.badResponse,
        ),
      );

      final result = await service.login(
          phone: '+8618800000000', password: 'wrong');
      expect(result.isErr, isTrue);
    });

    test('验证码错误 → Err(可操作错误)', () async {
      adapter.stubError(
        'https://passport.pintia.cn/api/users/sessions',
        DioException(
          requestOptions: RequestOptions(
              path: 'https://passport.pintia.cn/api/users/sessions'),
          response: Response(
            requestOptions: RequestOptions(
                path: 'https://passport.pintia.cn/api/users/sessions'),
            statusCode: 400,
            data: {
              'error': {'code': 'GATEWAY_WRONG_CAPTCHA', 'message': 'Wrong Captcha'}
            },
          ),
          type: DioExceptionType.badResponse,
        ),
      );

      final result = await service.login(
          phone: '+8618800000000', password: 'test123');
      expect(result.isErr, isTrue);
      expect((result as Err<dynamic>).error.userMessage, contains('验证码'));
    });

    test('网络错误 → Err(NetworkError)', () async {
      adapter.stubError(
        'https://passport.pintia.cn/api/users/sessions',
        DioException(
          requestOptions: RequestOptions(
              path: 'https://passport.pintia.cn/api/users/sessions'),
          type: DioExceptionType.connectionError,
        ),
      );

      final result = await service.login(
          phone: '+8618800000000', password: 'test123');
      expect(result.isErr, isTrue);
    });

    test('缓存 session 有效时跳过登录', () async {
      // 预置有效 session
      await jar.saveFromResponse(
        Uri.parse('https://pintia.cn'),
        [Cookie('PTASession', 'valid-session')],
      );
      // getProblemSets 返回 200 → session 有效
      adapter.stub(
        'https://pintia.cn/api/problem-sets',
        MockResponse(body: {'problemSets': []}, statusCode: 200),
      );

      final result = await service.login(
          phone: '+8618800000000', password: 'test123');
      expect(result.isOk, isTrue);
    });
  });

  group('PintiaService.setSessionCookie', () {
    test('手动设置 PTASession cookie', () async {
      await service.setSessionCookie('manual-session-value');

      final cookies =
          await jar.loadForRequest(Uri.parse('https://pintia.cn'));
      expect(cookies.any((c) => c.name == 'PTASession'), isTrue);
      expect(cookies.firstWhere((c) => c.name == 'PTASession').value,
          'manual-session-value');
    });
  });

  group('PintiaService.getProblemSets', () {
    test('成功 → Ok(List)', () async {
      adapter.stub(
        'https://pintia.cn/api/problem-sets',
        MockResponse(body: {
          'problemSets': [
            {'id': 'ps-1', 'name': '数据结构'},
            {'id': 'ps-2', 'name': '操作系统'},
          ]
        }),
      );

      final result = await service.getProblemSets();
      expect(result.isOk, isTrue);
      expect(result.unwrap().length, 2);
    });

    test('空列表 → Ok(empty)', () async {
      adapter.stub(
        'https://pintia.cn/api/problem-sets',
        MockResponse(body: {'problemSets': []}),
      );

      final result = await service.getProblemSets();
      expect(result.unwrap(), isEmpty);
    });

    test('401 → Err', () async {
      adapter.stubError(
        'https://pintia.cn/api/problem-sets',
        DioException(
          requestOptions:
              RequestOptions(path: 'https://pintia.cn/api/problem-sets'),
          response: Response(
            requestOptions:
                RequestOptions(path: 'https://pintia.cn/api/problem-sets'),
            statusCode: 401,
          ),
          type: DioExceptionType.badResponse,
        ),
      );

      final result = await service.getProblemSets();
      expect(result.isErr, isTrue);
    });
  });

  group('PintiaService.getExams', () {
    test('成功 → Ok(List)', () async {
      adapter.stub(
        'https://pintia.cn/api/problem-sets/ps-1/exams',
        MockResponse(body: {
          'exams': [
            {'id': 'e1', 'title': '期中考试', 'endAt': '2025-06-20T14:00:00'},
            {'id': 'e2', 'title': '期末考试', 'endAt': '2025-07-15T10:00:00'},
          ]
        }),
      );

      final result = await service.getExams('ps-1');
      expect(result.isOk, isTrue);
      expect(result.unwrap().length, 2);
    });
  });

  group('PintiaService.getCachedSession', () {
    test('无缓存时返回 null', () async {
      final session = await service.getCachedSession();
      expect(session, isNull);
    });

    test('有缓存时返回 session 值', () async {
      await jar.saveFromResponse(
        Uri.parse('https://pintia.cn'),
        [Cookie('PTASession', 'cached-session-value')],
      );

      final session = await service.getCachedSession();
      expect(session, 'cached-session-value');
    });
  });
}
