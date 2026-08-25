/// 内置主题完整性测试——扁平 8 色模型。
///
/// 覆盖：2 个内置主题（dark / light）齐全 / 8 个必填语义色齐全 / hex 合法 /
/// 可经 ThemeDescriptor.fromJson 往返 / registerBuiltinThemes 幂等注册。
library;

import 'package:test/test.dart';
import '../theme_descriptor.dart';
import '../theme_store.dart';
import '../builtin_themes.dart';

const _requiredKeys = <String>[
  'background',
  'surface',
  'border',
  'text',
  'textSecondary',
  'accent',
  'error',
  'others',
];

void main() {
  group('builtinThemes', () {
    test('包含 2 个内置主题：dark / light', () {
      expect(builtinThemes.length, 2);
      final ids = builtinThemes.map((t) => t.id).toSet();
      expect(ids, containsAll(['dark', 'light']));
    });

    test('每个主题 8 个必填语义色齐全且无多余键', () {
      for (final t in builtinThemes) {
        expect(t.colors.length, _requiredKeys.length,
            reason: '${t.id} colors 键数应为 ${_requiredKeys.length}');
        for (final key in _requiredKeys) {
          expect(t.colors.containsKey(key), isTrue,
              reason: '${t.id} 缺少必填语义色: $key');
        }
      }
    });

    test('每个主题颜色值均为合法 hex', () {
      for (final t in builtinThemes) {
        for (final e in t.colors.entries) {
          expect(ThemeDescriptor.parseHex(e.value), isNotNull,
              reason: '${t.id} colors.${e.key} 颜色格式非法: ${e.value}');
        }
      }
    });

    test('可经 fromJson/toJson 往返', () {
      for (final t in builtinThemes) {
        final restored = ThemeDescriptor.fromJson(t.toJson());
        expect(restored.id, t.id);
        expect(restored.colors, t.colors);
      }
    });
  });

  group('registerBuiltinThemes', () {
    test('注册 2 个内置主题到 store', () {
      final store = ThemeStore();
      registerBuiltinThemes(store);
      expect(store.all.length, 2);
      expect(store.findById('dark'), isNotNull);
      expect(store.findById('light'), isNotNull);
    });

    test('幂等：重复注册不增加数量（同 id 覆盖）', () {
      final store = ThemeStore();
      registerBuiltinThemes(store);
      registerBuiltinThemes(store);
      expect(store.all.length, 2);
    });

    test('默认激活：dark 在未设置时为首选（activeOrFirst）', () {
      final store = ThemeStore();
      registerBuiltinThemes(store);
      // 注册顺序 dark 在前 → 未设置活跃时 activeOrFirst 返回 dark
      expect(store.activeOrFirst?.id, 'dark');
    });
  });
}
