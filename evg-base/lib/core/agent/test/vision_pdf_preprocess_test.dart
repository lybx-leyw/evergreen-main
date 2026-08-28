/// VisionPdfPreprocess 测试（Task R3-6）。
///
/// 测试环境 `Platform.isAndroid=false` → 恒不拆分（桌面零行为变化）；
/// flutter_stub 的 MethodChannel.invokeMethod 恒返回 null → 即使安卓路径
/// 也 fail-open 返回 null（旧 APK / 渲染失败不引入新崩溃路径）。
library;

import 'package:test/test.dart';

import '../tools/vision_pdf_preprocess.dart';

void main() {
  group('VisionPdfPreprocess.trySplitPdf', () {
    test('非安卓（桌面）→ 恒 null，PDF 原样交给 vision.py（fitz 路径不变）',
        () async {
      expect(
        await VisionPdfPreprocess.trySplitPdf(
            {'mode': 'ocr', 'file_path': '/tmp/doc.pdf'}),
        isNull,
      );
    });

    test('非 PDF 文件 → null（图片/PPT 不走预拆分，vision.py 内部处理）',
        () async {
      expect(
        await VisionPdfPreprocess.trySplitPdf(
            {'mode': 'describe', 'file_path': '/tmp/scan.png'}),
        isNull,
      );
      expect(
        await VisionPdfPreprocess.trySplitPdf(
            {'mode': 'describe', 'file_path': '/tmp/deck.pptx'}),
        isNull,
      );
    });

    test('generate 模式 → null（生图占位，无文件输入）', () async {
      expect(
        await VisionPdfPreprocess.trySplitPdf({'mode': 'generate'}),
        isNull,
      );
    });

    test('缺少 file_path → null', () async {
      expect(await VisionPdfPreprocess.trySplitPdf({'mode': 'ocr'}), isNull);
    });

    test('已含 pages_dir → null（幂等，防重入）', () async {
      expect(
        await VisionPdfPreprocess.trySplitPdf({
          'mode': 'ocr',
          'file_path': '/tmp/doc.pdf',
          'pages_dir': '/tmp/evergreen_vision_pdf/1',
        }),
        isNull,
      );
    });
  });
}
