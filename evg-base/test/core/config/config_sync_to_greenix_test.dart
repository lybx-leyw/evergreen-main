/// syncConfigToGreenix 保护机制测试 —— Android 空 SharedPreferences 不覆写真实凭证。
///
/// 覆盖场景（Android 上凭证丢失的最常见根因）：
///   1. 空 SP + 已有非空配置 → 全部保留
///   2. SP 有声明但值空 + 已有非空配置 → 保留文件值
///   3. SP 有非空新值 → SP 优先（用户新填入）
///   4. greenixConfigPath 未设置 → 跳过不崩
///   5. 文件不存在 → 创建
///   6. JSON 解析失败 → 从空字典恢复
library;

import 'dart:convert';
import 'dart:io';

import 'package:evergreen_base/core/config/config_http_server.dart';
import 'package:evergreen_base/core/config/settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 在临时目录准备一个已有 config.json，返回其文件路径。
File _prepareConfigFile(Map<String, dynamic> content) {
  final dir = Directory.systemTemp.createTempSync('greenix_sync_test_');
  final file = File('${dir.path}${Platform.pathSeparator}config.json');
  // 确保父目录存在（模拟实际 path 带 .greenix/ 前缀）
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(jsonEncode(content));
  addTearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });
  return file;
}

/// 读取 config.json 并返回解析后的 Map。
Map<String, dynamic> _readConfig(File file) {
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    // 使用 flutter_test 内置 SharedPreferences mock
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    // 重置 settings 模块的 _decls，避免跨测试文件污染
    await initSettings(prefs, pluginDirs: []);
  });

  group('syncConfigToGreenix — 空 SP 不覆写已有凭证（Android 最大痛点）', () {
    test('SP 完全空 + 文件有凭证 → 凭证保留', () {
      // 模拟：Android 启动时 initSettings 没扫到任何 config.json（插件资产释放失败）
      // → _decls 为空 → getAllSettings 返回 [] → 不会生成任何 prefs 配置
      final file = _prepareConfigFile({
        'ZJU_USERNAME': 'real_user',
        'ZJU_PASSWORD': 'secret123',
        'OTHER_KEY': 'other_val',
      });

      final server = ConfigHttpServer(prefs);
      server.setGreenixConfigPath(file.path);

      final result = _readConfig(file);
      expect(result['ZJU_USERNAME'], 'real_user');
      expect(result['ZJU_PASSWORD'], 'secret123');
      expect(result['OTHER_KEY'], 'other_val');
      expect(result.length, 3); // 没有新增多余 key
    });

    test('SP 有声明但值空 + 文件有凭证 → 保留文件值（防止空 SP 覆写）', () async {
      // 模拟：插件 config.json 声明了 ZJU_USERNAME/ZJU_PASSWORD，
      // 但 Android 首次启动 SharedPreferences 全都是空值
      final file = _prepareConfigFile({
        'ZJU_USERNAME': 'real_user',
        'ZJU_PASSWORD': 'real_pass',
      });

      final server = ConfigHttpServer(prefs);

      // 模拟声明存在但值为空：注册为动态设置项
      server.registerSetting('ZJU_USERNAME', '用户名');
      server.registerSetting('ZJU_PASSWORD', '密码');
      // prefs 中这两个 key 未被 setString → getSetting 返回空字符串
      server.setGreenixConfigPath(file.path);

      final result = _readConfig(file);
      expect(result['ZJU_USERNAME'], 'real_user',
          reason: 'SP 空值不得覆写文件中的真实用户名');
      expect(result['ZJU_PASSWORD'], 'real_pass',
          reason: 'SP 空值不得覆写文件中的真实密码');
    });

    test('SP 有非空新值 → 文件写入 SP 值（用户输入优先）', () async {
      // 用户在设置面板填入了新的凭证 → 应写入文件
      final file = _prepareConfigFile({
        'ZJU_USERNAME': 'old_user',
        'SCRAPER_USERNAME': 'old_scraper',
      });

      final server = ConfigHttpServer(prefs);
      server.registerSetting('ZJU_USERNAME', '用户名');
      server.registerSetting('SCRAPER_USERNAME', '爬虫用户名');

      // 用户在 SharedPreferences 里填了新值
      await prefs.setString('ZJU_USERNAME', 'new_user');
      // SCRAPER_USERNAME 未设置 → getSetting 返回空

      server.setGreenixConfigPath(file.path);

      final result = _readConfig(file);
      expect(result['ZJU_USERNAME'], 'new_user',
          reason: '用户新填入值应优先于文件旧值');
      expect(result['SCRAPER_USERNAME'], 'old_scraper',
          reason: 'SP 无新值 → 保留文件的非空旧值');
    });

    test('greenixConfigPath 未设置 → 不崩、不写任何文件', () {
      final tmpFile = File(
          '${Directory.systemTemp.path}/greenix_should_not_exist.json');
      // 确认文件不存在
      if (tmpFile.existsSync()) tmpFile.deleteSync();

      final server = ConfigHttpServer(prefs);
      // 不调用 setGreenixConfigPath，直接调用 syncConfigToGreenix
      server.syncConfigToGreenix();

      expect(tmpFile.existsSync(), isFalse,
          reason: 'null path 时不应创建任何文件');
    });

    test('config.json 不存在 → 自动创建', () {
      final dir = Directory.systemTemp.createTempSync('greenix_new_test_');
      addTearDown(() {
        try {
          dir.deleteSync(recursive: true);
        } catch (_) {}
      });
      final path = '${dir.path}${Platform.pathSeparator}config.json';
      final file = File(path);
      expect(file.existsSync(), isFalse);

      final server = ConfigHttpServer(prefs);
      server.setGreenixConfigPath(path);

      expect(file.existsSync(), isTrue, reason: '文件不存在时应自动创建');
      final result = _readConfig(file);
      expect(result, isEmpty, reason: 'SP 空 → 创建空配置');
    });

    test('JSON 解析失败 → 从空字典恢复（不丢数据）', () {
      // 写入非法 JSON
      final file = _prepareConfigFile(<String, dynamic>{});
      file.writeAsStringSync('NOT VALID JSON {{{');

      final server = ConfigHttpServer(prefs);
      server.registerSetting('MY_KEY', '测试');
      // prefs 中有值
      prefs.setString('MY_KEY', 'my_value');

      server.setGreenixConfigPath(file.path);

      // 应从空恢复 + 合并 prefs 值
      final result = _readConfig(file);
      expect(result['MY_KEY'], 'my_value',
          reason: 'JSON 解析失败后仍应写入 prefs 中的值');
    });

    test('SP 为空 + 文件为空 → 写入空对象', () {
      final file = _prepareConfigFile(<String, dynamic>{});

      final server = ConfigHttpServer(prefs);
      server.setGreenixConfigPath(file.path);

      final result = _readConfig(file);
      expect(result, isEmpty);
    });
  });

  group('syncConfigToGreenix — 凭证混合场景', () {
    test('部分 key 在 SP、部分只在文件 → 合并保留', () {
      // 场景：SCRAPER_USERNAME 有声明且设了值，
      // ZJU_PASSWORD 只在文件里（动态注册才产生，initSettings 未扫到）
      final file = _prepareConfigFile({
        'ZJU_USERNAME': 'file_user',
        'ZJU_PASSWORD': 'file_pass',
        'CUSTOM_KEY': 'file_custom',
      });

      final server = ConfigHttpServer(prefs);
      // 只动态注册部分 key （模拟运行期热注册）
      server.registerSetting('ZJU_USERNAME', '用户名');
      // ZJU_PASSWORD 和 CUSTOM_KEY 都未注册

      server.setGreenixConfigPath(file.path);

      final result = _readConfig(file);
      expect(result['ZJU_USERNAME'], 'file_user',
          reason: 'SP 值为空 → 保留文件值');
      expect(result['ZJU_PASSWORD'], 'file_pass',
          reason: '完全不在 SP → 保留文件值');
      expect(result['CUSTOM_KEY'], 'file_custom',
          reason: '完全不在 SP → 保留文件值');
      expect(result.length, 3);
    });

    test('连续两次 sync → 不丢数据', () {
      final file = _prepareConfigFile({'ZJU_USERNAME': 'user1'});

      final server = ConfigHttpServer(prefs);
      server.registerSetting('ZJU_USERNAME', '用户名');
      server.setGreenixConfigPath(file.path);
      expect(_readConfig(file)['ZJU_USERNAME'], 'user1');

      // 第二次 sync，SP 仍为空 → 值应保留
      server.syncConfigToGreenix();
      expect(_readConfig(file)['ZJU_USERNAME'], 'user1',
          reason: '二次 sync 不应丢失文件中的值');
    });
  });
}
