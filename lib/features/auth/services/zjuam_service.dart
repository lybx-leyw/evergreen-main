import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../../../core/result.dart';
import '../../../core/errors.dart';
import '../../../core/log.dart';
import '../../zdbk/services/zdbk_patterns.dart';

/// ZJU Unified Authentication — RSA login to zjuam.zju.edu.cn.
///
/// Uses dart:io HttpClient (not Dio) for precise control over cookies and
/// redirects, matching the Celechron reference implementation exactly.
///
/// Returns [Result<Cookie>] instead of custom [ZjuAmResult], integrating
/// with the unified error handling system. Each failure path returns a
/// typed [AppError] with a user-readable Chinese message.
class ZjuAmService {
  final HttpClient _client;

  ZjuAmService(this._client);

  /// Login to ZJU SSO with RSA-encrypted credentials.
  ///
  /// Returns [Ok] with the `iPlanetDirectoryPro` [Cookie] on success,
  /// or [Err] with a typed [AppError] on failure.
  Future<Result<Cookie>> login(String username, String password) async {
    Log().info('ZJUAM login attempt', data: {'username': username});

    try {
      // Step 1: GET /cas/login → execution token + session cookies
      final req1 = await _client
          .getUrl(_u('/cas/login'))
          .timeout(const Duration(seconds: 10));
      req1.followRedirects = false;
      final res1 = await req1.close().timeout(const Duration(seconds: 10));
      final body1 = await res1.transform(utf8.decoder).join();

      final execMatch =
          ZdbkPatterns.executionToken.firstMatch(body1);
      if (execMatch == null) {
        Log().warn('Failed to extract execution token',
            data: {'bodyPreview': body1.substring(0, min(body1.length, 200))});
        return Err(AppError.parseHtml(
          body1.substring(0, min(body1.length, 200)),
          'execution token',
        ));
      }
      final execution = execMatch.group(1)!;

      // Collect native Cookie objects from step 1 response
      final cookies = [...res1.cookies];

      // Step 2: GET /cas/v2/getPubKey → RSA keys (JSON)
      final req2 = await _client
          .getUrl(_u('/cas/v2/getPubKey'))
          .timeout(const Duration(seconds: 10));
      for (final c in cookies) {
        req2.cookies.add(c);
      }
      final res2 = await req2.close().timeout(const Duration(seconds: 10));
      final body2 = await res2.transform(utf8.decoder).join();

      Map<String, dynamic> pubKeyData;
      try {
        pubKeyData = jsonDecode(body2) as Map<String, dynamic>;
      } catch (e) {
        return Err(AppError.parseJson(
          body2.substring(0, min(body2.length, 200)),
          'RSA public key',
        ));
      }

      final modulus = pubKeyData['modulus']?.toString();
      final exponent = pubKeyData['exponent']?.toString();
      if (modulus == null || exponent == null) {
        return Err(AppError.parseJson(body2, 'modulus/exponent'));
      }

      // Accumulate cookies from step 2 response
      cookies.addAll(res2.cookies);

      // Step 3: RSA encrypt
      final pwdEnc = _rsaEncrypt(password, modulus, exponent);

      // Step 4: POST /cas/login → iPlanetDirectoryPro cookie
      final body =
          'username=${Uri.encodeComponent(username)}'
          '&password=${Uri.encodeComponent(pwdEnc)}'
          '&execution=${Uri.encodeComponent(execution)}'
          '&_eventId=submit'
          '&rememberMe=true';

      final req4 = await _client
          .postUrl(_u('/cas/login'))
          .timeout(const Duration(seconds: 10));
      req4.followRedirects = false;
      req4.headers.set('Content-Type', 'application/x-www-form-urlencoded');
      for (final c in cookies) {
        req4.cookies.add(c);
      }
      req4.write(body);
      final res4 = await req4.close().timeout(const Duration(seconds: 10));
      await res4.drain();

      // Extract iPlanetDirectoryPro using native Dart cookie parsing.
      try {
        final iPlanetCookie = res4.cookies.firstWhere(
          (c) => c.name == 'iPlanetDirectoryPro',
        );
        Log().info('ZJUAM login succeeded');
        return Ok(iPlanetCookie);
      } catch (_) {
        Log().warn('ZJUAM login: no iPlanetDirectoryPro cookie (wrong credentials?)');
        return Err(AppError.authFailed('学号或密码错误'));
      }

    } on SocketException catch (e) {
      Log().warn('ZJUAM unreachable', error: e);
      return Err(AppError.networkUnreachable('zjuam.zju.edu.cn'));

    } on TimeoutException {
      Log().warn('ZJUAM login timed out');
      return Err(AppError.timeout(10, 'zjuam.zju.edu.cn/cas/login')
        ..recoveryHint = '服务器响应较慢，请稍后重试');

    } catch (e, stack) {
      Log().error('Unexpected ZJUAM login error', error: e, stack: stack);
      return Err(AppError.unknown(e)
        ..recoveryHint = '请尝试重新登录，或联系开发者');
    }
  }

  Uri _u(String path) => Uri.parse('https://zjuam.zju.edu.cn$path');

  /// RSA encrypt: password → UTF-8 bytes → hex → BigInt.modPow → hex(128).
  String _rsaEncrypt(String plaintext, String modulusHex, String exponentHex) {
    final bytes = utf8.encode(plaintext);
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final mod = BigInt.parse(modulusHex, radix: 16);
    final exp = BigInt.parse(exponentHex, radix: 16);
    final pwd = BigInt.parse(hex, radix: 16);
    BigInt r = BigInt.one, b = pwd % mod, e = exp;
    while (e > BigInt.zero) {
      if (e.isOdd) r = (r * b) % mod;
      e >>= 1;
      b = (b * b) % mod;
    }
    return r.toRadixString(16).padLeft(128, '0');
  }
}
