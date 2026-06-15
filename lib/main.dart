import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:media_kit/media_kit.dart';
import 'app.dart';
import 'core/config/app_config.dart';
import 'core/config/app_config_notifier.dart';
import 'core/config/providers.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  // Configure desktop window
  await windowManager.ensureInitialized();
  await windowManager.setMinimumSize(const Size(900, 600));
  await windowManager.setSize(const Size(1200, 800));
  await windowManager.setTitle(
      'ZJU live better and better — Evergreen 多工具集成版');
  await windowManager.center();
  await windowManager.show();

  // 初始化 SharedPreferences（Provider 注入需要）
  final prefs = await SharedPreferences.getInstance();

  // 新配置系统：AppConfigNotifier → 写入 AppConfigData + 同步旧 AppConfig
  final configNotifier = AppConfigNotifier(prefs);
  await configNotifier.initialize();

  // 旧配置系统：保持兼容（未迁移的消费者仍可读取 AppConfig）
  await AppConfig.initialize();

  runApp(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWith((ref) => configNotifier),
        sharedPreferencesProvider.overrideWith((ref) => prefs),
      ],
      child: const EvergreenApp(),
    ),
  );
}
