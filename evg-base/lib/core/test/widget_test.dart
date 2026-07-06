/// Core 根级模块验证测试——确保 errors / log / result 编译通过且行为正确。
library;

import 'package:test/test.dart';

import '../errors.dart';
import '../result.dart';

void main() {
  group('AppError', () {
    test('NetworkError factory 产生正确类型', () {
      final e = AppError.networkUnreachable('http://example.com');
      expect(e, isA<NetworkError>());
      expect(e.userMessage, '无法连接到服务器');
      expect((e as NetworkError).requestUrl, 'http://example.com');
    });

    test('AuthError factory 产生正确类型', () {
      final e = AppError.authFailed('密码错误');
      expect(e, isA<AuthError>());
      expect(e.userMessage, '登录失败：密码错误');
    });

    test('ParseError factory 产生正确类型', () {
      final e = AppError.parseJson('{"x":1}', 'name');
      expect(e, isA<ParseError>());
      expect(e.userMessage, '数据格式异常');
    });

    test('TimeoutError factory 产生正确类型', () {
      final e = AppError.timeout(30, 'http://slow.com') as TimeoutError;
      expect(e.timeoutSeconds, 30);
    });

    test('CacheError factory 产生正确类型', () {
      final e = AppError.cacheMiss('user_data') as CacheError;
      expect(e.cacheKey, 'user_data');
    });

    test('ValidationError factory 产生正确类型', () {
      final e = AppError.validationError('用户名不能为空');
      expect(e.userMessage, '用户名不能为空');
    });

    test('ConfigError factory 产生正确类型', () {
      final e = AppError.configMissing('API_KEY') as ConfigError;
      expect(e.configKey, 'API_KEY');
    });

    test('FileError factory 产生正确类型', () {
      final e = AppError.fileError('/tmp/test.txt', 'read') as FileError;
      expect(e.filePath, '/tmp/test.txt');
    });

    test('AiModelError factory 产生正确类型', () {
      final e = AppError.aiModelError('deepseek-chat', 429);
      expect(e.userMessage, 'AI 服务繁忙，请稍后重试');
    });

    test('ContextExceededError factory 产生正确类型', () {
      final e = AppError.contextExceeded('deepseek-chat', 70000, 65536) as ContextExceededError;
      expect(e.currentTokens, 70000);
      expect(e.maxTokens, 65536);
    });

    test('MediaError factory 产生正确类型', () {
      final e = AppError.mediaFailed('video', 'http://vid.mp4') as MediaError;
      expect(e.mediaType, 'video');
    });

    test('RenderError factory 产生正确类型', () {
      final e = AppError.renderError('ScoreBoard', 'score', 'null value');
      expect(e, isA<RenderError>());
      expect(e.userMessage, '界面显示异常');
    });

    test('UnknownError factory 产生正确类型', () {
      final e = AppError.unknown(Exception('boom'));
      expect(e, isA<UnknownError>());
      expect(e.userMessage, '发生了未知错误');
    });

    test('AppError.toString 返回 runtimeType + userMessage', () {
      final e = AppError.cacheMiss('key');
      expect(e.toString(), contains('CacheError'));
      expect(e.toString(), contains('本地缓存不可用'));
    });

    test('recoveryHint 可设置', () {
      final e = AppError.timeout(10, 'http://x.com');
      expect(e.recoveryHint, isNotNull);
      e.recoveryHint = 'custom hint';
      expect(e.recoveryHint, 'custom hint');
    });

    test('AppError 继承 Exception', () {
      expect(AppError.cacheMiss('x'), isA<Exception>());
    });
  });

  group('Result<T>', () {
    test('Ok.isOk 为 true', () {
      const result = Ok(42);
      expect(result.isOk, isTrue);
      expect(result.isErr, isFalse);
    });

    test('Err.isErr 为 true', () {
      final result = Err<int>(AppError.cacheMiss('x'));
      expect(result.isErr, isTrue);
      expect(result.isOk, isFalse);
    });

    test('Ok.unwrap 返回值', () {
      expect(const Ok('hello').unwrap(), 'hello');
    });

    test('Err.unwrap 抛出异常', () {
      final result = Err<String>(AppError.cacheMiss('x'));
      expect(() => result.unwrap(), throwsA(isA<AppError>()));
    });

    test('Ok.unwrapOr 返回值', () {
      expect(const Ok('hello').unwrapOr('default'), 'hello');
    });

    test('Err.unwrapOr 返回默认值', () {
      final result = Err<String>(AppError.cacheMiss('x'));
      expect(result.unwrapOr('default'), 'default');
    });

    test('map 转换 Ok 值', () {
      final result = const Ok(42).map((v) => v.toString());
      expect(result.unwrap(), '42');
    });

    test('map 在 Err 上透传', () {
      final result = Err<int>(AppError.cacheMiss('x')).map((v) => v.toString());
      expect(result.isErr, isTrue);
    });

    test('flatMap 链式调用 Ok', () {
      final result = const Ok(2)
          .flatMap((v) => Ok(v * 3))
          .flatMap((v) => Ok(v + 1));
      expect(result.unwrap(), 7);
    });

    test('flatMap 在 Err 上短路', () {
      final result = const Ok(2)
          .flatMap<int>((_) => Err<int>(AppError.cacheMiss('x')))
          .flatMap((v) => Ok(v + 1));
      expect(result.isErr, isTrue);
    });

    test('fold 分支 Ok', () {
      final result = const Ok(42).fold(
        (v) => 'got $v',
        (e) => 'error',
      );
      expect(result, 'got 42');
    });

    test('fold 分支 Err', () {
      final result = Err<int>(AppError.cacheMiss('x')).fold(
        (v) => 'got $v',
        (e) => 'err: ${e.userMessage}',
      );
      expect(result, 'err: 本地缓存不可用');
    });

    test('Ok == 比较', () {
      expect(const Ok(1), const Ok(1));
      expect(const Ok('a'), isNot(const Ok('b')));
    });

    test('Err == 比较', () {
      final e1 = Err<int>(AppError.cacheMiss('x'));
      final e2 = Err<int>(AppError.cacheMiss('x'));
      expect(e1, isNot(e2)); // AppError 未重载 ==，不同实例不等
    });

    test('Ok.toString 格式', () {
      expect(const Ok(42).toString(), 'Ok(42)');
    });

    test('Err.toString 格式', () {
      final e = AppError.cacheMiss('key');
      final result = Err<int>(e);
      expect(result.toString(), contains('Err('));
    });
  });
}
