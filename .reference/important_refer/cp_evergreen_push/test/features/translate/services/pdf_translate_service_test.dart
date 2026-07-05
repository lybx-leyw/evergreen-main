import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/core/result.dart';
import 'package:evergreen_multi_tools/core/services/pdf_translate_service.dart';

void main() {
  late PdfTranslateService service;

  setUp(() {
    service = PdfTranslateService(
      scriptPath: 'scripts/pdf_translate.py',
    );
  });

  group('PdfTranslateService.checkEnvironment', () {
    test('returns Ok with null or message', () async {
      // Python may or may not be installed on the dev machine — both are OK.
      // The service always uses 'python' (hardcoded, same as OCR).
      final result = await service.checkEnvironment();
      expect(result.isOk, isTrue);
    });
  });

  group('PdfTranslateService.translate', () {
    test('returns Err when input file does not exist', () async {
      final result = await service.translate(
        inputPath: '/nonexistent/path/paper.pdf',
        outputDir: '/tmp/output',
        apiKey: 'sk-test',
      );
      expect(result.isErr, isTrue);
      expect((result as Err).error.userMessage, contains('文件不存在'));
    });

    test('handles missing Python gracefully', () async {
      // Service always uses 'python' (hardcoded, like OCR).
      // If Python is installed: translation will start (and fail on missing input).
      // If Python is missing: will get ProcessException → translated to user-friendly error.
      // Either way, the error message should guide the user.
      final tempFile = File('${Directory.systemTemp.path}/test_input.pdf');
      await tempFile.writeAsString('%PDF-1.4 fake');
      try {
        final result = await service.translate(
          inputPath: tempFile.path,
          outputDir: '${Directory.systemTemp.path}/translated',
          apiKey: 'sk-test',
        );
        // If Python is available, the script runs and fails with API error.
        // If Python is missing, we get a translated error.
        // Both are valid outcomes.
        expect(result.isErr, isTrue);
      } finally {
        await tempFile.delete();
      }
    });
  });
}
