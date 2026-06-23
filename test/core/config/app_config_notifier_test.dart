import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:evergreen_multi_tools/core/config/app_config_notifier.dart';

void main() {
  group('AppConfigNotifier', () {
    /// Temp file used as the .env target so tests don't pollute each other.
    late String envPath;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      // Use a unique temp file for each test's .env
      final tmp = await Directory.systemTemp.createTemp('palace_test_env_');
      envPath = p.join(tmp.path, '.env');
      addTearDown(() async {
        try {
          await tmp.delete(recursive: true);
        } catch (_) {}
      });
    });

    test('默认 deepseekThinking = true', () async {
      final prefs = await SharedPreferences.getInstance();
      final notifier = AppConfigNotifier(prefs);
      notifier.envFilePathOverride = envPath;
      await notifier.initialize();
      expect(notifier.state.deepseekThinking, true);
      expect(notifier.state.deepseekModel, 'deepseek-v4-flash');
    });

    test('saveAll 持久化往返', () async {
      final prefs = await SharedPreferences.getInstance();
      final notifier = AppConfigNotifier(prefs);
      notifier.envFilePathOverride = envPath;
      await notifier.initialize();

      await notifier.saveAll({
        'ZJU_USERNAME': 'testuser',
        'DEEPSEEK_MODEL': 'custom-model',
        'DEEPSEEK_THINKING': 'disabled',
      });

      expect(notifier.state.zjuUsername, 'testuser');
      expect(notifier.state.deepseekModel, 'custom-model');
      expect(notifier.state.deepseekThinking, false);
    });

    test('set 单项更新', () async {
      final prefs = await SharedPreferences.getInstance();
      final notifier = AppConfigNotifier(prefs);
      notifier.envFilePathOverride = envPath;
      await notifier.initialize();

      notifier.set('ZJU_USERNAME', 'newuser');
      expect(notifier.state.zjuUsername, 'newuser');
    });

    test('saveAll 后 hasZjuCredentials 正确', () async {
      final prefs = await SharedPreferences.getInstance();
      final notifier = AppConfigNotifier(prefs);
      notifier.envFilePathOverride = envPath;
      await notifier.initialize();

      await notifier.saveAll({
        'ZJU_USERNAME': 'testuser',
        'ZJU_PASSWORD': 'testpass',
      });
      expect(notifier.state.hasZjuCredentials, true);
    });

    test('@Secure 字段 toString 脱敏', () async {
      final prefs = await SharedPreferences.getInstance();
      final notifier = AppConfigNotifier(prefs);
      notifier.envFilePathOverride = envPath;
      await notifier.initialize();
      await notifier.saveAll({
        'DEEPSEEK_API_KEY': 'sk-secret-key-12345',
      });

      final str = notifier.state.toString();
      expect(str, isNot(contains('sk-secret-key-12345')));
      expect(str, contains('sk-***'));
    });
  });
}
