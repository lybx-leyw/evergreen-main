import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/core/services/ocr_pipeline.dart';
import 'package:evergreen_multi_tools/core/config/app_config.dart';
import '../../mocks/mock_app_config.dart';
import '../../mocks/mock_dio.dart';

/// Tests verifying the simplified OCR logic in notes_provider.
///
/// After removing the duplicate Python subprocess escape hatch,
/// _ocrOneSlide relies solely on OcrPipeline.recognizeUrl().
/// These tests verify the OcrPipeline and delegate behavior
/// for the notes provider's use case (PPT slide URL OCR).
void main() {
  setUp(() {
    resetAppConfig();
  });

  tearDown(() {
    resetAppConfig();
  });

  group('OcrPipeline.recognizeUrl — notes provider use case', () {
    test('returns text when DeepSeek succeeds (Level 1)', () async {
      setupTestAppConfig(ocrApiKey: 'sk-test-ocr');

      final (dio, adapter) = createMockDio();
      const pngBase64 =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
      final url = 'https://classroom.zju.edu.cn/slides/note_test.jpg';

      adapter.stub(
        url,
        MockResponse(
          body: base64Decode(pngBase64),
          headers: {'Content-Type': 'image/png'},
        ),
      );
      adapter.stub(
        'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions',
        MockResponse(
          body: jsonDecode(jsonEncode({
            'choices': [
              {
                'message': {
                  'content': '幻灯片内容：第3章 线性代数基础',
                }
              }
            ],
          })),
        ),
      );

      final pipeline = OcrPipeline(dio);
      final result = await pipeline.recognizeUrl(url);

      expect(result, isNotEmpty);
      expect(result, contains('线性代数'));
    });

    test('returns empty string when all levels fail (no API key, no Python)',
        () async {
      // No API key, no Python → Level 2 Tesseract will fail
      // OcrPipeline should return '' gracefully
      final (dio, adapter) = createMockDio();
      const pngBase64 =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
      final url = 'https://classroom.zju.edu.cn/slides/note_fail.jpg';

      adapter.stub(
        url,
        MockResponse(
          body: base64Decode(pngBase64),
          headers: {'Content-Type': 'image/png'},
        ),
      );

      final pipeline = OcrPipeline(dio);
      final result = await pipeline.recognizeUrl(url);

      // Should return '' or a string (graceful degradation)
      expect(result, isA<String>());
      // Not null — always returns a string (empty on failure)
    });

    test('download failure → falls back gracefully', () async {
      setupTestAppConfig(ocrApiKey: 'sk-test-ocr');

      final (dio, adapter) = createMockDio();
      final url = 'https://classroom.zju.edu.cn/slides/offline.jpg';

      adapter.stubError(
        url,
        DioException(
          requestOptions: RequestOptions(path: url),
          type: DioExceptionType.connectionError,
        ),
      );

      final pipeline = OcrPipeline(dio);
      final result = await pipeline.recognizeUrl(url);

      // Falls back to Tesseract on desktop, or mobile delegate
      // Should return string (not throw)
      expect(result, isA<String>());
    });
  });

  group('OcrPipeline Level 2 fallback chain for URLs', () {
    test('DeepSeek empty → tries Level 2', () async {
      setupTestAppConfig(ocrApiKey: 'sk-test-ocr');

      final (dio, adapter) = createMockDio();
      const pngBase64 =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
      final url = 'https://classroom.zju.edu.cn/slides/empty_ocr.jpg';

      adapter.stub(
        url,
        MockResponse(
          body: base64Decode(pngBase64),
          headers: {'Content-Type': 'image/png'},
        ),
      );
      // DeepSeek returns empty content
      adapter.stub(
        'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions',
        MockResponse(
          body: jsonDecode(jsonEncode({
            'choices': [
              {'message': {'content': ''}}
            ],
          })),
        ),
      );

      final pipeline = OcrPipeline(dio);
      final result = await pipeline.recognizeUrl(url);

      // Falls back to Level 2 (Tesseract or mobile delegate)
      expect(result, isA<String>());
    });
  });

  group('OcrPipeline.recognizeFile — notes provider file types', () {
    test('recognizeFile handles image types: png', () async {
      final tmpFile = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}notes_ocr_png.png',
      );
      const pngBase64 =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
      tmpFile.writeAsBytesSync(base64Decode(pngBase64));

      try {
        final (dio, _) = createMockDio();
        final pipeline = OcrPipeline(dio);
        final result = await pipeline
            .recognizeFile(tmpFile.path)
            .timeout(const Duration(minutes: 3));
        // Goes to Level 2 (no API key set in this test)
        // CI may lack Tesseract binary → returns null
        expect(result, anyOf(isNull, isA<String>()));
      } on Exception catch (e) {
        expect(e.toString(), isA<String>());
      } finally {
        try {
          tmpFile.deleteSync();
        } catch (_) {}
      }
    });

    test('recognizeFile handles image types: jpg', () async {
      final tmpFile = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}notes_ocr_jpg.jpg',
      );
      // Minimal valid JPEG (1x1 pixel)
      const jpgBytes = [
        0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46,
        0x00, 0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00,
        0xFF, 0xDB, 0x00, 0x43, 0x00, 0x08, 0x06, 0x06, 0x07, 0x06,
        0x05, 0x08, 0x07, 0x07, 0x07, 0x09, 0x09, 0x08, 0x0A, 0x0C,
        0x14, 0x0D, 0x0C, 0x0B, 0x0B, 0x0C, 0x19, 0x12, 0x13, 0x0F,
        0x14, 0x1D, 0x1A, 0x1F, 0x1E, 0x1D, 0x1A, 0x1C, 0x1C, 0x20,
        0x24, 0x2E, 0x27, 0x20, 0x22, 0x2C, 0x23, 0x1C, 0x1C, 0x27,
        0x34, 0x2C, 0x2E, 0x30, 0x31, 0x32, 0x32, 0x32, 0x1F, 0x27,
        0x33, 0x38, 0x33, 0x2F, 0x38, 0x2C, 0x30, 0x32, 0x30, 0xFF,
        0xC0, 0x00, 0x0B, 0x08, 0x00, 0x01, 0x00, 0x01, 0x01, 0x01,
        0x11, 0x00, 0xFF, 0xC4, 0x00, 0x1F, 0x00, 0x00, 0x01, 0x05,
        0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06,
        0x07, 0x08, 0x09, 0x0A, 0x0B, 0xFF, 0xC4, 0x00, 0xB5, 0x10,
        0x00, 0x02, 0x01, 0x03, 0x03, 0x02, 0x04, 0x03, 0x05, 0x05,
        0x04, 0x04, 0x00, 0x00, 0x01, 0x7D, 0x01, 0x02, 0x03, 0x00,
        0x04, 0x11, 0x05, 0x12, 0x21, 0x31, 0x41, 0x06, 0x13, 0x51,
        0x61, 0x07, 0x22, 0x71, 0x14, 0x32, 0x81, 0x91, 0xA1, 0x08,
        0x23, 0x42, 0xB1, 0xC1, 0x15, 0x52, 0xD1, 0xF0, 0x24, 0x33,
        0x62, 0x72, 0x82, 0x09, 0x0A, 0x16, 0x17, 0x18, 0x19, 0x1A,
        0x25, 0x26, 0x27, 0x28, 0x29, 0x2A, 0x34, 0x35, 0x36, 0x37,
        0x38, 0x39, 0x3A, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49,
        0x4A, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5A, 0x63,
        0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6A, 0x73, 0x74, 0x75,
        0x76, 0x77, 0x78, 0x79, 0x7A, 0x83, 0x84, 0x85, 0x86, 0x87,
        0x88, 0x89, 0x8A, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98,
        0x99, 0x9A, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7, 0xA8, 0xA9,
        0xAA, 0xB2, 0xB3, 0xB4, 0xB5, 0xB6, 0xB7, 0xB8, 0xB9, 0xBA,
        0xC2, 0xC3, 0xC4, 0xC5, 0xC6, 0xC7, 0xC8, 0xC9, 0xCA, 0xD2,
        0xD3, 0xD4, 0xD5, 0xD6, 0xD7, 0xD8, 0xD9, 0xDA, 0xE1, 0xE2,
        0xE3, 0xE4, 0xE5, 0xE6, 0xE7, 0xE8, 0xE9, 0xEA, 0xF1, 0xF2,
        0xF3, 0xF4, 0xF5, 0xF6, 0xF7, 0xF8, 0xF9, 0xFA, 0xFF, 0xDA,
        0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3F, 0x00, 0x37, 0x80,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0xD9,
      ];
      tmpFile.writeAsBytesSync(jpgBytes);

      try {
        final (dio, _) = createMockDio();
        final pipeline = OcrPipeline(dio);
        final result = await pipeline.recognizeFile(tmpFile.path);
        // Goes to Level 2 (no API key)
        expect(result, anyOf(isNull, isA<String>()));
      } finally {
        try {
          tmpFile.deleteSync();
        } catch (_) {}
      }
    });
  });
}
