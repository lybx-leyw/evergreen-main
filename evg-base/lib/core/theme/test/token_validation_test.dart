/// Token 完整性 + 内置主题 验证测试。
library;

import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;

import '../src/tokens.dart';
import '../src/color.dart';

// ═══════ helpers ═══════

String _themePath(String name) =>
    p.join(Directory.current.path, 'builtins', name, 'theme', 'theme.json');

Map<String, dynamic> _loadJson(String path) {
  final raw = File(path).readAsStringSync();
  return jsonDecode(raw) as Map<String, dynamic>;
}

// ═══════ tests ═══════

void main() {
  group('token 完整性', () {
    test('SemanticTokens.allowedKeys 包含 20 个 key', () {
      expect(SemanticTokens.count, 20);
      expect(SemanticTokens.allowedKeys, hasLength(20));
    });

    test('ComponentTokens.allowedKeys 包含 54 个 key', () {
      expect(ComponentTokens.count, 54);
      expect(ComponentTokens.allowedKeys, hasLength(54));
    });

    test('语义 token 无重复', () {
      expect(
        SemanticTokens.allowedKeys.length,
        SemanticTokens.allowedKeys.toSet().length,
      );
    });

    test('组件 token 无重复', () {
      expect(
        ComponentTokens.allowedKeys.length,
        ComponentTokens.allowedKeys.toSet().length,
      );
    });

    test('ComponentTokens.subTokens 覆盖全部 54 组件', () {
      for (final key in ComponentTokens.allowedKeys) {
        final subs = ComponentTokens.subTokensFor(key);
        expect(subs, isNotEmpty,
            reason: '组件 "$key" 缺少子 token 定义');
      }
    });
  });

  group('内置主题', () {
    test('light.json — 语义 token 全覆盖 20 个', () {
      final json = _loadJson(_themePath('light'));
      final colors = json['colors'] as Map<String, dynamic>;
      final semanticKeys = colors.keys
          .where((k) => colors[k] is String)
          .toList();
      for (final expected in SemanticTokens.allowedKeys) {
        expect(semanticKeys, contains(expected),
            reason: 'light.json 缺少语义 token: $expected');
      }
    });

    test('dark.json — 语义 token 全覆盖 20 个', () {
      final json = _loadJson(_themePath('dark'));
      final colors = json['colors'] as Map<String, dynamic>;
      final semanticKeys = colors.keys
          .where((k) => colors[k] is String)
          .toList();
      for (final expected in SemanticTokens.allowedKeys) {
        expect(semanticKeys, contains(expected),
            reason: 'dark.json 缺少语义 token: $expected');
      }
    });

    test('light.json — 所有颜色值合法 hex', () {
      final json = _loadJson(_themePath('light'));
      final colors = json['colors'] as Map<String, dynamic>;
      for (final e in colors.entries) {
        if (e.value is String) {
          expect(isValidHexColor(e.value as String), isTrue,
              reason: 'light.json 语义 token "${e.key}" 颜色格式非法: ${e.value}');
        } else if (e.value is Map) {
          for (final se in (e.value as Map).entries) {
            expect(isValidHexColor(se.value.toString()), isTrue,
                reason: 'light.json 组件 token "${e.key}.${se.key}" 颜色格式非法: ${se.value}');
          }
        }
      }
    });

    test('dark.json — 所有颜色值合法 hex', () {
      final json = _loadJson(_themePath('dark'));
      final colors = json['colors'] as Map<String, dynamic>;
      for (final e in colors.entries) {
        if (e.value is String) {
          expect(isValidHexColor(e.value as String), isTrue,
              reason: 'dark.json 语义 token "${e.key}" 颜色格式非法: ${e.value}');
        } else if (e.value is Map) {
          for (final se in (e.value as Map).entries) {
            expect(isValidHexColor(se.value.toString()), isTrue,
                reason: 'dark.json 组件 token "${e.key}.${se.key}" 颜色格式非法: ${se.value}');
          }
        }
      }
    });

    test('light.json — type=theme', () {
      final json = _loadJson(_themePath('light'));
      expect(json['type'], 'theme');
    });

    test('dark.json — type=theme', () {
      final json = _loadJson(_themePath('dark'));
      expect(json['type'], 'theme');
    });
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
  });
}
