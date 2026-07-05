import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';

import '../../../core/result.dart';
import '../../../core/errors.dart';
import '../../../core/log.dart';

/// PTA (Pintia/拼题A) API 服务——登录 + 获取题目集/成绩。
///
/// API 基址: `https://passport.pintia.cn/api`
/// 数据域: `https://pintia.cn/api`
///
/// Pintia 使用腾讯云验证码 (Tencent Cloud CAPTCHA)，自动登录无法绕过。
/// 策略：先检查已有的 PTASession cookie，有效则跳过登录；
/// 登录失败时提示用户手动在浏览器中登录后粘贴 session。
class PintiaService {
  final Dio _dio;
  final PersistCookieJar _cookieJar;

  PintiaService(this._dio, this._cookieJar);

  /// 从 cookie jar 读取已有的 PTASession 值（供外部检查）。
  Future<String?> getCachedSession() async {
    final cookies =
        await _cookieJar.loadForRequest(Uri.parse('https://pintia.cn'));
    for (final c in cookies) {
      if (c.name == 'PTASession' && c.value.isNotEmpty) {
        return c.value;
      }
    }
    return null;
  }

  /// 手动设置 PTASession cookie（用户从浏览器粘贴）。
  Future<void> setSessionCookie(String sessionValue) async {
    await _cookieJar.delete(Uri.parse('https://pintia.cn'));
    await _cookieJar.saveFromResponse(
      Uri.parse('https://pintia.cn'),
      [Cookie('PTASession', sessionValue)],
    );
    Log().info('Pintia session cookie manually set');
  }

  /// 验证当前 PTASession 是否有效。
  ///
  /// Pintia 无 session 时返回 HTTP 404 + `USER_NOT_FOUND`。
  /// 有效时返回 HTTP 200 + `problemSets` 列表。
  Future<bool> hasValidSession() async {
    final session = await getCachedSession();
    if (session == null) return false;
    try {
      final res = await _dio.get(
        'https://pintia.cn/api/problem-sets',
        options: Options(
          headers: {'Accept': 'application/json'},
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      // 必须检查响应体：200 + problemSets = 有效；404 + USER_NOT_FOUND = 无效
      final data = res.data;
      if (res.statusCode == 200 && data is Map) {
        return data['problemSets'] != null || data is List;
      }
      return false;
    } on DioException {
      return false;
    }
  }

  /// Pintia 无 session 时返回 HTTP 404（USER_NOT_FOUND）而非 401。
  bool _isSessionExpired(DioException e) {
    final code = e.response?.statusCode;
    return code == 401 || code == 404;
  }

  /// 使用手机号 + 密码登录。
  ///
  /// 先检查已有 PTASession，有效则跳过登录。
  /// 登录失败（含验证码错误）返回 [Err]。
  Future<Result<bool>> login({
    required String phone,
    required String password,
    bool rememberMe = false,
  }) async {
    // 先检查缓存 session
    final cached = await getCachedSession();
    if (cached != null) {
      final valid = await hasValidSession();
      if (valid) {
        Log().info('Pintia reuse cached session');
        return const Ok(true);
      }
    }

    Log().info('Pintia login attempt', data: {'phone': phone});

    try {
      final res = await _dio.post(
        'https://passport.pintia.cn/api/users/sessions',
        data: {
          'phone': phone,
          'password': password,
          'rememberMe': rememberMe,
        },
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
        ),
      );

      final data = res.data;
      if (data is Map && data['cookie'] != null) {
        Log().info('Pintia login success');
        return const Ok(true);
      }

      final error = data is Map ? data['error']?.toString() : null;
      if (error != null) {
        Log().warn('Pintia login failed', data: {'error': error});
        return Err(AppError.authFailed(error));
      }

      Log().info('Pintia login success (implicit)');
      return const Ok(true);

    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final body = e.response?.data;
      dynamic errBody = body is Map ? body['error'] : null;
      final code = errBody is Map ? errBody['code']?.toString() ?? '' : '';
      final msg = errBody is Map ? errBody['message']?.toString() ?? '' : errBody?.toString() ?? '';

      Log().warn('Pintia login error',
          error: e, data: {'status': status, 'code': code, 'body': msg});

      // 腾讯云验证码 — 需在浏览器中手动登录
      if (code == 'GATEWAY_WRONG_CAPTCHA') {
        return Err(AppError.authFailed(
          'PTA 需要验证码，请在浏览器中登录 https://pintia.cn 后，'
          '将 PTASession cookie 值粘贴到此处。',
        ));
      }

      if (status == 401 || status == 403) {
        return Err(AppError.authFailed('手机号或密码错误'));
      }
      if (status != null && status >= 500) {
        return Err(AppError.httpStatus(status, 'passport.pintia.cn'));
      }
      return Err(AppError.networkUnreachable('passport.pintia.cn'));
    } catch (e, stack) {
      Log().error('Pintia login unexpected error', error: e, stack: stack);
      return Err(AppError.unknown(e));
    }
  }

  /// 获取当前用户的题目集列表。
  Future<Result<List<Map<String, dynamic>>>> getProblemSets() async {
    try {
      final res = await _dio.get(
        'https://pintia.cn/api/problem-sets',
        options: Options(
          headers: {'Accept': 'application/json'},
          validateStatus: (s) => s != null && s < 500,
        ),
      );

      // 404 = USER_NOT_FOUND → session 无效
      if (res.statusCode == 404) {
        return Err(AppError.authFailed('PTA 未登录'));
      }
      final data = res.data;
      if (data is Map && data['problemSets'] is List) {
        return Ok((data['problemSets'] as List)
            .map((e) => e as Map<String, dynamic>)
            .toList());
      }
      if (data is List) {
        return Ok(data.cast<Map<String, dynamic>>());
      }

      return Ok(<Map<String, dynamic>>[]);
    } on DioException catch (e) {
      if (_isSessionExpired(e)) {
        return Err(AppError.authFailed('PTA 未登录'));
      }
      return Err(AppError.networkUnreachable('pintia.cn'));
    } catch (e, stack) {
      Log().error('Pintia getProblemSets error', error: e, stack: stack);
      return Err(AppError.unknown(e));
    }
  }

  /// 获取题目集内的考试/作业列表。
  Future<Result<List<Map<String, dynamic>>>> getExams(
      String problemSetId) async {
    try {
      final res = await _dio.get(
        'https://pintia.cn/api/problem-sets/$problemSetId/exams',
        options: Options(
          headers: {'Accept': 'application/json'},
        ),
      );

      final data = res.data;
      if (data is Map && data['exams'] is List) {
        return Ok((data['exams'] as List)
            .map((e) => e as Map<String, dynamic>)
            .toList());
      }
      if (data is List) {
        return Ok(data.cast<Map<String, dynamic>>());
      }

      return Ok(<Map<String, dynamic>>[]);
    } on DioException catch (e) {
      if (_isSessionExpired(e)) {
        return Err(AppError.authFailed('PTA 未登录'));
      }
      return Err(AppError.networkUnreachable('pintia.cn'));
    } catch (e, stack) {
      Log().error('Pintia getExams error', error: e, stack: stack);
      return Err(AppError.unknown(e));
    }
  }

  /// 获取某次考试的题目列表。
  Future<Result<List<Map<String, dynamic>>>> getProblems(
      String problemSetId, String examId) async {
    try {
      final res = await _dio.get(
        'https://pintia.cn/api/problem-sets/$problemSetId/exams/$examId',
        options: Options(
          headers: {'Accept': 'application/json'},
        ),
      );

      final data = res.data;
      if (data is Map) {
        final problems = data['problems'] ??
            data['problemList'] ??
            data['examProblems'] ??
            data['data'];
        if (problems is List) {
          return Ok(
              problems.map((e) => e as Map<String, dynamic>).toList());
        }
      }

      return Ok(<Map<String, dynamic>>[]);
    } on DioException catch (e) {
      if (_isSessionExpired(e)) {
        return Err(AppError.authFailed('PTA 未登录'));
      }
      return Err(AppError.networkUnreachable('pintia.cn'));
    } catch (e, stack) {
      Log().error('Pintia getProblems error', error: e, stack: stack);
      return Err(AppError.unknown(e));
    }
  }
}
