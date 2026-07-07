/// Token 完整性 + 内置主题 验证测试。
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
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

/// 递归检查五层 JSON 中所有 hex 值。
void _checkAllHex(Map<String, dynamic> json, String label) {
  // 遍历 app/module/page/slot/components 五层
  for (final layerKey in ['app', 'module', 'page', 'slot', 'components']) {
    final layer = json[layerKey];
    if (layer is! Map<String, dynamic>) continue;
    for (final comp in layer.entries) {
      if (comp.value is Map) {
        for (final tok in (comp.value as Map).entries) {
          final val = tok.value.toString();
          // 跳过非颜色 token（thickness、width、数组等）
          if (_isNonColorToken(comp.key.toString(), tok.key.toString())) continue;
          expect(isValidHexColor(val), isTrue,
              reason: '$label $layerKey.${comp.key}.${tok.key} 颜色格式非法: $val');
        }
      }
    }
  }
}

bool _isNonColorToken(String component, String subToken) {
  const nonColor = <String, Set<String>>{
    'divider': {'thickness', 'width'},
    'border': {'width'},
    'chart': {'colors'},
  };
  return nonColor[component]?.contains(subToken) ?? false;
}

// ═══════ tests ═══════

void main() {
  group('token 完整性', () {
    test('AppTokens.allowedKeys 包含 5 个 key', () {
      expect(AppTokens.count, 5);
      expect(AppTokens.allowedKeys, hasLength(5));
    });

    test('ComponentTokens.allowedKeys 包含 54 个 key', () {
      expect(ComponentTokens.count, 54);
      expect(ComponentTokens.allowedKeys, hasLength(54));
    });

    test('App token 无重复', () {
      expect(
        AppTokens.allowedKeys.length,
        AppTokens.allowedKeys.toSet().length,
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
    test('light.json — App 层完整', () {
      final json = _loadJson(_themePath('light'));
      final app = json['app'] as Map<String, dynamic>;
      for (final expected in AppTokens.allowedKeys) {
        expect(app.containsKey(expected), isTrue,
            reason: 'light.json app 层缺少组件: $expected');
      }
    });

    test('dark.json — App 层完整', () {
      final json = _loadJson(_themePath('dark'));
      final app = json['app'] as Map<String, dynamic>;
      for (final expected in AppTokens.allowedKeys) {
        expect(app.containsKey(expected), isTrue,
            reason: 'dark.json app 层缺少组件: $expected');
      }
    });

    test('light.json — 所有颜色值合法 hex', () {
      final json = _loadJson(_themePath('light'));
      _checkAllHex(json, 'light.json');
    });

    test('dark.json — 所有颜色值合法 hex', () {
      final json = _loadJson(_themePath('dark'));
      _checkAllHex(json, 'dark.json');
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
