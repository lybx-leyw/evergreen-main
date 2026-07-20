/// icon 解析兜底验证：不可解析的 icon 名称应兜底为默认值，未提供仍保持 null。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';

void main() {
  group('icon 解析兜底', () {
    test('未提供的 icon 仍为 null', () {
      final d = ModuleDescriptor.fromJson({
        'type': 'module',
        'id': 'noicon',
        'name': '无图标模块',
      });
      expect(d.icon, isNull);
    });

    test('未知 icon 名称兜底为默认值 (kDefaultIcon)', () {
      final d = ModuleDescriptor.fromJson({
        'type': 'module',
        'id': 'unknownicon',
        'name': '未知图标模块',
        'icon': 'movie', // 不在 _iconMap 中的名称
      });
      expect(d.icon, isNotNull);
      expect(d.icon, kDefaultIcon);
    });

    test('合法 icon 名称仍按映射解析', () {
      final d = ModuleDescriptor.fromJson({
        'type': 'module',
        'id': 'knownicon',
        'name': '已知图标模块',
        'icon': 'smart_toy',
      });
      expect(d.icon, 0xf06c);
    });

    test('合法 codePoint (int/hex) 原样返回', () {
      final d = ModuleDescriptor.fromJson({
        'type': 'module',
        'id': 'inticon',
        'name': '整数图标模块',
        'icon': 0xe873,
      });
      expect(d.icon, 0xe873);
    });
  });
}
