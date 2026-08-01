/// initSettings + registerConfigFromManifest 安卓空插件目录测试。
///
/// Android 最大痛点是插件资产释放失败 → plugins/ 为空 → initSettings 扫不到 config.json
/// → 所有设置项（含 ZJU_USERNAME/DEEPSEEK_API_KEY 等凭证）未注册 → 设置面板空白。
///
/// 覆盖场景：
///   1. initSettings 空/不存在目录 → 零声明
///   2. initSettings config.json 无 settings 字段 → 零声明
///   3. initSettings config.json 格式损坏 → 优雅跳过
///   4. initSettings 正常 config.json → 正确解析所有类型
///   5. registerConfigFromManifest 文件缺失 → 空摘要
///   6. registerConfigFromManifest JSON 损坏 → 空摘要
///   7. registerConfigFromManifest items 缺少 key → 跳过
///   8. registerConfigFromManifest secure string → 正确注册
library;

import 'dart:convert';
import 'dart:io';

import 'package:evergreen_base/core/config/config_http_server.dart';
import 'package:evergreen_base/core/config/register_config.dart';
import 'package:evergreen_base/core/config/settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 在临时目录中创建 config/config.json 并返回插件根目录路径。
Directory _makePluginDir(Map<String, dynamic> configContent) {
  final dir = Directory.systemTemp.createTempSync('evg_init_settings_test_');
  final configDir = Directory('${dir.path}${Platform.pathSeparator}config');
  configDir.createSync();
  final file = File(
      '${configDir.path}${Platform.pathSeparator}config.json');
  file.writeAsStringSync(jsonEncode(configContent));
  addTearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });
  return dir;
}

/// 不创建 config 子目录，只在根目录放 config.json（兼容旧格式）。
Directory _makeRootConfigPluginDir(Map<String, dynamic> configContent) {
  final dir = Directory.systemTemp.createTempSync('evg_init_settings_test_');
  final file = File('${dir.path}${Platform.pathSeparator}config.json');
  file.writeAsStringSync(jsonEncode(configContent));
  addTearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });
  return dir;
}

/// 有效的 config.json（含 string / bool / path / option + secure 字段）。
const _validSettingsJson = {
  'type': 'config',
  'id': 'test-plugin',
  'settings': [
    {'key': 'MY_STRING', 'label': '字符串', 'type': 'string', 'default': 'hello'},
    {'key': 'MY_BOOL', 'label': '开关', 'type': 'bool', 'default': 'true'},
    {'key': 'MY_PATH', 'label': '路径', 'type': 'path', 'default': '/tmp'},
    {
      'key': 'MY_OPTION',
      'label': '选项',
      'type': 'option',
      'default': 'a',
      'options': [
        {'value': 'a', 'label': 'A'},
        {'value': 'b', 'label': 'B'},
      ],
    },
    {
      'key': 'MY_SECRET',
      'label': '密钥',
      'type': 'string',
      'isSecure': true,
    },
  ],
};

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    // 重置 settings 模块的 _decls
    await initSettings(prefs, pluginDirs: []);
  });

  // ═════════════════════════════════════════════════════════════════════
  // initSettings — 插件目录扫描
  // ═════════════════════════════════════════════════════════════════════

  group('initSettings — 空/缺失目录（Android 插件资产释放失败）', () {
    test('不存在目录 → 零声明', () async {
      await initSettings(prefs,
          pluginDirs: ['/this/path/does/not/exist_on_any_os']);

      final all = getAllSettings(prefs);
      expect(all, isEmpty, reason: '不存在目录应返回零声明');
    });

    test('空 pluginDirs → 零声明', () async {
      await initSettings(prefs);

      final all = getAllSettings(prefs);
      expect(all, isEmpty);
    });

    test('目录存在但无任何 config.json → 零声明', () async {
      final emptyDir = Directory.systemTemp.createTempSync('evg_empty_');
      addTearDown(() {
        try {
          emptyDir.deleteSync(recursive: true);
        } catch (_) {}
      });

      await initSettings(prefs, pluginDirs: [emptyDir.path]);

      final all = getAllSettings(prefs);
      expect(all, isEmpty,
          reason: '空目录应返回零声明，模拟 Android plugins/ 为空');
    });

    test('config.json 无 settings 字段 → 零声明', () async {
      final dir = _makePluginDir({'type': 'config', 'id': 'test'});

      await initSettings(prefs, pluginDirs: [dir.path]);

      final all = getAllSettings(prefs);
      expect(all, isEmpty,
          reason: '无 settings 字段应等价零声明');
    });

    test('config.json 格式损坏 → 跳过该插件，其他正常', () async {
      final badDir = _makePluginDir(<String, dynamic>{});
      // 覆盖写入损坏 JSON
      final badFile = File(
          '${badDir.path}${Platform.pathSeparator}config${Platform.pathSeparator}config.json');
      badFile.writeAsStringSync('NOT VALID {{{');

      final goodDir = _makePluginDir(_validSettingsJson);

      await initSettings(prefs, pluginDirs: [badDir.path, goodDir.path]);

      final all = getAllSettings(prefs);
      expect(all.length, 5,
          reason: '损坏的插件跳过 + 正常的 5 项仍注册');
      final keys = all.map((s) => s.decl.key).toSet();
      expect(keys, contains('MY_STRING'));
      expect(keys, contains('MY_SECRET'));
    });
  });

  group('initSettings — 正常 config.json 解析', () {
    test('子目录格式 config/config.json → 5 项设置 + 默认值', () async {
      final dir = _makePluginDir(_validSettingsJson);

      await initSettings(prefs, pluginDirs: [dir.path]);

      final all = getAllSettings(prefs);
      expect(all.length, 5);

      // 类型检查
      final byKey = {for (final s in all) s.decl.key: s};
      expect(byKey['MY_STRING']!.decl.type, SettingType.string);
      expect(byKey['MY_BOOL']!.decl.type, SettingType.bool_);
      expect(byKey['MY_PATH']!.decl.type, SettingType.path);
      expect(byKey['MY_OPTION']!.decl.type, SettingType.option);
      expect(byKey['MY_OPTION']!.decl.options!.length, 2);
      expect(byKey['MY_SECRET']!.decl.isSecure, isTrue);

      // 默认值
      expect(byKey['MY_STRING']!.value, 'hello');
      expect(byKey['MY_BOOL']!.value, 'true');
    });

    test('根目录格式 config.json（兼容旧格式）→ 一样解析', () async {
      final dir = _makeRootConfigPluginDir({
        'settings': [
          {'key': 'OLD_KEY', 'label': '旧格式', 'type': 'string', 'default': 'old'},
        ],
      });

      await initSettings(prefs, pluginDirs: [dir.path]);

      final all = getAllSettings(prefs);
      expect(all.length, 1);
      expect(all.first.decl.key, 'OLD_KEY');
      expect(all.first.value, 'old');
    });
  });

  group('initSettings — 默认值不覆盖已有 SP 值', () {
    test('SP 已有非空值 → 不被 defaultValue 覆盖', () async {
      final dir = _makePluginDir(_validSettingsJson);

      // 预先设一个值
      await prefs.setString('MY_STRING', 'pre_existing');

      await initSettings(prefs, pluginDirs: [dir.path]);

      final all = getAllSettings(prefs);
      final item = all.firstWhere((s) => s.decl.key == 'MY_STRING');
      expect(item.value, 'pre_existing',
          reason: 'SP 已有值 → 不被 config.json default 覆盖');
    });
  });

  // ═════════════════════════════════════════════════════════════════════
  // registerConfigFromManifest — 运行期热注册
  // ═════════════════════════════════════════════════════════════════════

  group('registerConfigFromManifest — 边界条件', () {
    late ConfigHttpServer configServer;

    setUp(() {
      configServer = ConfigHttpServer(prefs);
    });

    test('文件缺失 → 空摘要', () {
      final summary = registerConfigFromManifest(
        configServer: configServer,
        pluginDir: '/nonexistent/plugin',
      );

      expect(summary.count, 0);
      expect(summary.registered, isEmpty);
      expect(summary.savedDefaults, isEmpty);
    });

    test('config.json 格式损坏 → 空摘要（不崩）', () {
      final dir = _makePluginDir(<String, dynamic>{});
      final file = File(
          '${dir.path}${Platform.pathSeparator}config${Platform.pathSeparator}config.json');
      file.writeAsStringSync('CORRUPTED {{ JSON');

      final summary = registerConfigFromManifest(
        configServer: configServer,
        pluginDir: dir.path,
      );

      expect(summary.count, 0, reason: '损坏 JSON → 空摘要');
    });

    test('无 settings 字段 → 空摘要', () {
      final dir = _makePluginDir({'type': 'config', 'id': 'test'});

      final summary = registerConfigFromManifest(
        configServer: configServer,
        pluginDir: dir.path,
      );

      expect(summary.count, 0);
    });

    test('items 缺少 key → 跳过该项', () {
      final dir = _makePluginDir({
        'settings': [
          {'key': 'VALID_KEY', 'label': '有效'},
          {'label': '无key的项'}, // no 'key' field
          {'key': '', 'label': '空key'}, // empty key
          {'key': 'ANOTHER_VALID', 'label': '另一个有效'},
        ],
      });

      final summary = registerConfigFromManifest(
        configServer: configServer,
        pluginDir: dir.path,
      );

      expect(summary.registered.length, 2);
      expect(summary.registered, contains('VALID_KEY'));
      expect(summary.registered, contains('ANOTHER_VALID'));
    });

    test('secure string → 注册成功', () {
      final dir = _makePluginDir({
        'settings': [
          {
            'key': 'SCRAPER_USERNAME',
            'label': '爬虫用户名',
            'type': 'string',
            'isSecure': true,
            'default': '',
          },
        ],
      });

      final summary = registerConfigFromManifest(
        configServer: configServer,
        pluginDir: dir.path,
      );

      expect(summary.registered, contains('SCRAPER_USERNAME'));
    });

    test('有 default 值 → savedDefaults 列出', () {
      final dir = _makePluginDir({
        'settings': [
          {'key': 'WITH_DEFAULT', 'label': '有默认值', 'default': 'xyz'},
          {'key': 'NO_DEFAULT', 'label': '无默认值'},
          {'key': 'EMPTY_DEFAULT', 'label': '空默认值', 'default': ''},
        ],
      });

      final summary = registerConfigFromManifest(
        configServer: configServer,
        pluginDir: dir.path,
      );

      expect(summary.registered.length, 3);
      expect(summary.savedDefaults, contains('WITH_DEFAULT'));
      expect(summary.savedDefaults, isNot(contains('NO_DEFAULT')));
      expect(summary.savedDefaults, isNot(contains('EMPTY_DEFAULT')),
          reason: '空字符串 default 不应列入 savedDefaults');
    });
  });
}
