/// M3 P4 集成测试：两端注册接通 + 全景计数。
///
/// - Dart 端 [SlotDispatch] 必须把 `pdf-viewer`/`scanner` 路由到对应 Slot，
///   而非兜底 [UnknownSlot]（R2）。
/// - HTML 端经公共 [renderComponent] 必须命中 `pdf-viewer`/`scanner` 渲染器，
///   输出含真实字段、不写死（R7）。
///
/// 运行：cd evg-base && flutter test test/m3_components_test.dart
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/renderer/components/placeholder/unknown_slot.dart';
import 'package:evergreen_base/renderer/components/shared/widgets/pdf_viewer.dart';
import 'package:evergreen_base/renderer/page/composite_view.dart';
import 'package:evergreen_base/renderer/page/html_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Dart 端 SlotDispatch 接通（非 UnknownSlot）', () {
    testWidgets('pdf-viewer → PdfViewerSlot（空态也不走 UnknownSlot）',
        (tester) async {
      final desc = ModuleDescriptor(id: 'm', name: 'M');
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SlotDispatch(
              slotKey: 's1',
              config: ComponentDescriptor(
                type: 'pdf-viewer',
                config: {'title': '白皮书'},
              ),
              moduleDescriptor: desc,
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(find.byType(PdfViewerWidget), findsWidgets);
      expect(find.byType(UnknownSlot), findsNothing);
    });

    testWidgets('scanner → ScannerSlot（桌面降级为手动输入，不崩）',
        (tester) async {
      final desc = ModuleDescriptor(id: 'm', name: 'M');
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SlotDispatch(
              slotKey: 's2',
              config: ComponentDescriptor(
                type: 'scanner',
                config: {'emitEvent': 'code_scanned', 'hint': '扫描一卡通'},
              ),
              moduleDescriptor: desc,
            ),
          ),
        ),
      ));
      await tester.pump();
      // 桌面无相机 → 手动输入占位（TextField），仍非 UnknownSlot。
      expect(find.byType(TextField), findsWidgets);
      expect(find.byType(UnknownSlot), findsNothing);
    });
  });

  group('HTML 端 renderComponent 接通', () {
    test('pdf-viewer / scanner 均已注册且输出真实字段', () async {
      final pdf = await renderComponent({
        'type': 'pdf-viewer',
        'config': {'url': 'https://e.com/b.pdf', 'title': '白皮书', 'page': 2}
      }, null);
      expect(pdf, contains('https://e.com/b.pdf'));
      expect(pdf, contains('page=2'));
      expect(pdf, isNot(contains('未提供 PDF 地址')));

      final scan = await renderComponent({
        'type': 'scanner',
        'config': {'hint': '扫描教室码', 'emitEvent': 'room_scanned'}
      }, null);
      expect(scan, contains('evg-scanner-input'));
      expect(scan, contains('room_scanned'));

      // 图标注册
      expect(componentIcon('pdf-viewer'), '📕');
      expect(componentIcon('scanner'), '📷');
    });
  });
}
