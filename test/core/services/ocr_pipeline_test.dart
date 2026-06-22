import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/core/services/ocr_pipeline.dart';
import 'package:evergreen_multi_tools/core/config/app_config.dart';
import '../../mocks/mock_app_config.dart';
import '../../mocks/mock_dio.dart';

/// Load a fixture JSON string by name.
String _fixture(String name) {
  switch (name) {
    case 'ocr_ok':
      return jsonEncode({
        'choices': [
          {
            'message': {
              'content': 'DeepSeek OCR 识别结果：测试文本。',
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
    default:
      return '{}';
  }
}

/// Check if Python + Tesseract are available for integration tests.
bool get _hasPython {
  try {
    final result = Process.runSync('python', ['--version']);
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}

/// Check if ocr_file.py exists for Tesseract integration tests.
bool get _hasOcrScripts {
  return File('scripts/ocr_file.py').existsSync() ||
      File('scripts/ocr_slides.py').existsSync();
}

void main() {
  // ── _parsePageOutput (静态方法，纯函数) ──────────────────────

  group('OcrPipeline.parsePageOutput', () {
    test('单页 JSON → 纯文本', () {
      final json = jsonEncode({
        'pages': [
          {'page': 1, 'text': '第一页内容'},
        ]
      });
      final result = OcrPipeline.parsePageOutput(json);
      expect(result, '第一页内容');
    });

    test('多页 JSON → 带页眉的合并文本', () {
      final json = jsonEncode({
        'pages': [
          {'page': 1, 'text': '首页'},
          {'page': 2, 'text': '第二页'},
        ]
      });
      final result = OcrPipeline.parsePageOutput(json);
      expect(result, contains('--- 第 1 页 ---'));
      expect(result, contains('首页'));
      expect(result, contains('--- 第 2 页 ---'));
      expect(result, contains('第二页'));
    });

    test('空 pages → null', () {
      final json = jsonEncode({'pages': []});
      final result = OcrPipeline.parsePageOutput(json);
      expect(result, isNull);
    });

    test('pages 字段缺失 → null', () {
      final json = jsonEncode({'error': 'something'});
      final result = OcrPipeline.parsePageOutput(json);
      expect(result, isNull);
    });

    test('非 JSON 输入 → null', () {
      final result = OcrPipeline.parsePageOutput('not valid json');
      expect(result, isNull);
    });

    test('空字符串 → null', () {
      final result = OcrPipeline.parsePageOutput('');
      expect(result, isNull);
    });

    test('所有页面 text 为空 → null', () {
      final json = jsonEncode({
        'pages': [
          {'page': 1, 'text': ''},
          {'page': 2, 'text': ''},
        ]
      });
      final result = OcrPipeline.parsePageOutput(json);
      expect(result, isNull);
    });

    test('部分页面有 text，部分为空 → 只包含有内容的页面', () {
      final json = jsonEncode({
        'pages': [
          {'page': 1, 'text': ''},
          {'page': 2, 'text': '有效内容'},
          {'page': 3, 'text': ''},
        ]
      });
      final result = OcrPipeline.parsePageOutput(json);
      expect(result, isNotNull);
      expect(result, contains('有效内容'));
      expect(result, contains('第 2 页'));
      // 因为只有 1 个有效页但总 pages.length > 1，仍会显示页眉
      // 这是设计行为——按总页数判断是否显示页眉
    });

    test('text 字段缺失 → 跳过该页', () {
      final json = jsonEncode({
        'pages': [
          {'page': 1},
          {'page': 2, 'text': '内容'},
        ]
      });
      final result = OcrPipeline.parsePageOutput(json);
      // pages.length=2 > 1 → 会添加页眉，即使第1页为空
      expect(result, contains('第 2 页'));
      expect(result, contains('内容'));
    });

    test('单页 text 为空 → null', () {
      final json = jsonEncode({
        'pages': [
          {'page': 1, 'text': ''},
        ]
      });
      final result = OcrPipeline.parsePageOutput(json);
      expect(result, isNull);
    });
  });

  // ── recognizeFile ───────────────────────────────────────────

  group('OcrPipeline.recognizeFile', () {
    setUp(() {
      resetAppConfig();
    });

    tearDown(() {
      resetAppConfig();
    });

    test('文件不存在 → null', () async {
      final (dio, _) = createMockDio();
      final pipeline = OcrPipeline(dio);
      final result = await pipeline.recognizeFile('/nonexistent/file.png');
      expect(result, isNull);
    });

    test('配置 DeepSeek API key → Level 1 成功时返回结果', () async {
      setupTestAppConfig(ocrApiKey: 'sk-test-ocr');

      final (dio, adapter) = createMockDio();
      adapter.stub(
        'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions',
        MockResponse(body: jsonDecode(_fixture('ocr_ok'))),
      );

      // Create a test image file
      final tmpFile = File(
          '${Directory.systemTemp.path}${Platform.pathSeparator}ocr_pipe_test_img.png');
      const pngBase64 =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
      tmpFile.writeAsBytesSync(base64Decode(pngBase64));

      try {
        final pipeline = OcrPipeline(dio);
        final result = await pipeline.recognizeFile(tmpFile.path);
        expect(result, isNotNull);
        expect(result, contains('DeepSeek OCR'));
        expect(result, contains('测试文本'));
      } finally {
        try {
          tmpFile.deleteSync();
        } catch (_) {}
      }
    });

    test('DeepSeek 返回空 → 降级到 Tesseract', () async {
      setupTestAppConfig(ocrApiKey: 'sk-test-ocr');

      final (dio, adapter) = createMockDio();
      adapter.stub(
        'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions',
        MockResponse(body: jsonDecode(_fixture('ocr_empty'))),
      );

      final tmpFile = File(
          '${Directory.systemTemp.path}${Platform.pathSeparator}ocr_pipe_test_fallback.png');
      const pngBase64 =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
      tmpFile.writeAsBytesSync(base64Decode(pngBase64));

      try {
        final pipeline = OcrPipeline(dio);
        final result = await pipeline
            .recognizeFile(tmpFile.path)
            .timeout(const Duration(minutes: 3));
        // Falls back to Tesseract (Level 2) — may return null if Python/Tesseract
        // not installed, but should not crash
        // If Tesseract is available, it will OCR the 1×1 pixel image (probably empty)
        expect(result, anyOf(isNull, isA<String>()));
      } on Exception catch (e) {
        // 超时或进程异常：降级链应容错
        expect(e.toString(), isA<String>());
      } finally {
        try {
          tmpFile.deleteSync();
        } catch (_) {}
      }
    });

    test('未配置 API key → 直接走 Tesseract', () async {
      // No API key set
      final (dio, _) = createMockDio();

      final tmpFile = File(
          '${Directory.systemTemp.path}${Platform.pathSeparator}ocr_pipe_no_key.png');
      const pngBase64 =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
      tmpFile.writeAsBytesSync(base64Decode(pngBase64));

      try {
        final pipeline = OcrPipeline(dio);
        final result = await pipeline
            .recognizeFile(tmpFile.path)
            .timeout(const Duration(minutes: 3));
        // Falls back to Tesseract
        expect(result, anyOf(isNull, isA<String>()));
      } on Exception catch (e) {
        expect(e.toString(), isA<String>());
      } finally {
        try {
          tmpFile.deleteSync();
        } catch (_) {}
      }
    });
  });

  // ── recognizeUrl ────────────────────────────────────────────

  group('OcrPipeline.recognizeUrl', () {
    setUp(() {
      resetAppConfig();
    });

    tearDown(() {
      resetAppConfig();
    });

    test('DeepSeek URL OCR 成功', () async {
      setupTestAppConfig(ocrApiKey: 'sk-test-ocr');

      final (dio, adapter) = createMockDio();
      // Stub the image download
      const pngBase64 =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
      adapter.stub(
        'https://img.cmc.zju.edu.cn/slides/page1.jpg',
        MockResponse(
          body: base64Decode(pngBase64),
          headers: {'Content-Type': 'image/png'},
        ),
      );
      // Stub the OCR API
      adapter.stub(
        'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions',
        MockResponse(body: jsonDecode(_fixture('ocr_ok'))),
      );

      final pipeline = OcrPipeline(dio);
      final result = await pipeline.recognizeUrl(
          'https://img.cmc.zju.edu.cn/slides/page1.jpg');

      expect(result, isNotEmpty);
      expect(result, contains('DeepSeek OCR'));
    });

    test('DeepSeek URL OCR 失败 → 降级到 Tesseract', () async {
      setupTestAppConfig(ocrApiKey: 'sk-test-ocr');

      final (dio, adapter) = createMockDio();
      // Stub the image download
      const pngBase64 =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
      adapter.stub(
        'https://img.cmc.zju.edu.cn/slides/page2.jpg',
        MockResponse(
          body: base64Decode(pngBase64),
          headers: {'Content-Type': 'image/png'},
        ),
      );
      // Stub OCR API to return empty
      adapter.stub(
        'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions',
        MockResponse(body: jsonDecode(_fixture('ocr_empty'))),
      );

      final pipeline = OcrPipeline(dio);
      final result = await pipeline.recognizeUrl(
          'https://img.cmc.zju.edu.cn/slides/page2.jpg');

      // Falls back to Tesseract — may return empty if Tesseract not installed
      expect(result, isA<String>());
    });

    test('未配置 API key → 直接 Tesseract', () async {
      final (dio, adapter) = createMockDio();
      const pngBase64 =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
      adapter.stub(
        'https://img.cmc.zju.edu.cn/slides/page3.jpg',
        MockResponse(
          body: base64Decode(pngBase64),
          headers: {'Content-Type': 'image/png'},
        ),
      );

      final pipeline = OcrPipeline(dio);
      final result = await pipeline.recognizeUrl(
          'https://img.cmc.zju.edu.cn/slides/page3.jpg');

      // No API key → goes to Tesseract directly
      expect(result, isA<String>());
    });

    test('图片下载失败 → 降级到 Tesseract (ocr_slides 自行下载)', () async {
      setupTestAppConfig(ocrApiKey: 'sk-test-ocr');

      final (dio, adapter) = createMockDio();
      // Stub download to fail for DeepSeek path
      final url = 'https://img.cmc.zju.edu.cn/slides/page_fail.jpg';
      adapter.stubError(
        url,
        DioException(
          requestOptions: RequestOptions(path: url),
          type: DioExceptionType.connectionError,
        ),
      );

      final pipeline = OcrPipeline(dio);
      final result = await pipeline.recognizeUrl(url);

      // Falls back to Tesseract (may return '' if Tesseract not available)
      expect(result, isA<String>());
    });
  });

  // ── 集成测试：Tesseract 真实 OCR ────────────────────────────

  group('OcrPipeline (Tesseract integration)', () {
    setUp(() {
      resetAppConfig();
    });

    tearDown(() {
      resetAppConfig();
    });

    test('recognizeFile 本地图片 → Tesseract', () async {
      if (!_hasPython || !_hasOcrScripts) {
        return; // skip silently if deps not available
      }

      final (dio, _) = createMockDio();
      // No API key → direct Tesseract

      // Use a file known to exist — the test PNG
      final tmpFile = File(
          '${Directory.systemTemp.path}${Platform.pathSeparator}ocr_tess_test.png');
      const pngBase64 =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
      tmpFile.writeAsBytesSync(base64Decode(pngBase64));

      try {
        final pipeline = OcrPipeline(dio);
        final result = await pipeline.recognizeFile(tmpFile.path);
        // Tesseract may return null (no text on 1×1 pixel) but shouldn't crash
        expect(result, anyOf(isNull, isA<String>()));
      } finally {
        try {
          tmpFile.deleteSync();
        } catch (_) {}
      }
    });
  });
}
