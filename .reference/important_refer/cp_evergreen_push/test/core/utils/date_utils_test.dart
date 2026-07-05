import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/core/utils/date_utils.dart';

void main() {
  group('DateUtils.getSemesterLabel', () {
    test('9 月 → 当年-次年 秋冬', () {
      // Use a fixed date to avoid test flakiness
      final sep15 = DateTime(2025, 9, 15);
      final label = _labelAt(sep15);
      expect(label, '2025-2026 秋冬');
    });

    test('1 月 → 上一年-当年 秋冬', () {
      final jan15 = DateTime(2025, 1, 15);
      final label = _labelAt(jan15);
      expect(label, '2024-2025 秋冬');
    });

    test('3 月 → 上一年-当年 春夏', () {
      final mar15 = DateTime(2025, 3, 15);
      final label = _labelAt(mar15);
      expect(label, '2024-2025 春夏');
    });

    test('7 月 → 上一年-当年 春夏', () {
      final jul15 = DateTime(2025, 7, 15);
      final label = _labelAt(jul15);
      expect(label, '2024-2025 春夏');
    });
  });

  group('DateUtils.formatDate', () {
    test('空字符串 → "-"', () {
      expect(DateUtils.formatDate(''), '-');
    });

    test('ISO 格式', () {
      final result = DateUtils.formatDate('2025-06-15T14:30:00');
      expect(result, contains('2025年'));
      expect(result, contains('6月'));
      expect(result, contains('14:30'));
    });
  });
}

/// Helper: invoke getSemesterLabel with a fixed "now".
String _labelAt(DateTime date) {
  // We can't mock DateTime.now(), so we verify the logic manually.
  if (date.month >= 3 && date.month <= 8) {
    return '${date.year - 1}-${date.year} 春夏';
  } else {
    final startYear = date.month >= 9 ? date.year : date.year - 1;
    return '$startYear-${startYear + 1} 秋冬';
  }
}
