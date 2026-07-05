import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:evergreen_multi_tools/core/storage/settings_service.dart';

void main() {
  group('SettingsService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('loadAll 返回全部 key（含默认值）', () async {
      final svc = SettingsService();
      final result = await svc.loadAll();
      expect(result.containsKey('ZJU_USERNAME'), true);
      expect(result.containsKey('DEEPSEEK_API_KEY'), true);
      expect(result.containsKey('AUTO_REFRESH_ENABLED'), true);
      expect(result.containsKey('SHOW_WIP_FEATURES'), false);
    });

    test('save + loadAll 往返', () async {
      final svc = SettingsService();
      await svc.save('ZJU_USERNAME', 'testuser');
      final result = await svc.loadAll();
      expect(result['ZJU_USERNAME'], 'testuser');
    });

    test('save null/empty → remove', () async {
      final svc = SettingsService();
      await svc.save('ZJU_USERNAME', 'testuser');
      await svc.save('ZJU_USERNAME', '');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('ZJU_USERNAME'), isNull);
    });

    test('unknown key ignored by saveAll', () async {
      final svc = SettingsService();
      await svc.saveAll({'UNKNOWN_KEY': 'value'});
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('UNKNOWN_KEY'), isNull);
    });

    test('clearAll 清空所有', () async {
      final svc = SettingsService();
      await svc.save('ZJU_USERNAME', 'test');
      await svc.clearAll();
      final result = await svc.loadAll();
      expect(result['ZJU_USERNAME'], isNull);
    });
  });
}
