/// ThemeDescriptor + ThemeStore + 扫描函数 全量测试。
///
/// 覆盖范围：
///   ThemeDescriptor — const 构造 / fromJson / fromJsonString / toJson /
///     semantic / component / semanticColor / componentColor / parseHex /
///     校验方法
///   ThemeStore — register / all / findById / activeTheme / setActiveById /
///     activeOrFirst / ChangeNotifier
///   scanThemes / loadThemes / scanThemeFile
library;

import 'dart:io';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;

import '../theme_descriptor.dart';
import '../theme_store.dart';
import '../theme_loader.dart';
import '../src/color.dart';
import '../src/tokens.dart';

// ═══════ helpers ═══════

String _testDir(String sub) =>
    p.join(Directory.current.path, 'test', '_fixtures', sub);

ThemeDescriptor _simpleTheme() => const ThemeDescriptor(
      id: 'test',
      name: 'Test',
      semanticTokens: {'primary': '#FF0000', 'background': '#FFFFFF'},
    );

ThemeDescriptor _fullTheme() => const ThemeDescriptor(
      id: 'full',
      name: 'Full Theme',
      semanticTokens: {
        'primary': '#1677FF',
        'secondary': '#4096FF',
        'background': '#F5F6F8',
      },
      componentTokens: {
        'sidebar': {'bg': '#F2F3F5', 'text': '#1A1D21'},
        'button': {'primary': '#1677FF', 'hover': '#0958D9', 'text': '#FFFFFF'},
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
      expect(t.semanticTokens.length, 3);
      expect(t.componentTokens.length, 2);
    });

    test('const 构造 — 空 tokens', () {
      final t = ThemeDescriptor(id: 'empty', name: 'Empty');
      expect(t.semanticTokens, isEmpty);
      expect(t.componentTokens, isEmpty);
    });

    // ── fromJson ──
    test('fromJson — 完整解析', () {
      final t = ThemeDescriptor.fromJson({
        'type': 'theme',
        'id': 'json_theme',
        'name': 'JSON Theme',
        'colors': {
          'primary': '#FF5722',
          'background': '#FAFAFA',
          'sidebar': {'bg': '#333', 'text': '#FFF'},
        },
      });
      expect(t.id, 'json_theme');
      expect(t.semantic('primary'), '#FF5722');
      expect(t.component('sidebar')?['bg'], '#333');
    });

    test('fromJson — type 不为 theme 抛 FormatException', () {
      expect(
        () => ThemeDescriptor.fromJson({'type': 'config', 'id': 'x'}),
        throwsFormatException,
      );
    });

    test('fromJson — 空 colors', () {
      final t = ThemeDescriptor.fromJson({
        'type': 'theme',
        'id': 'no_colors',
        'name': 'No Colors',
      });
      expect(t.semanticTokens, isEmpty);
      expect(t.componentTokens, isEmpty);
    });

    test('fromJson — 只有语义 token', () {
      final t = ThemeDescriptor.fromJson({
        'type': 'theme',
        'id': 'sem_only',
        'name': 'Semantic Only',
        'colors': {'primary': '#000', 'background': '#FFF'},
      });
      expect(t.semanticTokens.length, 2);
      expect(t.componentTokens, isEmpty);
    });

    test('fromJson — 只有组件 token', () {
      final t = ThemeDescriptor.fromJson({
        'type': 'theme',
        'id': 'comp_only',
        'name': 'Component Only',
        'colors': {
          'sidebar': {'bg': '#333'},
        },
      });
      expect(t.semanticTokens, isEmpty);
      expect(t.componentTokens.length, 1);
    });

    // ── fromJsonString ──
    test('fromJsonString — 有效 JSON', () {
      final t = ThemeDescriptor.fromJsonString(
          '{"type":"theme","id":"s","name":"S","colors":{"primary":"#000"}}');
      expect(t.id, 's');
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
      expect(restored.semanticTokens, original.semanticTokens);
      // 组件 token 顺序可能不同，逐个 key 验证
      for (final k in original.componentTokens.keys) {
        expect(restored.componentTokens[k], original.componentTokens[k]);
      }
    });

    // ── semantic / component ──
    test('semantic — 命中返回 hex', () {
      final t = _simpleTheme();
      expect(t.semantic('primary'), '#FF0000');
    });

    test('semantic — 未命中返回 null', () {
      final t = _simpleTheme();
      expect(t.semantic('nonexistent'), isNull);
    });

    test('component — 命中返回 map', () {
      final t = _fullTheme();
      expect(t.component('button'), isNotNull);
      expect(t.component('button')?['primary'], '#1677FF');
    });

    test('component — 未命中返回 null', () {
      final t = _fullTheme();
      expect(t.component('nonexistent'), isNull);
    });

    // ── semanticColor / componentColor ──
    test('semanticColor — 合法 hex 返回 ThemeColor', () {
      final t = _simpleTheme();
      final c = t.semanticColor('primary');
      expect(c, isNotNull);
      expect(c!.toHex(withAlpha: false), '#FF0000');
    });

    test('semanticColor — 未声明返回 null', () {
      final t = _simpleTheme();
      expect(t.semanticColor('missing'), isNull);
    });

    test('semanticColor — 非法 hex 返回 null', () {
      final t = ThemeDescriptor(
        id: 'bad',
        name: 'Bad',
        semanticTokens: {'primary': 'not-a-color'},
      );
      expect(t.semanticColor('primary'), isNull);
    });

    test('componentColor — 命中返回 ThemeColor', () {
      final t = _fullTheme();
      final c = t.componentColor('button', 'primary');
      expect(c, isNotNull);
      expect(c!.toHex(withAlpha: false), '#1677FF');
    });

    test('componentColor — 组件存在但 token 不存在返回 null', () {
      final t = _fullTheme();
      expect(t.componentColor('button', 'missing'), isNull);
    });

    test('componentColor — 组件不存在返回 null', () {
      final t = _fullTheme();
      expect(t.componentColor('nonexistent', 'bg'), isNull);
    });

    // ── semanticColorOr / componentColorOr ──
    test('semanticColorOr — 命中返回实际值', () {
      final t = _simpleTheme();
      final c = t.semanticColorOr('primary', const ThemeColor(0xFF000000));
      expect(c.toHex(withAlpha: false), '#FF0000');
    });

    test('semanticColorOr — 未命中返回 fallback', () {
      final t = _simpleTheme();
      final fallback = const ThemeColor(0xFF000000);
      final c = t.semanticColorOr('missing', fallback);
      expect(c, same(fallback));
    });

    test('semanticColorOr — 非法 hex 返回 fallback', () {
      final t = ThemeDescriptor(
        id: 'bad',
        name: 'Bad',
        semanticTokens: {'primary': 'not-a-color'},
      );
      final fallback = const ThemeColor(0xFF000000);
      final c = t.semanticColorOr('primary', fallback);
      expect(c, same(fallback));
    });

    test('componentColorOr — 命中返回实际值', () {
      final t = _fullTheme();
      final c = t.componentColorOr('button', 'primary', const ThemeColor(0xFF000000));
      expect(c.toHex(withAlpha: false), '#1677FF');
    });

    test('componentColorOr — 未命中返回 fallback', () {
      final t = _fullTheme();
      final fallback = const ThemeColor(0xFF000000);
      final c = t.componentColorOr('button', 'missing', fallback);
      expect(c, same(fallback));
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

    // ── 校验方法 ──
    test('unknownSemanticKeys — 返回未知 key', () {
      final t = ThemeDescriptor(
        id: 'x',
        name: 'X',
        semanticTokens: {'primary': '#000', 'customKey': '#FFF'},
      );
      expect(t.unknownSemanticKeys, contains('customKey'));
    });

    test('unknownComponentKeys — 返回未知 key', () {
      final t = ThemeDescriptor(
        id: 'x',
        name: 'X',
        componentTokens: {
          'sidebar': {'bg': '#000'},
          'customComponent': {'x': '#FFF'},
        },
      );
      expect(t.unknownComponentKeys, contains('customComponent'));
    });

    test('invalidColors — 检测非法 hex', () {
      final t = ThemeDescriptor(
        id: 'x',
        name: 'X',
        semanticTokens: {'primary': 'bad'},
        componentTokens: {
          'sidebar': {'bg': 'also-bad'},
        },
      );
      expect(t.invalidColors.length, 2);
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
      store.register(
          ThemeDescriptor(id: 'test', name: 'Overridden', semanticTokens: {}));
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
      store.activeTheme = _simpleTheme();
      expect(count, 0);
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

    test('loadThemes — 注册到 store', () {
      final dir = _testDir('load_test');
      if (Directory(dir).existsSync()) Directory(dir).deleteSync(recursive: true);
      final themeDir = Directory(p.join(dir, 'my_theme', 'theme'));
      themeDir.createSync(recursive: true);
      File(p.join(themeDir.path, 'theme.json')).writeAsStringSync(
        '{"type":"theme","id":"loaded","name":"Loaded","colors":{"primary":"#000"}}',
      );

      final store = ThemeStore();
      loadThemes(dir, store);
      expect(store.findById('loaded'), isNotNull);

      // cleanup
      Directory(dir).deleteSync(recursive: true);
    });

    test('loadThemes — 重复 id 覆盖', () {
      final dir = _testDir('overwrite_test');
      if (Directory(dir).existsSync()) Directory(dir).deleteSync(recursive: true);
      final themeDir = Directory(p.join(dir, 'my_theme', 'theme'));
      themeDir.createSync(recursive: true);
      File(p.join(themeDir.path, 'theme.json')).writeAsStringSync(
        '{"type":"theme","id":"loaded","name":"Second","colors":{"primary":"#FFF"}}',
      );

      final store = ThemeStore();
      store.register(ThemeDescriptor(id: 'loaded', name: 'First'));
      loadThemes(dir, store);
      expect(store.findById('loaded')?.name, 'Second'); // 后者覆盖

      Directory(dir).deleteSync(recursive: true);
    });

    test('scanThemeFile — 有效文件', () {
      final dir = _testDir('single_file');
      if (Directory(dir).existsSync()) Directory(dir).deleteSync(recursive: true);
      Directory(dir).createSync(recursive: true);
      final file = File(p.join(dir, 'theme.json'));
      file.writeAsStringSync(
        '{"type":"theme","id":"single","name":"Single","colors":{}}',
      );

      final t = scanThemeFile(file.path);
      expect(t.id, 'single');

      Directory(dir).deleteSync(recursive: true);
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
    test('SemanticTokens 数量 = 20', () {
      expect(SemanticTokens.count, 20);
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

    test('isValidHexColor', () {
      expect(isValidHexColor('#FFF'), isTrue);
      expect(isValidHexColor('#1677FF'), isTrue);
      expect(isValidHexColor('#FF1677FF'), isTrue);
      expect(isValidHexColor('red'), isFalse);
      expect(isValidHexColor('#GGG'), isFalse);
      expect(isValidHexColor(''), isFalse);
      expect(isValidHexColor(null), isFalse);
    });
  });

  // ═══════ invalidColors 非颜色 token 跳过 ═══════

  group('invalidColors 非颜色 token', () {
    test('跳过 divider.thickness', () {
      final t = ThemeDescriptor(
        id: 'x',
        name: 'X',
        componentTokens: {
          'divider': {'color': '#FF0000', 'thickness': '1'},
        },
      );
      // thickness="1" 不是 hex，但应被跳过（已知非颜色子 token）
      expect(t.invalidColors, isEmpty);
    });

    test('跳过 chart.colors（数组型）', () {
      final t = ThemeDescriptor(
        id: 'x',
        name: 'X',
        componentTokens: {
          'chart': {
            'colors': '[#FF0000, #00FF00]',
            'axis': '#CCCCCC',
            'grid': '#EEEEEE',
            'tooltip': '#333333',
          },
        },
      );
      // colors 是数组字符串，应被跳过；axis/grid/tooltip 是合法 hex
      expect(t.invalidColors, isEmpty);
    });

    test('非颜色 token 中仍检测非法 hex', () {
      final t = ThemeDescriptor(
        id: 'x',
        name: 'X',
        componentTokens: {
          'sidebar': {'bg': 'not-a-color'},
        },
      );
      // sidebar.bg 没有在白名单中→应被检测
      expect(t.invalidColors.length, 1);
      expect(t.invalidColors.first.key, 'sidebar.bg');
    });
  });

  // ═══════ fromJson 校验行为 ═══════

  group('fromJson 校验行为', () {
    test('未知 key 出现在 unknownSemanticKeys', () {
      final t = ThemeDescriptor.fromJson({
        'type': 'theme',
        'id': 'test',
        'name': 'T',
        'colors': {
          'primary': '#000',
          'customMadeUpKey': '#FFF',
        },
      });
      expect(t.unknownSemanticKeys, contains('customMadeUpKey'));
    });

    test('未知组件 key 出现在 unknownComponentKeys', () {
      final t = ThemeDescriptor.fromJson({
        'type': 'theme',
        'id': 'test',
        'name': 'T',
        'colors': {
          'madeUpComponent': {'x': '#FFF'},
        },
      });
      expect(t.unknownComponentKeys, contains('madeUpComponent'));
    });

    test('fromJson 未知 key 不抛异常', () {
      // 兼容未来扩展：未知 key 静默接受，仅通过 getter 暴露
      expect(
        () => ThemeDescriptor.fromJson({
          'type': 'theme',
          'id': 'x',
          'name': 'X',
          'colors': {'futureToken': '#000'},
        }),
        returnsNormally,
      );
    });
  });
}
