import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 全局 [SharedPreferences] Provider——由 `main()` 通过 override 注入。
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
      'Use ProviderScope overrides in main() to inject SharedPreferences');
});
