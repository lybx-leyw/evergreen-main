/// Date formatting and semester calculation utilities.
class DateUtils {
  /// Format a date string into human-readable Chinese date.
  static String formatDate(String dateStr) {
    if (dateStr.isEmpty) return '-';

    DateTime? date;

    if (dateStr.contains('-') || dateStr.contains('T')) {
      date = DateTime.tryParse(dateStr);
    }

    if (date == null) {
      final ts = int.tryParse(dateStr);
      if (ts != null) {
        date = DateTime.fromMillisecondsSinceEpoch(
            ts > 1e12 ? ts : ts * 1000);
      }
    }

    if (date == null) return dateStr;

    return '${date.year}年${date.month}月${date.day}日 '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }

  /// Format a DateTime relative to now (Chinese).
  static String formatRelative(DateTime date) {
    final now = DateTime.now();
    final diff = date.difference(now);

    if (diff.inSeconds < 0) return '已过期';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟后';
    if (diff.inHours < 24) {
      return '${diff.inHours}小时${diff.inMinutes.remainder(60)}分钟后';
    }
    if (diff.inDays < 30) {
      return '${diff.inDays}天${diff.inHours.remainder(24)}小时后';
    }
    return formatDate(date.toIso8601String());
  }

  /// Get the default semester start date.
  ///
  /// ZJU 学期划分：秋冬 9 月~次年 2 月，春夏 3 月~8 月。
  /// 1 月归属于**上一年的秋冬学期**。
  static DateTime getSemesterStart() {
    final now = DateTime.now();
    if (now.month >= 3 && now.month <= 8) {
      // 春夏学期：3 月 1 日
      return DateTime(now.year, 3, 1);
    } else {
      // 秋冬学期：9 月 1 日
      return DateTime(now.year, 9, 1);
    }
  }

  /// Get semester label (e.g., "2025-2026 秋冬").
  ///
  /// ZJU 学年从秋季开始：2025 年 9 月 → "2025-2026 秋冬"
  /// 1 月仍属于上一年的秋冬学期。
  static String getSemesterLabel() {
    final now = DateTime.now();
    if (now.month >= 3 && now.month <= 8) {
      // 春夏学期：2025 年 3 月 → "2024-2025 春夏"
      return '${now.year - 1}-${now.year} 春夏';
    } else {
      // 秋冬学期：2025 年 9 月 或 2026 年 1 月 → "2025-2026 秋冬"
      final startYear = now.month >= 9 ? now.year : now.year - 1;
      return '$startYear-${startYear + 1} 秋冬';
    }
  }
}
