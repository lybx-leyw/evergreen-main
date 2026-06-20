import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/features/translate/models/translation_enums.dart';
import 'package:evergreen_multi_tools/features/translate/models/translation_job.dart';
import 'package:evergreen_multi_tools/features/translate/models/translation_history.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════════════
  // TranslationStatus
  // ═══════════════════════════════════════════════════════════════════════

  group('TranslationStatus', () {
    test('isActive is true for preparing and translating', () {
      expect(TranslationStatus.preparing.isActive, isTrue);
      expect(TranslationStatus.translating.isActive, isTrue);
      expect(TranslationStatus.idle.isActive, isFalse);
      expect(TranslationStatus.done.isActive, isFalse);
      expect(TranslationStatus.error.isActive, isFalse);
    });

    test('isTerminal is true for done and error', () {
      expect(TranslationStatus.done.isTerminal, isTrue);
      expect(TranslationStatus.error.isTerminal, isTrue);
      expect(TranslationStatus.idle.isTerminal, isFalse);
      expect(TranslationStatus.preparing.isTerminal, isFalse);
      expect(TranslationStatus.translating.isTerminal, isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // LanguageOption
  // ═══════════════════════════════════════════════════════════════════════

  group('LanguageOption', () {
    test('all options have valid codes', () {
      const expectedCodes = ['zh', 'en', 'ja', 'ko', 'fr', 'de', 'es'];
      final actualCodes =
          LanguageOption.values.map((l) => l.code).toList();
      expect(actualCodes, expectedCodes);
    });

    test('Chinese has correct display name and native', () {
      expect(LanguageOption.chinese.displayName, 'Chinese');
      expect(LanguageOption.chinese.code, 'zh');
      expect(LanguageOption.chinese.nativeName, '中文');
    });

    test('English has correct display name and native', () {
      expect(LanguageOption.english.displayName, 'English');
      expect(LanguageOption.english.code, 'en');
      expect(LanguageOption.english.nativeName, 'English');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // TranslationJob
  // ═══════════════════════════════════════════════════════════════════════

  group('TranslationJob', () {
    test('has correct initial state', () {
      final job = TranslationJob(
        id: 'test-1',
        inputPath: '/tmp/test.pdf',
        inputName: 'test.pdf',
        langIn: 'en',
        langOut: 'zh',
      );
      expect(job.status, TranslationStatus.idle);
      expect(job.currentPage, 0);
      expect(job.totalPages, 0);
      expect(job.progress, 0.0);
      expect(job.isActive, isFalse);
      expect(job.isTerminal, isFalse);
    });

    test('progress is computed correctly', () {
      final job = TranslationJob(
        id: 'test-2',
        inputPath: '/tmp/test.pdf',
        inputName: 'test.pdf',
        langIn: 'en',
        langOut: 'zh',
        currentPage: 5,
        totalPages: 10,
      );
      expect(job.progress, 0.5);
    });

    test('progress is 0 when totalPages is 0', () {
      final job = TranslationJob(
        id: 'test-3',
        inputPath: '/tmp/test.pdf',
        inputName: 'test.pdf',
        langIn: 'en',
        langOut: 'zh',
      );
      expect(job.progress, 0.0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // PdfTranslateResult
  // ═══════════════════════════════════════════════════════════════════════

  group('PdfTranslateResult', () {
    test('hasOutput is true when dualPdfPath set', () {
      const result = PdfTranslateResult(dualPdfPath: '/out/paper_dual.pdf');
      expect(result.hasOutput, isTrue);
    });

    test('hasOutput is true when monoPdfPath set', () {
      const result = PdfTranslateResult(monoPdfPath: '/out/paper_mono.pdf');
      expect(result.hasOutput, isTrue);
    });

    test('hasOutput is false when no paths set', () {
      const result = PdfTranslateResult();
      expect(result.hasOutput, isFalse);
    });

    test('previewPath prefers dual over mono', () {
      const result = PdfTranslateResult(
        dualPdfPath: '/out/paper_dual.pdf',
        monoPdfPath: '/out/paper_mono.pdf',
      );
      expect(result.previewPath, '/out/paper_dual.pdf');
    });

    test('previewPath falls back to mono', () {
      const result = PdfTranslateResult(monoPdfPath: '/out/paper_mono.pdf');
      expect(result.previewPath, '/out/paper_mono.pdf');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // BatchProgress
  // ═══════════════════════════════════════════════════════════════════════

  group('BatchProgress', () {
    test('defaults to translating status', () {
      const bp = BatchProgress(
        fileIndex: 0,
        totalFiles: 3,
        fileName: 'test.pdf',
      );
      expect(bp.status, TranslationStatus.translating);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // TranslationHistory serialization
  // ═══════════════════════════════════════════════════════════════════════

  group('TranslationHistory', () {
    final now = DateTime(2026, 6, 19, 14, 30);

    test('toJson / fromJson roundtrip', () {
      final original = TranslationHistory(
        id: 'abc-123',
        fileName: 'paper.pdf',
        langIn: 'en',
        langOut: 'zh',
        dualPdfPath: '/out/paper_dual.pdf',
        totalSeconds: 45.2,
        totalTokens: 12345,
        completedAt: now,
      );
      final json = original.toJson();
      final restored = TranslationHistory.fromJson(json);
      expect(restored.id, original.id);
      expect(restored.fileName, original.fileName);
      expect(restored.langIn, original.langIn);
      expect(restored.langOut, original.langOut);
      expect(restored.dualPdfPath, original.dualPdfPath);
      expect(restored.totalSeconds, original.totalSeconds);
      expect(restored.totalTokens, original.totalTokens);
      expect(restored.completedAt, original.completedAt);
    });

    test('languagePair returns correct format', () {
      final h = TranslationHistory(
        id: 'x',
        fileName: 'a.pdf',
        langIn: 'en',
        langOut: 'zh',
        completedAt: now,
      );
      expect(h.languagePair, 'en → zh');
    });

    test('durationText formats seconds', () {
      final h = TranslationHistory(
        id: 'x',
        fileName: 'a.pdf',
        langIn: 'en',
        langOut: 'zh',
        totalSeconds: 45.2,
        completedAt: now,
      );
      expect(h.durationText, '45.2s');
    });

    test('fromJson handles missing optional fields', () {
      final restored = TranslationHistory.fromJson({
        'id': 'x',
        'fileName': 'a.pdf',
        'langIn': 'en',
        'langOut': 'zh',
        'completedAt': now.toIso8601String(),
      });
      expect(restored.dualPdfPath, isNull);
      expect(restored.totalSeconds, 0);
      expect(restored.totalTokens, 0);
    });
  });
}
