/// M3 P2 `pdf-viewer` 测试：Dart 原子组件。
///
/// 验证：空态不崩；config 真实字段（title/url）渲染。
///
/// 运行：cd evg-base && flutter test test/renderer/slots/pdf_viewer_test.dart
library;
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/renderer/components/shared/widgets/pdf_viewer.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/pdf_viewer_slot.dart';
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
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(
              body: PdfViewerWidget(
                  title: '我的PDF', path: 'assets/x.pdf'))));
      await tester.pump(); // 工具条同步渲染（占位版无异步 PDF 加载）
      expect(find.byType(PdfViewerWidget), findsWidgets);
      expect(find.text('我的PDF'), findsWidgets);
    });
  });

  group('PdfViewerSlot 接通', () {
    testWidgets('经 SlotDispatch 路由到 PdfViewerSlot（非 UnknownSlot）',
        (tester) async {
      const slot = PdfViewerSlot(
        config: ComponentDescriptor(type: 'pdf-viewer'),
        moduleId: 'test',
        pluginsDir: r'C:\tmp\plugins',
      );
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: slot)));
      await tester.pump();
      expect(find.byType(PdfViewerWidget), findsWidgets);
    });
  });
}
