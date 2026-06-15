import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/core/config/app_config_model.dart';

void main() {
  group('AppConfigData.mask', () {
    test('null → "(null)"', () {
      expect(AppConfigData.mask(null), '(null)');
    });
    test('空字符串 → "(null)"', () {
      expect(AppConfigData.mask(''), '(null)');
    });
    test('短字符串 ≤6 → "***"', () {
      expect(AppConfigData.mask('123456'), '***');
      expect(AppConfigData.mask('ab'), '***');
    });
    test('长字符串 → 前3+***', () {
      expect(AppConfigData.mask('1234567890'), '123***');
    });
  });

  group('AppConfigData.toString', () {
    test('不含明文密码', () {
      final config = AppConfigData(
        zjuUsername: 'testuser',
        zjuPassword: 'mysecretpassword',
        deepseekApiKey: 'sk-1234567890abcdef',
      );
      final str = config.toString();
      expect(str, contains('testuser'));
      expect(str, isNot(contains('mysecretpassword')));
      expect(str, isNot(contains('1234567890abcdef')));
      expect(str, contains('***'));
    });
  });

  group('AppConfigData.hasZjuCredentials', () {
    test('都有 → true', () {
      expect(AppConfigData(zjuUsername: 'u', zjuPassword: 'p').hasZjuCredentials, isTrue);
    });
    test('缺用户名 → false', () {
      expect(AppConfigData(zjuPassword: 'p').hasZjuCredentials, isFalse);
    });
    test('空字符串 → false', () {
      expect(AppConfigData(zjuUsername: '', zjuPassword: 'p').hasZjuCredentials, isFalse);
    });
  });

  group('AppConfigData.hasDeepSeekApiKey', () {
    test('有 → true', () {
      expect(AppConfigData(deepseekApiKey: 'sk-xxx').hasDeepSeekApiKey, isTrue);
    });
    test('无 → false', () {
      expect(const AppConfigData().hasDeepSeekApiKey, isFalse);
    });
  });

  group('AppConfigData.deepseekThinking', () {
    test('默认 true', () {
      expect(const AppConfigData().deepseekThinking, isTrue);
    });
    test('显式设为 false', () {
      expect(const AppConfigData(deepseekThinking: false).deepseekThinking, isFalse);
    });
  });

  group('AppConfigData.copyWith', () {
    test('部分覆盖', () {
      final original = AppConfigData(zjuUsername: 'old', deepseekModel: 'old-model');
      final updated = original.copyWith(zjuUsername: 'new');
      expect(updated.zjuUsername, 'new');
      expect(updated.deepseekModel, 'old-model');
    });
  });
}
