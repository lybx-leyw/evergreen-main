/// M3 P2 `pdf-viewer` 测试：Dart 原子组件 + HTML 渲染。
///
/// 验证：空态不崩；config 真实字段（title/url）渲染；HTML 输出含 iframe 与真实 url。
///
/// 运行：cd evg-base && flutter test test/renderer/pdf_viewer_test.dart
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/pdf_viewer_slot.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/renderPdfViewer.dart';
import 'package:evergreen_base/renderer/components/shared/widgets/pdf_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PdfViewerWidget', () {
    testWidgets('无 url/path → 空态不崩（R5）', (tester) async {
      await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: PdfViewerWidget())));
      await tester.pump();
      expect(find.text('未提供 PDF 地址'), findsWidgets);
    });

    testWidgets('title 经 config 同步渲染到工具条', (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: PdfViewerWidget(
                  title: '我的PDF', path: 'assets/x.pdf'))));
      await tester.pump(); // 单帧：工具条同步渲染，不等 PDF 异步加载
      expect(find.byType(PdfViewerWidget), findsWidgets);
      expect(find.text('我的PDF'), findsWidgets);
    });
  });

  group('renderPdfViewer (HTML)', () {
    test('有 url → 输出 iframe 含真实 url 与页码', () {
      final html = renderPdfViewer({
        'config': {'url': 'https://e.com/a.pdf', 'title': '白皮书', 'page': 3}
      });
      expect(html, contains('iframe'));
      expect(html, contains('https://e.com/a.pdf'));
      expect(html, contains('page=3'));
    });
    test('无 url/path → 空态', () {
      final html = renderPdfViewer({'config': {}});
      expect(html, contains('未提供 PDF 地址'));
    });
    test('仅 path（本地文件）→ 降级提示不崩', () {
      final html = renderPdfViewer({
        'config': {'path': 'assets/docs/intro.pdf', 'title': '本地手册'}
      });
      expect(html, contains('evg-pdf-note'));
      expect(html, contains('本地文件'));
      expect(html, contains('本地手册'));
    });
  });

  group('PdfViewerSlot 接通', () {
    testWidgets('经 SlotDispatch 路由到 PdfViewerSlot（非 UnknownSlot）',
        (tester) async {
      final slot = PdfViewerSlot(
        config: ComponentDescriptor(type: 'pdf-viewer'),
        moduleId: 'test',
        pluginsDir: r'C:\tmp\plugins',
      );
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: slot)));
      await tester.pump();
      expect(find.byType(PdfViewerWidget), findsWidgets);
    });
  });
}
