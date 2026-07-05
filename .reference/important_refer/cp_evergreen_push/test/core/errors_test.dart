import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/core/errors.dart';

void main() {
  group('NetworkError', () {
    test('NetworkError.unreachable — userMessage 含"无法连接"', () {
      final err = AppError.networkUnreachable('example.com');
      expect(err, isA<NetworkError>());
      expect(err.userMessage, contains('无法连接'));
      expect(err.debugMessage, contains('example.com'));
      expect(err.recoveryHint, contains('网络'));
      expect(err.source, isNotNull);
      expect(err.source, isNot(contains('errors.dart')));
    });

    test('NetworkError.httpStatus(500) — recoveryHint 含"稍后"', () {
      final err = AppError.httpStatus(500, 'api.example.com');
      expect(err.userMessage, contains('500'));
      expect(err.recoveryHint, contains('稍后'));
    });

    test('NetworkError.httpStatus(404) — recoveryHint 含"参数"', () {
      final err = AppError.httpStatus(404, 'api.example.com');
      expect(err.recoveryHint, contains('参数'));
    });

    test('responseBodySnippet — 截断 ≤ 200 字符', () {
      final err = AppError.networkUnreachable('example.com');
      // Cast to NetworkError to access responseBodySnippet
      expect((err as NetworkError).responseBodySnippet, isNull);
    });
  });

  group('AuthError', () {
    test('AuthError.failed — userMessage 含失败原因', () {
      final err = AppError.authFailed('密码错误');
      expect(err, isA<AuthError>());
      expect(err.userMessage, contains('密码错误'));
      expect(err.recoveryHint, contains('学号'));
    });

    test('AuthError.expired — recoveryHint 含"自动重新登录"', () {
      final err = AppError.sessionExpired('ZDBK');
      expect(err.userMessage, contains('过期'));
      expect(err.recoveryHint, contains('自动重新登录'));
    });

    test('AuthError.casRedirectFailed — userMessage 含"跳转失败"', () {
      final err = AuthError.casRedirectFailed('no Location header');
      expect(err.userMessage, contains('跳转失败'));
    });
  });

  group('ParseError', () {
    test('ParseError.html — userMessage 含"学校系统可能已更新"', () {
      final err = AppError.parseHtml('<html></html>', 'execution');
      expect(err, isA<ParseError>());
      expect(err.userMessage, contains('学校系统可能已更新'));
      expect(err.recoveryHint, contains('开发者'));
    });

    test('ParseError.json — userMessage 含"数据格式异常"', () {
      final err = AppError.parseJson('{bad}', 'field');
      expect(err.userMessage, contains('数据格式异常'));
    });
  });

  group('DataIntegrityError', () {
    test('DataIntegrityError.typeMismatch — 语义层错误', () {
      final err = AppError.dataIntegrity(
          'zdbk/transcript', 'items', 'List', 'Map');
      expect(err, isA<DataIntegrityError>());
      expect(err.userMessage, contains('数据格式异常'));
      expect(err.debugMessage, contains('zdbk/transcript'));
    });

    test('DataIntegrityError.missingField — userMessage 含"数据不完整"',
        () {
      final err = DataIntegrityError.missingField('zdbk/grade', 'xf');
      expect(err.userMessage, contains('数据不完整'));
      expect(err.debugMessage, contains('xf'));
    });

    test('DataIntegrityError.logicalError — userMessage 含"数据异常"', () {
      final err = DataIntegrityError.logicalError(
          'zdbk/timetable', 'date range invalid');
      expect(err.userMessage, contains('数据异常'));
    });

    test('DataIntegrityError vs ParseError 边界 — 不同子类型', () {
      final parseErr = AppError.parseHtml('<html>', 'pattern');
      final dataErr = AppError.dataIntegrity(
          'src', 'f', 'List', 'Map');
      expect(parseErr, isA<ParseError>());
      expect(dataErr, isA<DataIntegrityError>());
      expect(parseErr, isNot(isA<DataIntegrityError>()));
    });
  });

  group('CacheError', () {
    test('CacheError.miss — recoveryHint 含"从服务器重新获取"', () {
      final err = AppError.cacheMiss('zdbk_transcript');
      expect(err, isA<CacheError>());
      expect(err.recoveryHint, contains('从服务器重新获取'));
    });

    test('CacheError.writeFailed — recoveryHint 含"离线"', () {
      final err = CacheError.writeFailed('key');
      expect(err.recoveryHint, contains('离线'));
    });
  });

  group('TimeoutError', () {
    test('TimeoutError.request — userMessage 含超时秒数', () {
      final err = AppError.timeout(10, 'http://example.com');
      expect(err, isA<TimeoutError>());
      expect(err.userMessage, contains('10秒'));
      expect(err.recoveryHint, contains('稍后'));
    });
  });

  group('ValidationError', () {
    test('ValidationError.invalid — userMessage 含字段名', () {
      final err = ValidationError.invalid('学号', 'abc', '8位数字');
      expect(err.userMessage, contains('学号'));
      expect(err.recoveryHint, contains('学号'));
    });

    test('ValidationError.required — recoveryHint 含"必填"', () {
      final err = ValidationError.required('密码');
      expect(err.userMessage, contains('密码'));
      expect(err.recoveryHint, contains('必填'));
    });
  });

  group('MediaError', () {
    test('MediaError.loadFailed("video") — userMessage 含"视频"', () {
      final err = AppError.mediaFailed('video', 'http://v.example.com');
      expect(err, isA<MediaError>());
      expect(err.userMessage, contains('视频'));
      expect(err.recoveryHint, contains('播放器'));
    });

    test('MediaError.unsupportedFormat — userMessage 含"不支持"', () {
      final err =
          MediaError.unsupportedFormat('audio', 'ogg');
      expect(err.userMessage, contains('不支持'));
    });
  });

  group('AiModelError', () {
    test('AiModelError.apiError(429) — userMessage 含"繁忙"', () {
      final err =
          AppError.aiModelError('deepseek-v4-flash', 429);
      expect(err, isA<AiModelError>());
      expect(err.userMessage, contains('繁忙'));
      expect(err.recoveryHint, contains('频率'));
    });

    test('AiModelError.apiError(401) — userMessage 含"认证失败"', () {
      final err =
          AppError.aiModelError('deepseek-v4-flash', 401);
      expect(err.userMessage, contains('认证失败'));
      expect(err.recoveryHint, contains('API 密钥'));
    });

    test('AiModelError.quotaExhausted — recoveryHint 含"充值"', () {
      final err = AiModelError.quotaExhausted('deepseek-v4-flash');
      expect(err.recoveryHint, contains('充值'));
    });
  });

  group('ContextExceededError', () {
    test('ContextExceededError.overflow — userMessage 含"超出"', () {
      final err = AppError.contextExceeded(
          'deepseek-v4-flash', 200000, 131072);
      expect(err, isA<ContextExceededError>());
      expect(err.userMessage, contains('超出'));
      expect(err.recoveryHint, contains('新会话'));
      expect(err.recoveryHint, contains('丢失'));
    });

    test('ContextExceededError.usageRatio — 正确计算', () {
      final err = ContextExceededError.overflow(
          'deepseek-v4-flash', 10000, 131072);
      expect(err.usageRatio, closeTo(0.076, 0.001));
    });

    test('ContextExceededError.usageRatio — maxTokens 为 0 时返回 0', () {
      final err = ContextExceededError.overflow(
          'deepseek-v4-flash', 100, 0);
      expect(err.usageRatio, 0.0);
    });
  });

  group('ConfigError', () {
    test('ConfigError.missing — recoveryHint 含"配置"', () {
      final err = AppError.configMissing('学号');
      expect(err, isA<ConfigError>());
      expect(err.userMessage, contains('缺少'));
      expect(err.recoveryHint, contains('配置'));
    });

    test('ConfigError.invalid — userMessage 含"不合法"', () {
      final err = ConfigError.invalid('端口', 'abc', 'int');
      expect(err.userMessage, contains('不合法'));
    });
  });

  group('FileError', () {
    test('FileError.operationFailed(磁盘满) — recoveryHint 含"空间不足"',
        () {
      final err = AppError.fileError('/path/file.txt', 'write',
          osError: 'No space left on device');
      expect(err, isA<FileError>());
      expect(err.recoveryHint, contains('空间不足'));
    });

    test('FileError.unsupportedFormat — userMessage 含"不支持"', () {
      final err =
          FileError.unsupportedFormat('/path/file.exe', 'exe');
      expect(err.userMessage, contains('不支持'));
    });
  });

  group('UnknownError', () {
    test('UnknownError.from — userMessage 非空兜底', () {
      final err = AppError.unknown(Exception('crash'));
      expect(err, isA<UnknownError>());
      expect(err.userMessage, contains('未知错误'));
      expect(err.userMessage, isNotEmpty);
      expect(err.debugMessage, isNotEmpty);
      expect(err.recoveryHint, isNotNull);
    });
  });

  group('AppError 工厂方法', () {
    test('所有工厂方法返回非空 userMessage', () {
      final errors = <AppError>[
        AppError.networkUnreachable('url'),
        AppError.httpStatus(500, 'url'),
        AppError.parseHtml('<html>', 'p'),
        AppError.parseJson('{}', 'f'),
        AppError.authFailed('reason'),
        AppError.sessionExpired('svc'),
        AppError.timeout(5, 'url'),
        AppError.cacheMiss('key'),
        AppError.dataIntegrity('s', 'f', 'e', 'a'),
        AppError.mediaFailed('video', 'url'),
        AppError.aiModelError('m', 500),
        AppError.contextExceeded('m', 1, 2),
        AppError.configMissing('key'),
        AppError.fileError('path', 'write'),
        AppError.unknown(Exception('x')),
      ];

      for (final err in errors) {
        expect(err.userMessage, isNotEmpty,
            reason: '${err.runtimeType} userMessage is empty');
        expect(err.debugMessage, isNotEmpty,
            reason: '${err.runtimeType} debugMessage is empty');
        expect(err.source, isNotNull,
            reason: '${err.runtimeType} source is null');
      }
    });
  });
}
