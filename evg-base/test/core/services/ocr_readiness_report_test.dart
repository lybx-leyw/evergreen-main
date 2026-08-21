// OcrReadinessReport 纯逻辑测试（不触 FS：直接构造报告对象）。
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_base/core/services/ocr_pipeline.dart';

void main() {
  OcrReadinessReport _report({
    bool python = true,
    bool pdf = true,
    bool ocr = true,
    bool key = true,
    bool tess = true,
    List<String> issues = const [],
  }) =>
      OcrReadinessReport(
        pythonAvailable: python,
        pdfScriptAvailable: pdf,
        ocrFileScriptAvailable: ocr,
        deepSeekKeyConfigured: key,
        tesseractAvailable: tess,
        issues: issues,
      );

  group('OcrReadinessReport', () {
    test('全部就绪 → ready + 摘要', () {
      final r = _report();
      expect(r.ready, isTrue);
      expect(r.summarize(), contains('OCR 就绪'));
    });

    test('存在问题 → ready=false + 摘要列出问题', () {
      final r = _report(
        python: false,
        key: false,
        tess: false,
        issues: [
          '未找到 Python 解释器',
          '未配置 DEEPSEEK_OCR_API_KEY',
        ],
      );
      expect(r.ready, isFalse);
      final s = r.summarize();
      expect(s, contains('OCR 未就绪'));
      expect(s, contains('未找到 Python 解释器'));
    });

    test('关键组件缺失映射到摘要', () {
      final r = _report(pdf: false, issues: ['缺少 pdf_to_images.py']);
      expect(r.pdfScriptAvailable, isFalse);
      expect(r.ready, isFalse);
    });
  });
}
