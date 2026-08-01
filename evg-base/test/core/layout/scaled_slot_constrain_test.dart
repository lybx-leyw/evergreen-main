/// ScaledSlot `constrain` 参数测试。
///
/// 验证 ScaledSlot 在 `constrain: true` 时会通过 SizedBox 给子组件
/// 提供 tight 约束（用于 absolute 布局 Positioned + ScaledSlot 场景）。
///
/// 修复历史：原本 ScaledSlot 仅是 InheritedWidget，不提供 tight 约束。
/// 当 slot 处于 `Stack + Positioned`（不带 width/height）这种无界父容器时，
/// 子组件里的 `Column(CrossAxisAlignment.stretch)` 会因无限宽度崩溃。
/// 修复方法：ScaledSlot 增加可选 `constrain: true` 参数。
library;

import 'package:evergreen_base/renderer/components/shared/slot_scale.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ScaledSlot(constrain: true) 用 SizedBox 强制 tight 约束', (tester) async {
    double? measuredWidth;
    double? measuredHeight;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            // 无界父容器：模拟 Stack + Positioned 不带 width/height
            child: UnconstrainedBox(
              child: ScaledSlot(
                slotWidth: 300,
                slotHeight: 200,
                constrain: true,
                child: LayoutBuilder(
                  builder: (ctx, c) {
                    measuredWidth = c.maxWidth;
                    measuredHeight = c.maxHeight;
                    return Container(width: 300, height: 200, color: Colors.red);
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    // 因为 constrain: true 注入 SizedBox(300, 200)，子 LayoutBuilder
    // 收到的 maxWidth/maxHeight 应为 tight 的 300 / 200。
    expect(measuredWidth, 300.0);
    expect(measuredHeight, 200.0);
  });

  testWidgets('ScaledSlot(constrain: false) 保留旧行为：仅注入缩放上下文，不强制约束', (tester) async {
    double? measuredWidth;
    double? measuredHeight;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            // 提供 tight 约束的父容器
            child: SizedBox(
              width: 500,
              height: 400,
              child: ScaledSlot(
                slotWidth: 300,
                slotHeight: 200,
                constrain: false,  // 默认 false
                child: LayoutBuilder(
                  builder: (ctx, c) {
                    measuredWidth = c.maxWidth;
                    measuredHeight = c.maxHeight;
                    return Container();
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    // constrain: false 不强制 SizedBox，约束来自父容器（500x400）
    expect(measuredWidth, 500.0);
    expect(measuredHeight, 400.0);
  });

  testWidgets('ScaledSlot(constrain: true) Column(stretch) 在无界父容器下不崩溃', (tester) async {
    // 关键场景：Column with CrossAxisAlignment.stretch + 无界宽度
    // 原本会因 BoxConstraints(w=Infinity) 崩溃。
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: UnconstrainedBox(
              child: ScaledSlot(
                slotWidth: 200,
                slotHeight: 100,
                constrain: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(height: 30, color: Colors.red),
                    Container(height: 30, color: Colors.green),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    // 不抛异常即通过
    expect(tester.takeException(), isNull);
  });
}
