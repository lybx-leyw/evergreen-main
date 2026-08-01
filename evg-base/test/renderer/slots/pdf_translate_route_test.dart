/// 验证 `pdf-translate` 组件类型经 SlotDispatch 路由到 TranslateSlot，
/// 不再落入 UnknownSlot（即不再显示“尚未实现渲染”）。
///
/// 运行：cd evg-base && flutter test test/renderer/slots/pdf_translate_route_test.dart
library;
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/providers.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/placeholder/unknown_slot.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/translate/translate_slot.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/composite_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('pdf-translate 经 SlotDispatch 路由到 TranslateSlot（非 UnknownSlot）',
      (tester) async {
    final descriptor = ModuleDescriptor.fromJson({
      'type': 'module',
      'id': 'pdf_translate',
      'name': 'PDF 翻译',
      'pages': []
    });
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        pluginsDirProvider.overrideWithValue(r'C:\tmp\plugins'),
      ],
      child: MaterialApp(
          home: Scaffold(
              body: SlotDispatch(
        slotKey: 'translate',
        config: const ComponentDescriptor(type: 'pdf-translate'),
        moduleDescriptor: descriptor,
      ))),
    ));
    await tester.pump();
    expect(find.byType(UnknownSlot), findsNothing);
    expect(find.byType(TranslateSlot), findsWidgets);
  });

  testWidgets('窄屏（安卓）布局不崩溃：内部 Expanded 须有界高度',
      (tester) async {
    final descriptor = ModuleDescriptor.fromJson({
      'type': 'module',
      'id': 'pdf_translate',
      'name': 'PDF 翻译',
      'pages': []
    });
    final prefs = await SharedPreferences.getInstance();
    // 约束宽度 < 600 触发 TranslateSlot 的窄屏（单列滚动）分支。
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        pluginsDirProvider.overrideWithValue(r'C:\tmp\plugins'),
      ],
      child: MaterialApp(
          home: Scaffold(
              body: SizedBox(
        width: 400,
        height: 700,
        child: SlotDispatch(
          slotKey: 'translate',
          config: const ComponentDescriptor(type: 'pdf-translate'),
          moduleDescriptor: descriptor,
        ),
      ))),
    ));
    await tester.pump();
    // 无布局异常（如 "RenderBox was not laid out" / sliver child.hasSize）。
    expect(tester.takeException(), isNull);
    expect(find.byType(TranslateSlot), findsWidgets);
  });
}
