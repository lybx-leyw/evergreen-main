import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/features/translate/models/translation_enums.dart';
import 'package:evergreen_multi_tools/features/translate/models/translation_job.dart';
import 'package:evergreen_multi_tools/features/translate/models/translation_history.dart';
import 'package:evergreen_multi_tools/features/translate/providers/translate_provider.dart';

/// Provider-override setup that doesn't depend on real PdfTranslateService.
///
/// The provider tests focus on state transitions and history persistence,
/// not on actual PDF translation (which requires Python).
void main() {
  // ═══════════════════════════════════════════════════════════════════════
  // TranslationHistory serialization (pure data, no providers needed)
  // ═══════════════════════════════════════════════════════════════════════

  group('TranslationHistory JSON roundtrip', () {
    test('single record survives full cycle', () {
      final original = TranslationHistory(
        id: 'abc-123',
        fileName: 'paper.pdf',
        langIn: 'en',
        langOut: 'zh',
        dualPdfPath: '/tmp/paper_dual.pdf',
        totalSeconds: 45.2,
        totalTokens: 12345,
        completedAt: DateTime(2026, 6, 19, 14, 30),
      );

      final jsonStr = jsonEncode(original.toJson());
      final restored = TranslationHistory.fromJson(
          jsonDecode(jsonStr) as Map<String, dynamic>);

      expect(restored.id, original.id);
      expect(restored.fileName, original.fileName);
      expect(restored.langIn, original.langIn);
      expect(restored.langOut, original.langOut);
      expect(restored.dualPdfPath, original.dualPdfPath);
      expect(restored.totalSeconds, original.totalSeconds);
      expect(restored.totalTokens, original.totalTokens);
    });

    test('record without optional fields survives roundtrip', () {
      final original = TranslationHistory(
        id: 'xyz-789',
        fileName: 'notes.pdf',
        langIn: 'en',
        langOut: 'zh',
        completedAt: DateTime(2026, 6, 19, 14, 30),
      );

      final jsonStr = jsonEncode(original.toJson());
      final restored = TranslationHistory.fromJson(
          jsonDecode(jsonStr) as Map<String, dynamic>);

      expect(restored.dualPdfPath, isNull);
      expect(restored.totalSeconds, 0);
      expect(restored.totalTokens, 0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // BatchState transitions (no subprocess needed)
  // ═══════════════════════════════════════════════════════════════════════

  group('BatchState', () {
    test('initial state is empty', () {
      const state = BatchState();
      expect(state.isEmpty, isTrue);
      expect(state.totalFiles, 0);
      expect(state.isRunning, isFalse);
    });

    test('copyWith preserves unspecified fields', () {
      const state = BatchState(filePaths: ['a.pdf']);
      final updated = state.copyWith(fileNames: ['a.pdf']);
      expect(updated.filePaths, ['a.pdf']);
      expect(updated.fileNames, ['a.pdf']);
    });

    test('doneCount and errorCount', () {
      const state = BatchState(
        results: [
          BatchProgress(
              fileIndex: 0,
              totalFiles: 3,
              fileName: 'a.pdf',
              status: TranslationStatus.done),
          BatchProgress(
              fileIndex: 1,
              totalFiles: 3,
              fileName: 'b.pdf',
              status: TranslationStatus.error),
          BatchProgress(
              fileIndex: 2,
              totalFiles: 3,
              fileName: 'c.pdf',
              status: TranslationStatus.translating),
        ],
      );
      expect(state.doneCount, 1);
      expect(state.errorCount, 1);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // LanguageOption completeness
  // ═══════════════════════════════════════════════════════════════════════

  group('LanguageOption', () {
    test('all 7 languages defined', () {
      expect(LanguageOption.values.length, 7);
    });

    test('every option has non-empty code and displayName', () {
      for (final l in LanguageOption.values) {
        expect(l.code.isNotEmpty, isTrue, reason: '${l.displayName} code');
        expect(l.displayName.isNotEmpty, isTrue,
            reason: '${l.code} displayName');
        expect(l.nativeName.isNotEmpty, isTrue,
            reason: '${l.code} nativeName');
      }
    });
  });
}
