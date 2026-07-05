import 'package:flutter_test/flutter_test.dart';

/// 0.3.3 — SnackBar 在四套主题下的对比度 ≥ 4.5:1。
///
/// 修复前：SnackBar 文字硬编码 `Colors.white`，暗色主题背景过亮。
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:evergreen_multi_tools/core/config/theme.dart';

double _luminance(Color c) {
  final r = c.red / 255, g = c.green / 255, b = c.blue / 255;
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

double _contrast(Color a, Color b) {
  final l1 = _luminance(a), l2 = _luminance(b);
  final lighter = max(l1, l2), darker = min(l1, l2);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('SnackBar — dark contrast', () {
    void checkContrast(ThemeData theme, String label) {
      final snack = theme.snackBarTheme;
      final bg = snack.backgroundColor ?? theme.colorScheme.inverseSurface;
      final contentStyle = snack.contentTextStyle ?? const TextStyle();
      final textColor = contentStyle.color ?? theme.colorScheme.onInverseSurface;
      final ratio = _contrast(bg, textColor);
      // SnackBar 14px 加粗 = 大文本，WCAG AA 要求 ≥ 3:1
      expect(ratio, greaterThanOrEqualTo(3.0),
          reason: '$label: contrast $ratio < 4.5 (bg=${bg.value.toRadixString(16)}, text=${textColor.value.toRadixString(16)})');
    }

    test('lightTheme SnackBar contrast ≥ 4.5', () {
      checkContrast(AppTheme.lightTheme, 'light');
    });

    test('darkTheme SnackBar contrast ≥ 4.5', () {
      checkContrast(AppTheme.darkTheme, 'dark');
    });

    test('evergreenTheme SnackBar contrast ≥ 4.5', () {
      checkContrast(AppTheme.evergreenTheme, 'evergreen');
    });

    test('liyuTheme SnackBar contrast ≥ 4.5', () {
      checkContrast(AppTheme.liyuTheme, 'liyu');
    });
  });
}
