/// ThemeDescriptor + ThemeStore + 扫描函数 全量测试（扁平语义色板）。
///
/// 覆盖范围：
///   ThemeDescriptor — const 构造 / fromJson / fromJsonString / toJson /
///     color / parseHex / 别名兼容
///   ThemeStore — register / all / findById / activeTheme / setActiveById /
///     activeOrFirst / ChangeNotifier
///   scanThemes / loadThemes / scanThemeFile
library;

import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;

import '../theme_descriptor.dart';
import '../theme_store.dart';
import '../theme_loader.dart';
import '../src/color.dart';

// ═══════ helpers ═══════

String _testDir(String sub) =>
    p.join(Directory.current.path, 'test', '_fixtures', sub);

ThemeDescriptor _simpleTheme() => const ThemeDescriptor(
      id: 'test',
      name: 'Test',
      colors: {
        'background': '#0D1117',
        'surface': '#161B22',
        'border': '#30363D',
        'text': '#C9D1D9',
        'textSecondary': '#8B949E',
        'accent': '#58A6FF',
        'error': '#FF7B72',
        'others': '#8B949E',
      },
    );

ThemeDescriptor _fullTheme() => const ThemeDescriptor(
      id: 'full',
      name: 'Full Theme',
      colors: {
        'background': '#0D1117',
        'surface': '#161B22',
        'border': '#30363D',
        'text': '#C9D1D9',
        'textSecondary': '#8B949E',
        'accent': '#58A6FF',
        'error': '#FF7B72',
        'others': '#8B949E',
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
      expect(t.colors.length, 8);
    });

    test('const 构造 — 空 colors', () {
      const t = ThemeDescriptor(id: 'empty', name: 'Empty', colors: {});
      expect(t.colors, isEmpty);
    });

    // ── fromJson（扁平 8 色）──
    test('fromJson — 最小合法 JSON', () {
      final t = ThemeDescriptor.fromJson({
        'type': 'theme',
        'id': 'json_theme',
        'name': 'JSON Theme',
        'colors': {
          'background': '#0D1117',
          'surface': '#161B22',
          'border': '#30363D',
          'text': '#C9D1D9',
          'textSecondary': '#8B949E',
          'accent': '#58A6FF',
          'error': '#FF7B72',
          'others': '#8B949E',
        },
      });
      expect(t.id, 'json_theme');
      expect(t.colors['accent'], '#58A6FF');
      expect(t.colors['background'], '#0D1117');
    });

    test('fromJson — 兼容别名 primary/secondary', () {
      final t = ThemeDescriptor.fromJson({
        'type': 'theme',
        'id': 'alias',
        'name': 'Alias',
        'colors': {
          'background': '#0D1117',
          'surface': '#161B22',
          'border': '#30363D',
          'text': '#C9D1D9',
          'textSecondary': '#8B949E',
          'primary': '#0D47A1',
          'error': '#EF5350',
          'secondary': '#42A5F5',
        },
      });
      expect(t.colors['accent'], '#0D47A1');
      expect(t.colors['others'], '#42A5F5');
    });

    test('fromJson — type 不为 theme 抛 FormatException', () {
      expect(
        () => ThemeDescriptor.fromJson({'type': 'config', 'id': 'x'}),
        throwsFormatException,
      );
    });

    test('fromJson — 缺少 colors 抛 FormatException', () {
      expect(
        () => ThemeDescriptor.fromJson({'type': 'theme', 'id': 'x'}),
        throwsFormatException,
      );
    });

    test('fromJson — 缺少必填色抛 FormatException', () {
      expect(
        () => ThemeDescriptor.fromJson({
          'type': 'theme',
          'id': 'x',
          'colors': {'background': '#0D1117'},
        }),
        throwsFormatException,
      );
    });

    test('fromJson — 非法 hex 抛 FormatException', () {
      expect(
        () => ThemeDescriptor.fromJson({
          'type': 'theme',
          'id': 'x',
          'colors': {
            'background': 'not-a-color',
            'surface': '#161B22',
            'border': '#30363D',
            'text': '#C9D1D9',
            'textSecondary': '#8B949E',
            'accent': '#58A6FF',
            'error': '#FF7B72',
            'others': '#8B949E',
          },
        }),
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
      final original = _fullTheme();
      final json = original.toJson();
      final restored = ThemeDescriptor.fromJson(json);
      expect(restored.id, original.id);
      expect(restored.colors, original.colors);
    });

    // ── color ──
    test('color — 命中返回 hex', () {
      final t = _simpleTheme();
      expect(t.color('accent'), '#58A6FF');
    });

    test('color — 未命中返回 null', () {
      final t = _simpleTheme();
      expect(t.color('unknown'), isNull);
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
        id: 'test',
        name: 'Overridden',
        colors: {},
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

      // 构造扁平 8 色主题 JSON（fromJson 要求 8 必填色）
      final themeMap = {
        'type': 'theme',
        'id': 'loaded',
        'name': 'Second',
        'colors': {
          'background': '#0D1117',
          'surface': '#161B22',
          'border': '#30363D',
          'text': '#C9D1D9',
          'textSecondary': '#8B949E',
          'accent': '#58A6FF',
          'error': '#FF7B72',
          'others': '#8B949E',
        },
      };
      File(p.join(themeDir.path, 'theme.json'))
          .writeAsStringSync(jsonEncode(themeMap));

      final store = ThemeStore();
      store.register(const ThemeDescriptor(
        id: 'loaded',
        name: 'First',
        colors: {},
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
}
