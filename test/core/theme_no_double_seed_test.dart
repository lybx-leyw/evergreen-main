import 'package:flutter_test/flutter_test.dart';

/// 0.3.1 — ThemeData 不能同时设置 colorScheme 和 colorSchemeSeed。
///
/// 修复前：darkTheme 同时设置了 colorScheme 和 colorSchemeSeed，
/// Flutter Material 3 断言崩溃。
import 'package:evergreen_multi_tools/core/config/theme.dart';

void main() {
  group('Theme — no double seed', () {
    test('lightTheme 构建成功', () {
      expect(() => AppTheme.lightTheme, returnsNormally);
    });

    test('darkTheme 构建成功', () {
      expect(() => AppTheme.darkTheme, returnsNormally);
    });

    test('evergreenTheme 构建成功', () {
      expect(() => AppTheme.evergreenTheme, returnsNormally);
    });

    test('liyuTheme 构建成功', () {
      expect(() => AppTheme.liyuTheme, returnsNormally);
    });

    test('darkTheme colorScheme.primaryContainer 对比度可达', () {
      final theme = AppTheme.darkTheme;
      final cs = theme.colorScheme;
      // 验证 primaryContainer 与 primary 的对比度不会是纯黑/纯白极端
      expect(cs.primaryContainer, isNotNull);
      expect(cs.primary, isNotNull);
      expect(cs.primaryContainer.value, isNot(0xFF000000));
      expect(cs.primaryContainer.value, isNot(0xFFFFFFFF));
    });
  });
}
