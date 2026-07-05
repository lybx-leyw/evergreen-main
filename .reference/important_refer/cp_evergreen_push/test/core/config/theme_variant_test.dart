import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/core/config/theme.dart';

void main() {
  group('ThemeVariantStorage', () {
    test('toStorageKey → fromStorageKey 往返一致', () {
      for (final variant in ThemeVariant.values) {
        final key = variant.toStorageKey();
        final restored = ThemeVariantStorage.fromStorageKey(key);
        expect(restored, variant,
            reason: '$variant → "$key" → $restored');
      }
    });

    test('fromStorageKey 无效键回退到 system', () {
      expect(
        ThemeVariantStorage.fromStorageKey('invalid_key'),
        ThemeVariant.system,
      );
    });

    test('fromStorageKey 空字符串回退到 system', () {
      expect(
        ThemeVariantStorage.fromStorageKey(''),
        ThemeVariant.system,
      );
    });
  });
}
