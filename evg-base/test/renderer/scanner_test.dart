/// M3 P3 `scanner` 测试：Dart 原子组件 + slot 事件 + HTML 渲染。
///
/// 重点（R5/R9）：Windows 桌面无摄像头 → 必须渲染"手动输入"占位且不崩溃；
/// 手动提交应经 onScan → pageEventBus.emit 链路。
///
/// 运行：cd evg-base && flutter test test/renderer/scanner_test.dart
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/core/module/page_event_bus.dart';
import 'package:evergreen_base/renderer/components/document/renderScanner.dart';
import 'package:evergreen_base/renderer/components/document/scanner_slot.dart';
import 'package:evergreen_base/renderer/components/shared/widgets/scanner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ScannerWidget（原子组件）', () {
    testWidgets('Windows 无相机 → 手动输入占位不崩（R5/R9）', (tester) async {
      await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: ScannerWidget())));
      await tester.pump();
      // 平台探测降级：直接显示手动输入占位，绝不构造 MobileScanner。
      expect(find.byType(TextField), findsWidgets);
      expect(find.text('扫码需在带摄像头的移动端 / 设备'), findsWidgets);
    });

    testWidgets('手动输入提交 → 触发 onScan 回调', (tester) async {
      String? scanned;
      String? fmt;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ScannerWidget(
            onScan: (code, format) {
              scanned = code;
              fmt = format;
            },
          ),
        ),
      ));
      await tester.pump();
      final field = find.byType(TextField);
      await tester.enterText(field, 'ISBN-9787111');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(scanned, 'ISBN-9787111');
      expect(fmt, isNull);
    });
  });

  group('ScannerSlot 事件接通', () {
    testWidgets('Windows 下降级渲染不崩，hint 透传', (tester) async {
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ScannerSlot(
              slotKey: 'right',
              moduleId: 'm1',
              config: ComponentDescriptor(
                type: 'scanner',
                config: {'emitEvent': 'code_scanned', 'hint': '扫描一卡通'},
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      // 桌面降级为手动输入，hint 仍应渲染；不抛不白屏。
      expect(find.text('扫描一卡通'), findsWidgets);
      expect(find.byType(TextField), findsWidgets);
    });

    test('emitScannerEvent 经 PageEventBus 发出正确事件与数据', () async {
      final bus = PageEventBus(pageId: 'test');
      String? receivedEvent;
      String? receivedSlot;
      String? receivedCode;
      String? receivedFormat;
      final sub = bus.on('room_scanned').listen((e) {
        receivedEvent = e.event;
        receivedSlot = e.sourceSlot;
        receivedCode = e.data['code'] as String?;
        receivedFormat = e.data['format'] as String?;
      });

      emitScannerEvent(
        bus: bus,
        slotKey: 'right',
        defaultEvent: 'room_scanned',
        code: 'CARD-123',
        format: 'qr',
      );

      // 广播流为异步投递，需等待一个事件循环 tick。
      await Future<void>.delayed(Duration.zero);

      expect(receivedEvent, 'room_scanned');
      expect(receivedSlot, 'right');
      expect(receivedCode, 'CARD-123');
      expect(receivedFormat, 'qr');

      // bus 为 null 时不抛（优雅降级）。
      expect(() => emitScannerEvent(
            bus: null,
            slotKey: 'x',
            defaultEvent: 'e',
            code: 'c',
            format: null,
          ), returnsNormally);

      await sub.cancel();
      bus.dispose();
    });
  });

  group('renderScanner (HTML)', () {
    test('输出含提示 + 手动输入框 + emit 事件名', () {
      final html = renderScanner({
        'config': {
          'hint': '扫描教室码',
          'mode': 'qr',
          'emitEvent': 'room_scanned',
        }
      });
      expect(html, contains('扫描教室码'));
      expect(html, contains('evg-scanner-input'));
      expect(html, contains('room_scanned'));
    });
    test('空 config → 仍有手动输入框（不崩/不写死）', () {
      final html = renderScanner({'config': {}});
      expect(html, contains('evg-scanner-input'));
      expect(html, contains('code_scanned')); // 默认事件名
    });
  });
}
