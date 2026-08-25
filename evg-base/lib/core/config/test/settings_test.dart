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

    test('string 构造函数可携带 suggestions', () {
      final d = SettingDecl.string(
        key: 'm', label: 'M',
        suggestions: const [SettingOption(value: 'a', label: 'A')],
      );
      expect(d.type, SettingType.string);
      expect(d.suggestions, hasLength(1));
      expect(d.suggestions!.first.value, 'a');
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

    test('string 类型 suggestions 解析（对象 / 纯字符串两种写法）', () async {
      final dir = _tmpConfigDir({
        'id': 't6',
        'name': 'Sug',
        'settings': [
          {
            'key': 'T6_MODEL', 'label': 'M', 'type': 'string', 'default': 'a',
            'suggestions': [
              {'value': 'a', 'label': 'A 模型'},
              'deepseek-chat',
            ],
          },
        ],
      });
      try {
        await initSettings(prefs, pluginDirs: [dir.path]);
        final all = getAllSettings(prefs);
        final item = all.firstWhere((s) => s.decl.key == 'T6_MODEL');
        expect(item.decl.type, SettingType.string);
        expect(item.decl.suggestions, hasLength(2));
        expect(item.decl.suggestions![0].value, 'a');
        expect(item.decl.suggestions![0].label, 'A 模型');
        expect(item.decl.suggestions![1].value, 'deepseek-chat');
        expect(item.decl.suggestions![1].label, 'deepseek-chat');
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

    test('string 类型接受任意模型 id——suggestions 不参与写入校验', () async {
      final dir = _tmpConfigDir({
        'id': 'tv4',
        'name': 'TV4',
        'settings': [
          {
            'key': 'TV_MODEL', 'label': 'M', 'type': 'string', 'default': 'deepseek-v4-flash',
            'suggestions': [
              {'value': 'deepseek-v4-flash', 'label': 'V4 Flash'},
              {'value': 'deepseek-chat', 'label': 'Chat'},
            ],
          },
        ],
      });
      try {
        await initSettings(prefs, pluginDirs: [dir.path]);
        // 自由填写任意 OpenAI 兼容模型 id（不在 suggestions 中）——必须写入成功
        await setSetting(prefs, 'TV_MODEL', 'gpt-4o');
        expect(prefs.getString('TV_MODEL'), 'gpt-4o');
        await setSetting(prefs, 'TV_MODEL', 'custom-model@org/deploy');
        expect(prefs.getString('TV_MODEL'), 'custom-model@org/deploy');
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
  // exportConfig / importConfig（.evgconfig v2）
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

    test('导出包含 settings，version 为当前版本', () async {
      final dir = _tmpConfigDir({
        'id': 'exp',
        'name': 'Export',
        'settings': [{'key': 'EXP_KEY', 'label': 'E', 'default': 'exp_val'}],
      });
      try {
        await initSettings(prefs, pluginDirs: [dir.path]);
        final exported = await exportConfig(prefs);
        expect(exported['format'], 'evgconfig');
        expect(exported['version'], kEvgConfigVersion);
        expect(exported['settings']['EXP_KEY'], 'exp_val');
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('导出包含 dynamicSettings（动态注册项枚举）', () async {
      // 模拟运行期动态注册写入（未声明 key）
      await prefs.setString('DYN_A', 'dyn_val');
      final exported = await exportConfig(prefs, dynamicKeys: ['DYN_A', 'DYN_MISSING']);
      expect(exported['dynamicSettings'], {'DYN_A': 'dyn_val'});
    });

    test('导出包含 permissions（bool 正确类型）', () async {
      registerPermissions('exp_perm', [
        const PermissionDecl(key: 'NET', label: '网络', description: '...'),
        const PermissionDecl(key: 'FS', label: '文件', description: '...'),
      ]);
      await setPermission(prefs, 'exp_perm', 'NET', false);
      final exported = await exportConfig(prefs, includePermissions: true);
      final perms = exported['permissions'] as Map<String, dynamic>;
      expect(perms['exp_perm'], {'NET': false, 'FS': true});
    });

    test('导出默认跳过 isSecure 明文，includeSecure 时包含', () async {
      final dir = _tmpConfigDir({
        'id': 'exp_sec',
        'name': 'ExportSec',
        'settings': [
          {'key': 'SEC_KEY', 'label': 'K', 'isSecure': true, 'default': 'secret'},
          {'key': 'PLAIN_KEY', 'label': 'P', 'default': 'plain'},
        ],
      });
      try {
        await initSettings(prefs, pluginDirs: [dir.path]);
        final exported = await exportConfig(prefs);
        expect(exported['settings'], isNot(contains('SEC_KEY')));
        expect(exported['settings']['PLAIN_KEY'], 'plain');
        final withSecure = await exportConfig(prefs, includeSecure: true);
        expect(withSecure['settings']['SEC_KEY'], 'secret');
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('导出包含 appPrefs（白名单）', () async {
      await prefs.setString('active_theme_id', 'ocean');
      final exported = await exportConfig(prefs, appPrefs: {'active_theme_id': ''});
      expect(exported['appPrefs'], {'active_theme_id': 'ocean'});
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

    test('导入 version 超出支持范围被拒绝', () async {
      expect(
        () => importConfig(prefs, {'format': 'evgconfig', 'version': 99, 'settings': {}}),
        throwsA(isA<ConfigValidationException>()),
      );
    });

    test('导入 format 非法被拒绝', () async {
      expect(
        () => importConfig(prefs, {'format': 'other', 'version': 1, 'settings': {}}),
        throwsA(isA<ConfigValidationException>()),
      );
    });

    test('v1 文件向后兼容导入（version 1 正常读 settings）', () async {
      final dir = _tmpConfigDir({
        'id': 'imp_v1',
        'name': 'ImportV1',
        'settings': [{'key': 'V1_KEY', 'label': 'V1', 'default': 'old'}],
      });
      try {
        await initSettings(prefs, pluginDirs: [dir.path]);
        await importConfig(prefs, {
          'format': 'evgconfig',
          'version': 1,
          'settings': {'V1_KEY': 'v1_value'},
        });
        expect(prefs.getString('V1_KEY'), 'v1_value');
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('导入 dynamicSettings 仅接受白名单 key', () async {
      await importConfig(prefs, {
        'dynamicSettings': {'DYN_OK': 'a', 'DYN_BAD': 'b'},
      }, allowedDynamicKeys: ['DYN_OK']);
      expect(prefs.getString('DYN_OK'), 'a');
      expect(prefs.getString('DYN_BAD'), isNull);
    });

    test('导入 appPrefs 仅接受白名单 key', () async {
      await importConfig(prefs, {
        'appPrefs': {'active_theme_id': 'ocean', 'sidebar_collapsed': 'true'},
      }, allowedAppPrefs: {'active_theme_id': '应用主题'});
      expect(prefs.getString('active_theme_id'), 'ocean');
      expect(prefs.getString('sidebar_collapsed'), isNull);
    });

    test('导入 permissions 仅接受已注册插件已声明键（bool 正确类型）', () async {
      registerPermissions('imp_perm', [
        const PermissionDecl(key: 'NET', label: '网络', description: '...'),
      ]);
      await importConfig(prefs, {
        'permissions': {
          'imp_perm': {'NET': false, 'HACK': true},
          'unknown_plugin': {'X': false},
        },
      });
      expect(getPermissions(prefs, 'imp_perm')['NET'], false);
      expect(prefs.containsKey('perm.imp_perm.HACK'), false);
      expect(prefs.containsKey('perm.unknown_plugin.X'), false);
    });

    test('导入 permissions overwrite:false 保留已有显式设置，默认覆盖', () async {
      registerPermissions('imp_perm2', [
        const PermissionDecl(key: 'NET', label: '网络', description: '...'),
      ]);
      await setPermission(prefs, 'imp_perm2', 'NET', false);
      await importConfig(prefs, {
        'permissions': {'imp_perm2': {'NET': true}},
      }, overwrite: false);
      expect(getPermissions(prefs, 'imp_perm2')['NET'], false); // 非覆盖保护
      await importConfig(prefs, {
        'permissions': {'imp_perm2': {'NET': true}},
      });
      expect(getPermissions(prefs, 'imp_perm2')['NET'], true); // 默认覆盖
    });

    test('导入 extra 白名单过滤 + perm.* 键跳过', () async {
      final dir = _tmpConfigDir({
        'id': 'imp_extra',
        'name': 'ImportExtra',
        'settings': [{'key': 'EXT_DECL', 'label': 'D', 'default': 'd'}],
      });
      try {
        await initSettings(prefs, pluginDirs: [dir.path]);
        await importConfig(prefs, {
          'extra': {
            'EXT_DECL': 'declared_value',
            'HACK_KEY': 'hack',
            'perm.whatever.X': 'true',
          },
        });
        expect(prefs.getString('EXT_DECL'), 'declared_value');
        expect(prefs.getString('HACK_KEY'), isNull);
        expect(prefs.containsKey('perm.whatever.X'), false);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('导入默认覆盖（v1 语义），overwrite:false 启用非空值保护', () async {
      final dir = _tmpConfigDir({
        'id': 'imp_prot',
        'name': 'ImportProt',
        'settings': [{'key': 'PROT_KEY', 'label': 'P', 'default': 'old'}],
      });
      try {
        await initSettings(prefs, pluginDirs: [dir.path]);
        await prefs.setString('PROT_KEY', 'existing');
        await importConfig(prefs, {'settings': {'PROT_KEY': 'incoming'}});
        expect(prefs.getString('PROT_KEY'), 'incoming'); // 默认覆盖（v1 语义）
        await importConfig(prefs, {'settings': {'PROT_KEY': 'incoming2'}}, overwrite: false);
        expect(prefs.getString('PROT_KEY'), 'incoming'); // 非空保护
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('onChanged 仅在发生实际写入时触发', () async {
      final dir = _tmpConfigDir({
        'id': 'imp_cb',
        'name': 'ImportCb',
        'settings': [{'key': 'CB_KEY', 'label': 'C', 'default': 'c'}],
      });
      try {
        await initSettings(prefs, pluginDirs: [dir.path]);
        var calls = 0;
        await importConfig(prefs, {'settings': {'CB_KEY': 'v1'}}, onChanged: () => calls++);
        expect(calls, 1);
        await importConfig(prefs, {'settings': {'UNKNOWN': 'x'}}, onChanged: () => calls++);
        expect(calls, 1); // 未写入不触发
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('导入 bool_/option 非法值跳过', () async {
      final dir = _tmpConfigDir({
        'id': 'imp_typed',
        'name': 'ImportTyped',
        'settings': [
          {'key': 'TYPED_FLAG', 'label': 'F', 'type': 'bool', 'default': ''},
          {
            'key': 'TYPED_MODE', 'label': 'M', 'type': 'option',
            'options': [
              {'value': 'a', 'label': 'A'},
              {'value': 'b', 'label': 'B'},
            ],
            'default': '',
          },
        ],
      });
      try {
        await initSettings(prefs, pluginDirs: [dir.path]);
        await importConfig(prefs, {
          'settings': {'TYPED_FLAG': 'maybe', 'TYPED_MODE': 'zzz'},
        });
        expect(prefs.getString('TYPED_FLAG'), isNull); // 非法 bool 跳过
        expect(prefs.getString('TYPED_MODE'), isNull); // 非法 option 跳过
        await importConfig(prefs, {
          'settings': {'TYPED_FLAG': 'true', 'TYPED_MODE': 'b'},
        });
        expect(prefs.getString('TYPED_FLAG'), 'true');
        expect(prefs.getString('TYPED_MODE'), 'b');
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('导入 isSecure 默认跳过，allowSecure 时导入', () async {
      final dir = _tmpConfigDir({
        'id': 'imp_sec',
        'name': 'ImportSec',
        'settings': [
          {'key': 'SEC_IMP', 'label': 'K', 'isSecure': true, 'default': ''},
        ],
      });
      try {
        await initSettings(prefs, pluginDirs: [dir.path]);
        await importConfig(prefs, {'settings': {'SEC_IMP': 'new_secret'}});
        expect(prefs.getString('SEC_IMP'), isNull); // 默认跳过
        await importConfig(prefs, {'settings': {'SEC_IMP': 'new_secret'}}, allowSecure: true);
        expect(prefs.getString('SEC_IMP'), 'new_secret');
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('getSettingSources 返回来源插件 id', () async {
      final dir = _tmpConfigDir({
        'id': 'src_plugin',
        'name': 'SrcPlugin',
        'settings': [{'key': 'SRC_KEY', 'label': 'S', 'default': 'v'}],
      });
      try {
        await initSettings(prefs, pluginDirs: [dir.path]);
        final sources = getSettingSources();
        expect(sources['SRC_KEY'], 'src_plugin');
      } finally {
        dir.deleteSync(recursive: true);
      }
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
