import 'package:flutter_test/flutter_test.dart';

/// 0.4.1 — 侧栏红点不包含已过期项。
void main() {
  group('Badge — expired filter', () {
    // 模拟 _ExpandedSidebar 的逻辑
    int countUrgent(List<DateTime?> deadlines, int maxDays) {
      final now = DateTime(2026, 6, 12);
      return deadlines.where((d) {
        if (d == null) return false;
        if (d.isBefore(now)) return false; // 排除已过期
        final diffDays = d.difference(now).inDays;
        return diffDays >= 0 && diffDays <= maxDays;
      }).length;
    }

    test('过期项不计入红点', () {
      final now = DateTime(2026, 6, 12);
      final deadlines = [
        now.subtract(const Duration(days: 3)),  // 过去 — 排除
        now.add(const Duration(days: 2)),       // 2天后 ✓
        now.add(const Duration(days: 10)),      // 10天后 — 超出7天范围
        now.add(const Duration(days: 5)),       // 5天后 ✓
      ];
      expect(countUrgent(deadlines, 7), 2); // 只有 #2 和 #4
    });

    test('今天截止的计入', () {
      final now = DateTime(2026, 6, 12);
      expect(countUrgent([now], 7), 1);
    });

    test('正好第7天的计入', () {
      final now = DateTime(2026, 6, 12);
      expect(countUrgent([now.add(const Duration(days: 7))], 7), 1);
    });

    test('第8天的不计入', () {
      final now = DateTime(2026, 6, 12);
      expect(countUrgent([now.add(const Duration(days: 8))], 7), 0);
    });

    test('全过期 = 0', () {
      final now = DateTime(2026, 6, 12);
      final deadlines = [
        now.subtract(const Duration(days: 30)),
        now.subtract(const Duration(days: 1)),
      ];
      expect(countUrgent(deadlines, 7), 0);
    });
  });
}
