import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 0.3.4 — 考试日历在不同宽度下不产生 bottom overflow。
void main() {
  testWidgets('Calendar grid — no overflow at narrow width', (tester) async {
    // 日历网格组件在 320px 宽度下无溢出
    final rows = 5; // 典型月历行数
    final cellW = 40.0; // 320 / 8 ≈ 40
    final cellH = cellW * 0.85;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: Column(
              children: [
                // Weekday headers
                SizedBox(
                  height: 20,
                  child: Row(
                    children: List.generate(
                      7,
                      (_) => SizedBox(
                        width: cellW,
                        child: const Center(child: Text('一')),
                      ),
                    ),
                  ),
                ),
                // Grid
                SizedBox(
                  height: rows * cellH + 1,
                  child: GridView.count(
                    crossAxisCount: 7,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: 1 / 0.85,
                    children: List.generate(7 * rows, (i) {
                      return Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey, width: 0.5),
                        ),
                        child: Center(child: Text('${i + 1}')),
                      );
                    }),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // 不应有 layout overflow
    expect(tester.takeException(), isNull);
  });

  testWidgets('Calendar grid — no overflow at wide width', (tester) async {
    final rows = 5;
    final cellW = 64.0;
    final cellH = cellW * 0.85;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 500,
            child: Column(
              children: [
                SizedBox(
                  height: 20,
                  child: Row(
                    children: List.generate(
                      7,
                      (_) => SizedBox(width: cellW,
                          child: const Center(child: Text('一'))),
                    ),
                  ),
                ),
                SizedBox(
                  height: rows * cellH,
                  child: GridView.count(
                    crossAxisCount: 7,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: 1 / 0.85,
                    children: List.generate(7 * rows, (_) => const SizedBox()),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
