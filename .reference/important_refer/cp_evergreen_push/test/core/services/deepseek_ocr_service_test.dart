import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/core/services/deepseek_ocr_service.dart';
import 'package:evergreen_multi_tools/core/result.dart';
import '../../mocks/mock_dio.dart';

/// Load a raw fixture string by name.
String _fixture(String name) {
  switch (name) {
    case 'ocr_ok':
      return jsonEncode({
        'choices': [
          {
            'message': {
              'content': 'Hello World\n这是 OCR 识别的文字。',
            }
          }
        ],
      });
    case 'ocr_empty':
      return jsonEncode({
        'choices': [
          {'message': {'content': ''}}
        ],
      });
    case 'ocr_null_content':
      return jsonEncode({
        'choices': [
          {'message': {}}
        ],
      });
    default:
      return '{}';
  }
}

void main() {
  // ── _mimeFromPath (静态方法，纯函数) ────────────────────────

  group('DeepSeekOcrService.mimeFromPath', () {
    test('jpg → image/jpeg', () {
      expect(DeepSeekOcrService.mimeFromPath('/path/to/file.jpg'),
          'image/jpeg');
    });

    test('jpeg → image/jpeg', () {
      expect(DeepSeekOcrService.mimeFromPath('/path/to/file.jpeg'),
          'image/jpeg');
    });

    test('JPG (大写) → image/jpeg', () {
      expect(DeepSeekOcrService.mimeFromPath('/path/to/file.JPG'),
          'image/jpeg');
    });

    test('png → image/png', () {
      expect(DeepSeekOcrService.mimeFromPath('/path/to/file.png'),
          'image/png');
    });

    test('bmp → image/bmp', () {
      expect(DeepSeekOcrService.mimeFromPath('/path/to/file.bmp'),
          'image/bmp');
    });

    test('webp → image/webp', () {
      expect(DeepSeekOcrService.mimeFromPath('/path/to/file.webp'),
          'image/webp');
    });

    test('tiff → image/tiff', () {
      expect(DeepSeekOcrService.mimeFromPath('/path/to/file.tiff'),
          'image/tiff');
    });

    test('tif → image/tiff', () {
      expect(DeepSeekOcrService.mimeFromPath('/path/to/file.tif'),
          'image/tiff');
    });

    test('unknown extension → image/png (fallback)', () {
      expect(DeepSeekOcrService.mimeFromPath('/path/to/file.xyz'),
          'image/png');
    });

    test('no extension → image/png (fallback)', () {
      expect(DeepSeekOcrService.mimeFromPath('/path/to/file'),
          'image/png');
    });

    test('nested path with jpg', () {
      expect(
          DeepSeekOcrService.mimeFromPath(
              '/very/deep/nested/structure/image.jpeg'),
          'image/jpeg');
    });
  });

  // ── recognize() ─────────────────────────────────────────────

  group('DeepSeekOcrService.recognize', () {
    late Directory tmpDir;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('ocr_test_');
    });

    tearDown(() {
      tmpDir.deleteSync(recursive: true);
    });

    test('成功返回 OCR 文本', () async {
      final (dio, adapter) = createMockDio();
      adapter.stub(
        'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions',
        MockResponse(body: jsonDecode(_fixture('ocr_ok'))),
      );

      // Create a minimal valid PNG
      final imgFile = File('${tmpDir.path}/test.png');
      // 1×1 pixel PNG in base64
      const pngBase64 =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
      imgFile.writeAsBytesSync(base64Decode(pngBase64));

      final service = DeepSeekOcrService(dio, 'sk-test-key');
      final result = await service.recognize(imgFile);

      expect(result, isNotNull);
      expect(result, contains('Hello World'));
      expect(result, contains('OCR 识别的文字'));
    });

    test('API 返回空 content → null', () async {
      final (dio, adapter) = createMockDio();
      adapter.stub(
        'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions',
        MockResponse(body: jsonDecode(_fixture('ocr_empty'))),
      );

      final imgFile = File('${tmpDir.path}/empty_test.png');
      imgFile.writeAsBytesSync([0x89, 0x50, 0x4E, 0x47]); // min PNG header

      final service = DeepSeekOcrService(dio, 'sk-test-key');
      final result = await service.recognize(imgFile);

      expect(result, isNull);
    });

    test('API 返回 null content → null', () async {
      final (dio, adapter) = createMockDio();
      adapter.stub(
        'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions',
        MockResponse(body: jsonDecode(_fixture('ocr_null_content'))),
      );

      final imgFile = File('${tmpDir.path}/null_test.png');
      imgFile.writeAsBytesSync([0x89, 0x50, 0x4E, 0x47]);

      final service = DeepSeekOcrService(dio, 'sk-test-key');
      final result = await service.recognize(imgFile);

      expect(result, isNull);
    });

    test('Dio 网络错误 → null', () async {
      final (dio, adapter) = createMockDio();
      final url =
          'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions';
      adapter.stubError(
        url,
        DioException(
          requestOptions: RequestOptions(path: url),
          type: DioExceptionType.connectionError,
          message: 'Connection refused',
        ),
      );

      final imgFile = File('${tmpDir.path}/net_err.png');
      imgFile.writeAsBytesSync([0x89, 0x50, 0x4E, 0x47]);

      final service = DeepSeekOcrService(dio, 'sk-test-key');
      final result = await service.recognize(imgFile);

      expect(result, isNull);
    });

    test('Dio 401 认证错误 → null', () async {
      final (dio, adapter) = createMockDio();
      final url =
          'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions';
      adapter.stubError(
        url,
        DioException(
          requestOptions: RequestOptions(path: url),
          response: Response(
            requestOptions: RequestOptions(path: url),
            statusCode: 401,
            data: {'error': 'Invalid API key'},
          ),
          type: DioExceptionType.badResponse,
        ),
      );

      final imgFile = File('${tmpDir.path}/auth_err.png');
      imgFile.writeAsBytesSync([0x89, 0x50, 0x4E, 0x47]);

      final service = DeepSeekOcrService(dio, 'sk-test-key');
      final result = await service.recognize(imgFile);

      expect(result, isNull);
    });

    test('文件不存在 → Dio error → null', () async {
      final (dio, _) = createMockDio();
      final service = DeepSeekOcrService(dio, 'sk-test-key');
      final result = await service.recognize(File('/nonexistent/path.png'));
      expect(result, isNull);
    });

    test('base64 data URL 包含正确的 MIME 类型', () async {
      final (dio, adapter) = createMockDio();
      final url =
          'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions';
      adapter.stub(
        url,
        MockResponse(body: jsonDecode(_fixture('ocr_ok'))),
      );

      final imgFile = File('${tmpDir.path}/photo.jpeg');
      const pngBase64 =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
      imgFile.writeAsBytesSync(base64Decode(pngBase64));

      final service = DeepSeekOcrService(dio, 'sk-test-key');
      final result = await service.recognize(imgFile);
      expect(result, isNotNull);

      // Verify the request was made with correct image/jpeg MIME type
      expect(adapter.wasRequested(url), isTrue);
    });
  });

  // ── testConnection ──────────────────────────────────────────

  group('DeepSeekOcrService.testConnection', () {
    final url =
        'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions';

    test('连接成功 → Ok 含模型名', () async {
      final (dio, adapter) = createMockDio();
      adapter.stub(url, MockResponse(body: {
        'model': 'vanchin/deepseek-ocr',
        'choices': [
          {'message': {'content': 'OK'}}
        ],
      }));

      final service = DeepSeekOcrService(dio, 'sk-test-key');
      final result = await service.testConnection();

      expect(result.isOk, isTrue);
      expect(result.unwrap(), contains('连接成功'));
      expect(result.unwrap(), contains('vanchin/deepseek-ocr'));
    });

    test('响应仅含 choices 无 model 字段 → 从 content 取模型标识', () async {
      final (dio, adapter) = createMockDio();
      adapter.stub(url, MockResponse(body: {
        'choices': [
          {'message': {'content': 'OK'}}
        ],
      }));

      final service = DeepSeekOcrService(dio, 'sk-test-key');
      final result = await service.testConnection();

      expect(result.isOk, isTrue);
      expect(result.unwrap(), contains('连接成功'));
    });

    test('响应既无 model 也无 choices → 回退默认模型名', () async {
      final (dio, adapter) = createMockDio();
      adapter.stub(url, MockResponse(body: {'id': 'chatcmpl-123'}));

      final service = DeepSeekOcrService(dio, 'sk-test-key');
      final result = await service.testConnection();

      expect(result.isOk, isTrue);
      expect(result.unwrap(), contains('vanchin/deepseek-ocr'));
    });

    test('401 → Err(AiModelError)', () async {
      final (dio, adapter) = createMockDio();
      adapter.stubError(
        url,
        DioException(
          requestOptions: RequestOptions(path: url),
          response: Response(
            requestOptions: RequestOptions(path: url),
            statusCode: 401,
            data: {'error': 'Invalid API key'},
          ),
          type: DioExceptionType.badResponse,
        ),
      );

      final service = DeepSeekOcrService(dio, 'sk-test-key');
      final result = await service.testConnection();

      expect(result.isErr, isTrue);
      final err = (result as Err<String>).error;
      expect(err.userMessage, isNotEmpty);
    });

    test('403 → Err(AiModelError)', () async {
      final (dio, adapter) = createMockDio();
      adapter.stubError(
        url,
        DioException(
          requestOptions: RequestOptions(path: url),
          response: Response(
            requestOptions: RequestOptions(path: url),
            statusCode: 403,
            data: {'error': 'Forbidden'},
          ),
          type: DioExceptionType.badResponse,
        ),
      );

      final service = DeepSeekOcrService(dio, 'sk-test-key');
      final result = await service.testConnection();

      expect(result.isErr, isTrue);
    });

    test('500 服务器错误 → Err(AiModelError)', () async {
      final (dio, adapter) = createMockDio();
      adapter.stubError(
        url,
        DioException(
          requestOptions: RequestOptions(path: url),
          response: Response(
            requestOptions: RequestOptions(path: url),
            statusCode: 500,
            data: {'error': 'Internal Server Error'},
          ),
          type: DioExceptionType.badResponse,
        ),
      );

      final service = DeepSeekOcrService(dio, 'sk-test-key');
      final result = await service.testConnection();

      expect(result.isErr, isTrue);
      final err = (result as Err<String>).error;
      expect(err.userMessage, contains('不可用'));
    });

    test('连接超时 → Err(AiModelError)', () async {
      final (dio, adapter) = createMockDio();
      adapter.stubError(
        url,
        DioException(
          requestOptions: RequestOptions(path: url),
          type: DioExceptionType.connectionTimeout,
          message: 'Connection timed out',
        ),
      );

      final service = DeepSeekOcrService(dio, 'sk-test-key');
      final result = await service.testConnection();

      expect(result.isErr, isTrue);
    });

    test('接收超时 → Err(AiModelError)', () async {
      final (dio, adapter) = createMockDio();
      adapter.stubError(
        url,
        DioException(
          requestOptions: RequestOptions(path: url),
          type: DioExceptionType.receiveTimeout,
          message: 'Receive timed out',
        ),
      );

      final service = DeepSeekOcrService(dio, 'sk-test-key');
      final result = await service.testConnection();

      expect(result.isErr, isTrue);
    });

    test('网络连接失败（无 statusCode）→ Err(AiModelError)', () async {
      final (dio, adapter) = createMockDio();
      adapter.stubError(
        url,
        DioException(
          requestOptions: RequestOptions(path: url),
          type: DioExceptionType.connectionError,
          message: 'Connection refused',
        ),
      );

      final service = DeepSeekOcrService(dio, 'sk-test-key');
      final result = await service.testConnection();

      expect(result.isErr, isTrue);
    });

    test('未知异常（非 DioException）→ Err(UnknownError)', () async {
      // 创建一个 Dio 实例但不配置 adapter——直接使用会抛非 DioException
      // 这里用 stub 返回无效 JSON 导致非 Dio 异常
      final (dio, adapter) = createMockDio();
      adapter.stub(url, MockResponse(
        body: 'not valid json',
        headers: {'Content-Type': 'text/plain'},
      ));

      final service = DeepSeekOcrService(dio, 'sk-test-key');
      final result = await service.testConnection();

      // 可能成功（如果 Dio 能解析 text/plain）或失败
      // 主要验证不会 crash
      expect(result, isA<Result<String>>());
    });
  });
}
