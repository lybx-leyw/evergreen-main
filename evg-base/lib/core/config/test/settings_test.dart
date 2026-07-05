/// Config 模块——设置与导入/导出测试。
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

// ═══════════════════════════════════════════════════════════════════════════
// 测试辅助
// ═══════════════════════════════════════════════════════════════════════════

Directory _tmpConfigDir(Map<String, dynamic> json) {
  final dir = Directory.systemTemp.createTempSync('config_test_');
  final file = File('${dir.path}${Platform.pathSeparator}config.json');
  file.writeAsStringSync(jsonEncode(json));
  return dir;
}

Directory _tmpConfigSubDir(Map<String, dynamic> json) {
  final dir = Directory.systemTemp.createTempSync('config_test_');
  final sub = Directory('${dir.path}${Platform.pathSeparator}config');
  sub.createSync();
  final file = File('${sub.path}${Platform.pathSeparator}config.json');
  file.writeAsStringSync(jsonEncode(json));
  return dir;
}

// ═══════════════════════════════════════════════════════════════════════════
// tests
// ═══════════════════════════════════════════════════════════════════════════

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    prefs = await SharedPreferences.getInstance();
  });

  // ───────────────────────────────────────────────────────────────────────
  // SettingDecl 构造
  // ───────────────────────────────────────────────────────────────────────

  group('SettingDecl 构造', () {
    test('string 命名构造函数', () {
      final d = SettingDecl.string(key: 'k', label: 'L', defaultValue: 'dv');
      expect(d.key, 'k');
      expect(d.label, 'L');
      expect(d.type, SettingType.string);
      expect(d.defaultValue, 'dv');
      expect(d.isSecure, false);
      expect(d.options, isNull);
    });

    test('bool_ 命名构造函数默认值为 "false"', () {
      final d = SettingDecl.bool_(key: 'b', label: 'B');
      expect(d.type, SettingType.bool_);
      expect(d.defaultValue, 'false');
    });

    test('path 命名构造函数', () {
      final d = SettingDecl.path(key: 'p', label: 'P');
      expect(d.type, SettingType.path);
      expect(d.isSecure, false);
    });

    test('option 命名构造函数存储选项列表', () {
      final opts = [const SettingOption(value: 'a', label: 'A')];
      final d = SettingDecl.option(key: 'o', label: 'O', options: opts, defaultValue: 'a');
      expect(d.type, SettingType.option);
      expect(d.options, hasLength(1));
      expect(d.options!.first.value, 'a');
    });

    test('isSecure 默认 false', () {
      final d = SettingDecl.string(key: 'k', label: 'L');
      expect(d.isSecure, false);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // initSettings
  // ───────────────────────────────────────────────────────────────────────

  group('initSettings', () {
    test('默认值写入 SharedPreferences', () async {
      final dir = _tmpConfigDir({
        'id': 't1',
        'name': 'Test',
        'settings': [
          {'key': 'T1_KEY', 'label': 'K1', 'type': 'string', 'default': 'hello'},
        ],
      });
      try {
        await initSettings(prefs, pluginDirs: [dir.path]);
        expect(prefs.getString('T1_KEY'), 'hello');
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('已存在的 key 不被覆盖', () async {
      await prefs.setString('T2_KEY', 'user_value');
      final dir = _tmpConfigDir({
        'id': 't2',
        'name': 'Test',
        'settings': [
          {'key': 'T2_KEY', 'label': 'K2', 'type': 'string', 'default': 'default_value'},
        ],
      });
      try {
        await initSettings(prefs, pluginDirs: [dir.path]);
        expect(prefs.getString('T2_KEY'), 'user_value');
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('空插件目录不崩溃', () async {
      final dir = Directory.systemTemp.createTempSync('config_test_empty_');
      try {
        await initSettings(prefs, pluginDirs: [dir.path]);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('config/config.json 子目录路径加载', () async {
      final dir = _tmpConfigSubDir({
        'id': 't3',
        'name': 'SubDir',
        'settings': [
          {'key': 'T3_KEY', 'label': 'K3', 'type': 'string', 'default': 'subdir'},
        ],
      });
      try {
        await initSettings(prefs, pluginDirs: [dir.path]);
        expect(prefs.getString('T3_KEY'), 'subdir');
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('解析 string/bool/path/option 四种类型', () async {
      final dir = _tmpConfigDir({
        'id': 't4',
        'name': 'Types',
        'settings': [
          {'key': 'T4_STR', 'label': 'S', 'type': 'string', 'default': 's'},
          {'key': 'T4_BOOL', 'label': 'B', 'type': 'bool', 'default': 'true'},
          {'key': 'T4_PATH', 'label': 'P', 'type': 'path', 'default': '/tmp'},
          {'key': 'T4_OPT', 'label': 'O', 'type': 'option', 'default': 'x', 'options': [{'value': 'x', 'label': 'X'}]},
        ],
      });
      try {
        await initSettings(prefs, pluginDirs: [dir.path]);
        expect(prefs.getString('T4_STR'), 's');
        expect(prefs.getString('T4_BOOL'), 'true');
        expect(prefs.getString('T4_PATH'), '/tmp');
        expect(prefs.getString('T4_OPT'), 'x');
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('缺失 type 字段默认 string', () async {
      final dir = _tmpConfigDir({
        'id': 't5',
        'name': 'NoType',
        'settings': [
          {'key': 'T5_KEY', 'label': 'K5', 'default': 'implicit_string'},
        ],
      });
      try {
        await initSettings(prefs, pluginDirs: [dir.path]);
        expect(prefs.getString('T5_KEY'), 'implicit_string');
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('自动解析 permissions 字段并注册', () async {
      final dir = _tmpConfigDir({
        'id': 'plugin_with_perms',
        'name': '带权限的插件',
        'settings': [
          {'key': 'PP_KEY', 'label': 'K', 'default': 'v'},
        ],
        'permissions': [
          {'key': 'NET', 'label': '网络', 'description': '访问互联网'},
          {'key': 'FS', 'label': '文件', 'description': '读取文件'},
        ],
      });
      try {
        await initSettings(prefs, pluginDirs: [dir.path]);
        // 权限应已自动注册
        final perms = getPermissions(prefs, 'plugin_with_perms');
        expect(perms, hasLength(2));
        expect(perms['NET'], true);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // getSetting
  // ───────────────────────────────────────────────────────────────────────

  group('getSetting', () {
    test('返回用户写入的值', () async {
      await prefs.setString('GS1', 'custom');
      final dir = _tmpConfigDir({
        'id': 'gs',
        'name': 'GS',
        'settings': [{'key': 'GS1', 'label': 'G', 'default': 'def'}],
      });
      try {
        await initSettings(prefs, pluginDirs: [dir.path]);
        expect(getSetting(prefs, 'GS1'), 'custom');
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('未写入时回退声明默认值', () async {
      final dir = _tmpConfigDir({
        'id': 'gs2',
        'name': 'GS2',
        'settings': [{'key': 'GS2', 'label': 'G2', 'default': 'fallback'}],
      });
      try {
        await initSettings(prefs, pluginDirs: [dir.path]);
        expect(getSetting(prefs, 'GS2'), 'fallback');
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('未知 key 返回空字符串', () {
      expect(getSetting(prefs, 'NONEXISTENT_KEY_999'), '');
    });

    test('空 SharedPreferences 不崩溃', () {
      expect(getSetting(prefs, 'ANY_KEY'), '');
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // setSetting
  // ───────────────────────────────────────────────────────────────────────

  group('setSetting', () {
    test('写入值', () async {
      await setSetting(prefs, 'SS1', 'hello');
      expect(prefs.getString('SS1'), 'hello');
    });

    test('空字符串删除 key', () async {
      await prefs.setString('SS2', 'temp');
      await setSetting(prefs, 'SS2', '');
      expect(prefs.getString('SS2'), isNull);
    });

    test('覆盖已有值', () async {
      await setSetting(prefs, 'SS3', 'first');
      await setSetting(prefs, 'SS3', 'second');
      expect(prefs.getString('SS3'), 'second');
    });

    test('bool_ 类型拒绝非法值', () async {
      final dir = _tmpConfigDir({
        'id': 'tv',
        'name': 'TV',
        'settings': [{'key': 'TV_BOOL', 'label': 'B', 'type': 'bool'}],
      });
      try {
        await initSettings(prefs, pluginDirs: [dir.path]);
        expect(
          () => setSetting(prefs, 'TV_BOOL', 'not_a_bool'),
          throwsA(isA<ConfigValidationException>()),
        );
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('option 类型拒绝不在列表中的值', () async {
      final dir = _tmpConfigDir({
        'id': 'tv2',
        'name': 'TV2',
        'settings': [
          {'key': 'TV_OPT', 'label': 'O', 'type': 'option', 'options': [{'value': 'a', 'label': 'A'}, {'value': 'b', 'label': 'B'}]},
        ],
      });
      try {
        await initSettings(prefs, pluginDirs: [dir.path]);
        expect(
          () => setSetting(prefs, 'TV_OPT', 'invalid_choice'),
          throwsA(isA<ConfigValidationException>()),
        );
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('option 类型合法值写入成功', () async {
      final dir = _tmpConfigDir({
        'id': 'tv3',
        'name': 'TV3',
        'settings': [
          {'key': 'TV_OPT2', 'label': 'O2', 'type': 'option', 'options': [{'value': 'a', 'label': 'A'}]},
        ],
      });
      try {
        await initSettings(prefs, pluginDirs: [dir.path]);
        await setSetting(prefs, 'TV_OPT2', 'a');
        expect(prefs.getString('TV_OPT2'), 'a');
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // getAllSettings
  // ───────────────────────────────────────────────────────────────────────

  group('getAllSettings', () {
    test('返回声明数量正确', () async {
      final dir = _tmpConfigDir({
        'id': 'ga',
        'name': 'GA',
        'settings': [
          {'key': 'GA1', 'label': 'A1', 'default': 'a'},
          {'key': 'GA2', 'label': 'A2', 'default': 'b'},
        ],
      });
      try {
        await initSettings(prefs, pluginDirs: [dir.path]);
        final all = getAllSettings(prefs);
        expect(all.where((s) => s.decl.key.startsWith('GA')), hasLength(2));
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('未写入的值显示默认值', () async {
      final dir = _tmpConfigDir({
        'id': 'ga2',
        'name': 'GA2',
        'settings': [{'key': 'GA_DEF', 'label': 'D', 'default': 'my_default'}],
      });
      try {
        await initSettings(prefs, pluginDirs: [dir.path]);
        final all = getAllSettings(prefs);
        final item = all.firstWhere((s) => s.decl.key == 'GA_DEF');
        expect(item.value, 'my_default');
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // exportConfig / importConfig
  // ───────────────────────────────────────────────────────────────────────

  group('exportConfig / importConfig', () {
    test('导出包含 aiMemory', () async {
      final dir = _tmpConfigDir({
        'id': 'exp0',
        'name': 'Export0',
        'settings': [{'key': 'EXP0_KEY', 'label': 'E0', 'default': 'v'}],
      });
      try {
        await initSettings(prefs, pluginDirs: [dir.path]);
        final exported = await exportConfig(prefs, aiMemory: {'favorites': ['m1', 'm2']});
        expect(exported['aiMemory'], {'favorites': ['m1', 'm2']});
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('导出包含 settings', () async {
      final dir = _tmpConfigDir({
        'id': 'exp',
        'name': 'Export',
        'settings': [{'key': 'EXP_KEY', 'label': 'E', 'default': 'exp_val'}],
      });
      try {
        await initSettings(prefs, pluginDirs: [dir.path]);
        final exported = await exportConfig(prefs);
        expect(exported['format'], 'evgconfig');
        expect(exported['version'], 1);
        expect(exported['settings']['EXP_KEY'], 'exp_val');
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('导入恢复设置值并返回 aiMemory', () async {
      final dir = _tmpConfigDir({
        'id': 'imp',
        'name': 'Import',
        'settings': [{'key': 'IMP_KEY', 'label': 'I', 'default': 'old'}],
      });
      try {
        await initSettings(prefs, pluginDirs: [dir.path]);
        final aiMem = await importConfig(prefs, {
          'settings': {'IMP_KEY': 'new_value'},
          'aiMemory': {'memories': [{'name': 'test'}]},
        });
        expect(prefs.getString('IMP_KEY'), 'new_value');
        expect(aiMem, isNotNull);
        expect(aiMem!['memories'], isNotEmpty);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('导入忽略未声明的 key', () async {
      await importConfig(prefs, {
        'settings': {'UNKNOWN_KEY_XYZ': 'should_be_ignored'},
      });
      expect(prefs.getString('UNKNOWN_KEY_XYZ'), isNull);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // 异常 toString
  // ───────────────────────────────────────────────────────────────────────

  group('异常 toString', () {
    test('ConfigMissingException', () {
      final e = ConfigMissingException('K', recoveryHint: '检查 config.json');
      expect(e.toString(), contains('K'));
      expect(e.toString(), contains('检查 config.json'));
    });

    test('ConfigValidationException', () {
      final e = ConfigValidationException(key: 'K', value: 'bad', reason: '必须是数字');
      expect(e.toString(), contains('bad'));
      expect(e.toString(), contains('必须是数字'));
    });
  });
}
