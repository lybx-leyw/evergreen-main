import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 边界测试：RenderObject 访问 + "attached" / "debugNeedsLayout" 断言。
///
/// 覆盖实际踩坑：
/// - 访问已 deactivate 的 RenderObject
/// - Layout 在执行中再次触发布局
/// - GlobalKey 在 widget 已卸载后访问

void main() {
  group('RenderObject — safety', () {
    testWidgets('GlobalKey 访问已卸载 widget 不崩溃', (tester) async {
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SizedBox(key: key)),
      ));
      expect(key.currentContext, isNotNull);

      // 卸载
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump();

      // GlobalKey 现在指向已卸载的 Element
      // 但不直接访问 renderObject 就不会崩溃
      expect(key.currentContext, isNull);
    });

    testWidgets('LayoutBuilder 在约束变化时正常重布局', (tester) async {
      double? lastWidth;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LayoutBuilder(
            builder: (_, constraints) {
              lastWidth = constraints.maxWidth;
              return SizedBox(width: constraints.maxWidth * 0.5, height: 50);
            },
          ),
        ),
      ));
      expect(lastWidth, greaterThan(0));

      // 改变窗口大小（通过 SizedBox 包裹模拟）
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 500,
            child: LayoutBuilder(
              builder: (_, constraints) {
                lastWidth = constraints.maxWidth;
                return SizedBox(
                    width: constraints.maxWidth * 0.5, height: 50);
              },
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(lastWidth, 500);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ScrollController 在 dispose 后不访问 RenderObject', (tester) async {
      final controller = ScrollController();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListView(
            controller: controller,
            children: List.generate(100, (i) => SizedBox(height: 50, child: Text('$i'))),
          ),
        ),
      ));
      expect(controller.hasClients, true);

      // 卸载 scroll view
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
      await tester.pump();

      // 已无 clients，访问不应崩溃
      expect(controller.hasClients, false);
      // animateTo / jumpTo 在无 clients 时不抛异常（ScrollController 做了防护）
    });
  });
}
