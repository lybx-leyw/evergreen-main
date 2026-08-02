/// 扁平语义色板 验证测试（主题扁平化改造后）。
library;

import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;

import '../theme_descriptor.dart';
import '../src/color.dart';

// ═══════ helpers ═══════

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

/// 各示例主题相对**子包根**（lib/core/theme）的路径。
/// my_theme 在 theme 子包 example 内；ocean_theme 在 core 根 example 内。
const _themePaths = <String, List<String>>{
  'my_theme': [
    'example',
    'plugins',
    'my_theme',
    'theme',
    'theme.json',
  ],
  'ocean_theme': [
    '..',
    'example',
    'plugins',
    'ocean_theme',
    'theme',
    'theme.json',
  ],
};

String _exampleThemePath(String plugin) => p.normalize(
    p.joinAll([Directory.current.path, ..._themePaths[plugin]!]));

Map<String, dynamic> _loadJson(String path) {
  final raw = File(path).readAsStringSync();
  return jsonDecode(raw) as Map<String, dynamic>;
}

bool _isValidHex(String val) => ThemeDescriptor.parseHex(val) != null;

// ═══════ tests ═══════

void main() {
  group('扁平主题 — 内置示例色板', () {
    for (final plugin in ['my_theme', 'ocean_theme']) {
      test('$plugin theme.json — 8 个必填语义色齐全', () {
        final json = _loadJson(_exampleThemePath(plugin));
        final colors = (json['colors'] as Map<String, dynamic>?);
        expect(colors, isNotNull, reason: '$plugin 缺少 colors 字段');
        for (final key in _requiredKeys) {
          expect(colors!.containsKey(key), isTrue,
              reason: '$plugin 缺少必填语义色: $key');
        }
        // 不应出现非约定的额外语义色
        for (final extra in colors!.keys) {
          expect(_requiredKeys.contains(extra), isTrue,
              reason: '$plugin 含未约定语义色: $extra');
        }
      });

      test('$plugin theme.json — 所有颜色值合法 hex', () {
        final json = _loadJson(_exampleThemePath(plugin));
        final colors = json['colors'] as Map<String, dynamic>;
        for (final e in colors.entries) {
          expect(_isValidHex(e.value.toString()), isTrue,
              reason: '$plugin colors.${e.key} 颜色格式非法: ${e.value}');
        }
      });

      test('$plugin theme.json — 可经 ThemeDescriptor.fromJson 解析', () {
        final json = _loadJson(_exampleThemePath(plugin));
        final theme = ThemeDescriptor.fromJson(json);
        expect(theme.id, isNotEmpty);
        expect(theme.colors.length, _requiredKeys.length);
        expect(theme.color('accent'), isNotNull);
      });
    }
  });

  group('ThemeColor hex 往返', () {
    test('#RRGGBB 往返', () {
      const cases = ['#000000', '#FFFFFF', '#1677FF', '#FF4D4F'];
      for (final hex in cases) {
        final c = ThemeColor.fromHex(hex);
        expect(c.toHex(withAlpha: false), hex);
      }
    });

    test('#AARRGGBB 往返', () {
      const cases = ['#FF000000', '#80FFFFFF', '#FF1677FF'];
      for (final hex in cases) {
        final c = ThemeColor.fromHex(hex);
        expect(c.toHex(), hex.toUpperCase());
      }
    });

    test('tryParse 对非法格式返回 null', () {
      expect(ThemeColor.tryParse('nope'), isNull);
      expect(ThemeColor.tryParse(''), isNull);
    });
  });
}
