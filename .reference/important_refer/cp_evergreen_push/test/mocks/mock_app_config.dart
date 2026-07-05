import 'package:evergreen_multi_tools/core/config/app_config.dart';

/// Test helper: inject AppConfig values for tests without reading env/files.
///
/// Usage in setUp():
/// ```dart
/// setUp(() {
///   setupTestAppConfig(
///     username: 'test_user',
///     password: 'test_pass',
///     apiKey: 'sk-test-key',
///   );
/// });
/// ```
void setupTestAppConfig({
  String username = 'test_user',
  String password = 'test_pass',
  String apiKey = 'sk-test-api-key',
  String ocrApiKey = 'sk-test-ocr-key',
  String model = 'deepseek-v4-flash',
  String thinking = 'enabled',
}) {
  AppConfig.set('ZJU_USERNAME', username);
  AppConfig.set('ZJU_PASSWORD', password);
  AppConfig.set('DEEPSEEK_API_KEY', apiKey);
  AppConfig.set('DEEPSEEK_OCR_API_KEY', ocrApiKey);
  AppConfig.set('DEEPSEEK_MODEL', model);
  AppConfig.set('DEEPSEEK_THINKING', thinking);
}

/// Reset AppConfig to empty state between tests.
void resetAppConfig() {
  AppConfig.set('ZJU_USERNAME', null);
  AppConfig.set('ZJU_PASSWORD', null);
  AppConfig.set('DEEPSEEK_API_KEY', null);
  AppConfig.set('DEEPSEEK_OCR_API_KEY', null);
  AppConfig.set('DEEPSEEK_MODEL', null);
  AppConfig.set('DEEPSEEK_THINKING', null);
}
