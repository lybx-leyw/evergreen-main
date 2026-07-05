import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/core/services/mlkit_ocr_service.dart';

/// Tests for MlKitOcrService — defensive initialization and null handling.
///
/// These are pure unit tests that verify the service's safety guards
/// without requiring actual ML Kit (Android/iOS) platform APIs.
void main() {
  group('MlKitOcrService construction', () {
    test('constructor does not throw', () {
      // Constructor should not create TextRecognizer immediately
      expect(() => MlKitOcrService(), returnsNormally);
    });

    test('can create multiple instances', () {
      // Each instance should be independent
      final a = MlKitOcrService();
      final b = MlKitOcrService();
      expect(identical(a, b), isFalse);
    });
  });

  group('MlKitOcrService disposal', () {
    test('dispose before any use does not throw', () {
      final service = MlKitOcrService();
      expect(() => service.dispose(), returnsNormally);
    });

    test('dispose after dispose is idempotent', () {
      final service = MlKitOcrService();
      service.dispose();
      expect(() => service.dispose(), returnsNormally);
    });
  });

  group('MlKitOcrService recognizePages', () {
    test('empty list returns null', () async {
      final service = MlKitOcrService();
      final result = await service.recognizePages([]);
      expect(result, isNull);
    });

    test('null input handled gracefully', () async {
      final service = MlKitOcrService();
      // recognizeImage with null path — should catch PathNotFoundException
      // and return null (on VM this will be a FileSystemException)
      final result = await service.recognizeImage('/nonexistent/path_that_does_not_exist.png');
      expect(result, isNull);
    });

    test('empty path returns null gracefully', () async {
      final service = MlKitOcrService();
      final result = await service.recognizeImage('');
      expect(result, isNull);
    });
  });
}
