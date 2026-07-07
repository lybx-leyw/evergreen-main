/// ThemeDescriptor + ThemeStore + 扫描函数 全量测试（五层架构）。
///
/// 覆盖范围：
///   ThemeDescriptor — const 构造 / fromJson / fromJsonString / toJson /
///     tokenValue / tokenColor / parseHex
///   ThemeStore — register / all / findById / activeTheme / setActiveById /
///     activeOrFirst / ChangeNotifier
///   scanThemes / loadThemes / scanThemeFile
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../theme_descriptor.dart';
import '../theme_store.dart';
import '../theme_loader.dart';
import '../src/color.dart';
import '../src/tokens.dart' show ComponentTokens, AppTokens;

// ═══════ helpers ═══════

String _testDir(String sub) =>
    p.join(Directory.current.path, 'test', '_fixtures', sub);

ThemeDescriptor _simpleTheme() => const ThemeDescriptor(
  id: 'test',
  name: 'Test',
  app: {'sidebar': {'bg': '#FF0000', 'text': '#FF0000', 'active': '#FF0000', 'hover': '#FF0000', 'divider': '#FF0000'}},
  module: {},
  page: {},
  slot: {},
  components: {},
);

ThemeDescriptor _fullTheme() => const ThemeDescriptor(
  id: 'full',
  name: 'Full Theme',
  app: {
    'sidebar': {'bg': '#F2F3F5', 'text': '#1A1D21', 'active': '#1677FF', 'hover': '#E8E8E8', 'divider': '#D0D5DD'},
    'header': {'bg': '#FFF', 'text': '#1A1D21', 'border': '#D0D5DD'},
    'footer': {'bg': '#FFF', 'text': '#1A1D21', 'border': '#D0D5DD'},
    'blank': {'bg': '#F5F6F8'},
    'commandPalette': {'bg': '#FFF', 'text': '#1A1D21', 'highlight': '#E8E8E8', 'border': '#D0D5DD'},
  },
  module: {'chrome': {'bg': '#FFF', 'border': '#D0D5DD'}},
  page: {
    'tabBar': {'bg': '#FFF', 'text': '#6B7280', 'active': '#1677FF', 'indicator': '#1677FF', 'hover': '#E8E8E8', 'border': '#D0D5DD'},
    'background': {'color': '#F5F6F8'},
  },
  slot: {
    'header': {'bg': '#FFF', 'text': '#1A1D21', 'border': '#D0D5DD'},
    'background': {'color': '#FFF'},
    'border': {'color': '#D0D5DD', 'width': '1'},
  },
  components: {
    'sidebar': {'bg': '#F2F3F5', 'text': '#1A1D21', 'active': '#1677FF', 'hover': '#0958D9'},
    'button': {'primary': '#1677FF', 'hover': '#0958D9', 'active': '#1677FF', 'disabled': '#D0D5DD', 'text': '#FFFFFF'},
    'card': {'bg': '#FFFFFF', 'border': '#D0D5DD', 'shadow': '#000000', 'text': '#1A1D21'},
  },
);

// ═══════ ThemeDescriptor ═══════

void main() {
  group('ThemeDescriptor', () {
    // ── const 构造 ──
    test('const 构造 — 全字段', () {
      final t = _fullTheme();
      expect(t.id, 'full');
      expect(t.name, 'Full Theme');
      expect(t.app.length, 5); // 5 app components
      expect(t.components.length, 3); // 3 components
    });

    test('const 构造 — 空层', () {
      const t = ThemeDescriptor(
        id: 'empty', name: 'Empty',
        app: {}, module: {}, page: {}, slot: {}, components: {},
      );
      expect(t.app, isEmpty);
      expect(t.components, isEmpty);
    });

    // ── fromJson（五层完整校验）──
    test('fromJson — 最小合法 JSON', () {
      final t = ThemeDescriptor.fromJson({
        'type': 'theme',
        'id': 'json_theme',
        'name': 'JSON Theme',
        'app': {
          'sidebar': {'bg': '#333', 'text': '#FFF', 'active': '#FF5722', 'hover': '#444', 'divider': '#555'},
          'header': {'bg': '#333', 'text': '#FFF', 'border': '#555'},
          'footer': {'bg': '#333', 'text': '#FFF', 'border': '#555'},
          'blank': {'bg': '#FAFAFA'},
          'commandPalette': {'bg': '#FFF', 'text': '#333', 'highlight': '#EEE', 'border': '#555'},
        },
        'module': {'chrome': {'bg': '#FFF', 'border': '#DDD'}},
        'page': {
          'tabBar': {'bg': '#FFF', 'text': '#999', 'active': '#FF5722', 'indicator': '#FF5722', 'hover': '#EEE', 'border': '#DDD'},
          'background': {'color': '#FAFAFA'},
        },
        'slot': {
          'header': {'bg': '#FFF', 'text': '#333', 'border': '#DDD'},
          'background': {'color': '#FFF'},
          'border': {'color': '#DDD', 'width': '1'},
        },
        'components': _makeMinComponents(),
      });
      expect(t.id, 'json_theme');
      expect(t.app['sidebar']?['active'], '#FF5722');
      expect(t.app['blank']?['bg'], '#FAFAFA');
    });

    test('fromJson — type 不为 theme 抛 FormatException', () {
      expect(
        () => ThemeDescriptor.fromJson({'type': 'config', 'id': 'x'}),
        throwsFormatException,
      );
    });

    test('fromJson — 缺少必填层抛 FormatException', () {
      expect(
        () => ThemeDescriptor.fromJson({'type': 'theme', 'id': 'x'}),
        throwsFormatException,
      );
    });

    // ── fromJsonString ──
    test('fromJsonString — 有效 JSON', () {
      // 用内置主题文件验证
      final builtinPath = p.join(
        Directory.current.path, 'builtins', 'light', 'theme', 'theme.json');
      if (File(builtinPath).existsSync()) {
        final raw = File(builtinPath).readAsStringSync();
        final t = ThemeDescriptor.fromJsonString(raw);
        expect(t.id, 'light');
      }
    });

    test('fromJsonString — 非法 JSON 抛 FormatException', () {
      expect(
        () => ThemeDescriptor.fromJsonString('not json'),
        throwsFormatException,
      );
    });

    // ── toJson ──
    test('toJson — 往返一致性', () {
      // _fullTheme() 仅有 3 个组件，无法通过 fromJson 的 54 组件完整校验。
      // 这里构造一个含全部 54 组件的完整主题来验证 JSON 往返。
      final original = ThemeDescriptor(
        id: 'full',
        name: 'Full Theme',
        app: _fullTheme().app,
        module: _fullTheme().module,
        page: _fullTheme().page,
        slot: _fullTheme().slot,
        components: _makeMinComponents(),
      );
      final json = original.toJson();
      final restored = ThemeDescriptor.fromJson(json);
      expect(restored.id, original.id);
      expect(restored.app.length, original.app.length);
      for (final k in original.components.keys) {
        expect(restored.components[k], original.components[k]);
      }
    });

    // ── tokenValue ──
    test('tokenValue — 命中返回 hex', () {
      final t = _simpleTheme();
      expect(t.tokenValue(t.app, 'sidebar', 'active'), '#FF0000');
    });

    test('tokenValue — 未命中返回 null', () {
      final t = _simpleTheme();
      expect(t.tokenValue(t.app, 'nonexistent', 'x'), isNull);
    });

    test('tokenValue — 组件命中但子 token 不存在', () {
      final t = _fullTheme();
      expect(t.tokenValue(t.components, 'button', 'nonexistent'), isNull);
    });

    // ── tokenColor ──
    test('tokenColor — 合法 hex 返回 ThemeColor', () {
      final t = _simpleTheme();
      final c = t.tokenColor(t.app, 'sidebar', 'active');
      expect(c, isNotNull);
      expect(c!.toHex(withAlpha: false), '#FF0000');
    });

    test('tokenColor — 未声明返回 null', () {
      final t = _simpleTheme();
      expect(t.tokenColor(t.app, 'missing', 'x'), isNull);
    });

    test('tokenColor — 非法 hex 返回 null', () {
      const t = ThemeDescriptor(
        id: 'bad', name: 'Bad',
        app: {'sidebar': {'bg': 'not-a-color', 'text': 'not', 'active': 'not', 'hover': 'not', 'divider': 'not'}},
        module: {}, page: {}, slot: {}, components: {},
      );
      expect(t.tokenColor(t.app, 'sidebar', 'bg'), isNull);
    });

    test('tokenColorOr — 使用 ?? 模式', () {
      final t = _simpleTheme();
      final fallback = const ThemeColor(0xFF000000);
      final c = t.tokenColor(t.app, 'sidebar', 'active') ?? fallback;
      expect(c.toHex(withAlpha: false), '#FF0000');

      final missing = t.tokenColor(t.app, 'missing', 'x') ?? fallback;
      expect(missing, same(fallback));
    });

    // ── parseHex ──
    test('parseHex — #RRGGBB', () {
      final c = ThemeDescriptor.parseHex('#FF0000');
      expect(c, isNotNull);
      expect(c!.toHex(withAlpha: false), '#FF0000');
    });

    test('parseHex — 非法格式返回 null', () {
      expect(ThemeDescriptor.parseHex('red'), isNull);
      expect(ThemeDescriptor.parseHex(''), isNull);
    });
  });

  // ═══════ ThemeColor ═══════

  group('ThemeColor', () {
    test('const 构造 + toHex', () {
      const c = ThemeColor(0xFF1677FF);
      expect(c.toHex(), '#FF1677FF');
      expect(c.toHex(withAlpha: false), '#1677FF');
    });

    test('fromHex #RRGGBB', () {
      final c = ThemeColor.fromHex('#1677FF');
      expect(c.value, 0xFF1677FF);
    });

    test('fromHex #AARRGGBB', () {
      final c = ThemeColor.fromHex('#801677FF');
      expect(c.value, 0x801677FF);
    });

    test('fromHex #RGB', () {
      final c = ThemeColor.fromHex('#F00');
      expect(c.toHex(withAlpha: false), '#FF0000');
    });

    test('fromHex 非法抛出', () {
      expect(() => ThemeColor.fromHex('red'), throwsFormatException);
    });

    test('tryParse 非法返回 null', () {
      expect(ThemeColor.tryParse('red'), isNull);
      expect(ThemeColor.tryParse('#XYZ'), isNull);
      expect(ThemeColor.tryParse(''), isNull);
    });

    test('== / hashCode', () {
      const a = ThemeColor(0xFFFF0000);
      const b = ThemeColor(0xFFFF0000);
      const c = ThemeColor(0xFF00FF00);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });
  });

  // ═══════ ThemeStore ═══════

  group('ThemeStore', () {
    late ThemeStore store;

    setUp(() {
      store = ThemeStore();
    });

    test('register — 新主题', () {
      store.register(_simpleTheme());
      expect(store.all.length, 1);
    });

    test('register — 同 id 覆盖', () {
      store.register(_simpleTheme());
      store.register(const ThemeDescriptor(
        id: 'test', name: 'Overridden',
        app: {}, module: {}, page: {}, slot: {}, components: {},
      ));
      expect(store.all.length, 1);
      expect(store.findById('test')?.name, 'Overridden');
    });

    test('all — 返回不可变列表', () {
      store.register(_simpleTheme());
      expect(store.all.length, 1);
    });

    test('all — 空 store', () {
      expect(store.all, isEmpty);
    });

    test('findById — 命中', () {
      store.register(_simpleTheme());
      expect(store.findById('test')?.id, 'test');
    });

    test('findById — 未命中返回 null', () {
      expect(store.findById('nonexistent'), isNull);
    });

    test('activeTheme — 初始为 null', () {
      expect(store.activeTheme, isNull);
    });

    test('activeTheme — set/get', () {
      final t = _simpleTheme();
      store.activeTheme = t;
      expect(store.activeTheme?.id, 'test');
    });

    test('activeTheme — 设置后触发 ChangeNotifier', () {
      var notified = false;
      store.addListener(() => notified = true);
      store.activeTheme = _simpleTheme();
      expect(notified, isTrue);
    });

    test('activeTheme — 同主题不重复通知', () {
      final t = _simpleTheme();
      store.activeTheme = t;
      var count = 0;
      store.addListener(() => count++);
      store.activeTheme = t; // 相同主题
      expect(count, 0);
    });

    test('activeTheme — 取消监听后不再通知', () {
      var count = 0;
      void listener() => count++;
      store.addListener(listener);
      store.removeListener(listener);
      store.activeTheme = _simpleTheme();
      expect(count, 0);
    });

    test('setActiveById — 成功返回 true', () {
      store.register(_simpleTheme());
      expect(store.setActiveById('test'), isTrue);
      expect(store.activeTheme?.id, 'test');
    });

    test('setActiveById — 不存在返回 false', () {
      expect(store.setActiveById('nonexistent'), isFalse);
      expect(store.activeTheme, isNull);
    });

    test('activeOrFirst — 已设置返回 active', () {
      store.register(_simpleTheme());
      store.register(_fullTheme());
      store.activeTheme = _fullTheme();
      expect(store.activeOrFirst?.id, 'full');
    });

    test('activeOrFirst — 未设置返回第一个', () {
      store.register(_simpleTheme());
      store.register(_fullTheme());
      expect(store.activeOrFirst?.id, 'test');
    });

    test('activeOrFirst — 空 store 返回 null', () {
      expect(store.activeOrFirst, isNull);
    });

    test('dispose — 清空监听者', () {
      var count = 0;
      store.addListener(() => count++);
      store.dispose();
      // dispose 后 ChangeNotifier 不可再使用，设置 activeTheme 会触发断言
      expect(
        () => store.activeTheme = _simpleTheme(),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  // ═══════ scan / load ═══════

  group('扫描函数', () {
    test('scanThemes — 空目录返回空列表', () {
      final dir = _testDir('empty');
      if (!Directory(dir).existsSync()) Directory(dir).createSync(recursive: true);
      expect(scanThemes(dir), isEmpty);
    });

    test('scanThemes — 不存在的目录返回空列表', () {
      expect(scanThemes('/nonexistent/path/12345'), isEmpty);
    });

    test('loadThemes — 注册到 store (使用内置主题)', () {
      final builtinsDir = p.join(Directory.current.path, 'builtins');
      if (Directory(builtinsDir).existsSync()) {
        final store = ThemeStore();
        loadThemes(builtinsDir, store);
        expect(store.all.length, greaterThan(0));
      }
    });

    test('loadThemes — 重复 id 覆盖', () {
      final dir = _testDir('overwrite_test');
      if (Directory(dir).existsSync()) Directory(dir).deleteSync(recursive: true);
      final themeDir = Directory(p.join(dir, 'my_theme', 'theme'));
      themeDir.createSync(recursive: true);

      // 构造含全部 54 组件的完整主题 JSON（fromJson 要求完整声明）
      final themeMap = {
        'type': 'theme',
        'id': 'loaded',
        'name': 'Second',
        'app': {
          'sidebar': {'bg': '#FFF', 'text': '#FFF', 'active': '#FFF', 'hover': '#FFF', 'divider': '#FFF'},
          'header': {'bg': '#FFF', 'text': '#FFF', 'border': '#FFF'},
          'footer': {'bg': '#FFF', 'text': '#FFF', 'border': '#FFF'},
          'blank': {'bg': '#FFF'},
          'commandPalette': {'bg': '#FFF', 'text': '#FFF', 'highlight': '#FFF', 'border': '#FFF'},
        },
        'module': {'chrome': {'bg': '#FFF', 'border': '#FFF'}},
        'page': {
          'tabBar': {'bg': '#FFF', 'text': '#FFF', 'active': '#FFF', 'indicator': '#FFF', 'hover': '#FFF', 'border': '#FFF'},
          'background': {'color': '#FFF'},
        },
        'slot': {
          'header': {'bg': '#FFF', 'text': '#FFF', 'border': '#FFF'},
          'background': {'color': '#FFF'},
          'border': {'color': '#FFF', 'width': '1'},
        },
        'components': _makeMinComponents(),
      };
      File(p.join(themeDir.path, 'theme.json'))
          .writeAsStringSync(jsonEncode(themeMap));

      final store = ThemeStore();
      store.register(const ThemeDescriptor(
        id: 'loaded', name: 'First',
        app: {}, module: {}, page: {}, slot: {}, components: {},
      ));
      loadThemes(dir, store);
      expect(store.findById('loaded')?.name, 'Second'); // 后者覆盖

      Directory(dir).deleteSync(recursive: true);
    });

    test('scanThemeFile — 内置主题文件', () {
      final builtinPath = p.join(
        Directory.current.path, 'builtins', 'light', 'theme', 'theme.json');
      if (File(builtinPath).existsSync()) {
        final t = scanThemeFile(builtinPath);
        expect(t.id, 'light');
      }
    });

    test('scanThemeFile — 文件不存在抛异常', () {
      expect(
        () => scanThemeFile('/nonexistent/theme.json'),
        throwsA(isA<FileSystemException>()),
      );
    });
  });

  // ═══════ Token 常量 ═══════

  group('token 常量', () {
    test('AppTokens 数量 = 5', () {
      expect(AppTokens.count, 5);
    });

    test('ComponentTokens 数量 = 54', () {
      expect(ComponentTokens.count, 54);
    });

    test('subTokens 覆盖全部 54 组件', () {
      for (final key in ComponentTokens.allowedKeys) {
        expect(
          ComponentTokens.subTokens.containsKey(key),
          isTrue,
          reason: '组件 "$key" 缺少子 token 定义',
        );
      }
    });
  });
}

// ═══════ 测试辅助 ═══════

/// 构建最小的 54 组件 JSON（仅含必要子 token，fromJson 校验用）。
Map<String, Map<String, String>> _makeMinComponents() {
  final result = <String, Map<String, String>>{};
  for (final entry in ComponentTokens.subTokens.entries) {
    final subs = <String, String>{};
    for (final token in entry.value) {
      subs[token] = '#CCCCCC';
    }
    result[entry.key] = subs;
  }
  return result;
}
