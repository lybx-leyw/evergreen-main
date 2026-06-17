import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:media_kit/media_kit.dart';
import 'app.dart';
import 'core/config/app_config.dart';
import 'core/config/app_config_notifier.dart';
import 'core/config/providers.dart';
import 'core/services/ocr_mobile.dart';
import 'core/utils/greenix_path.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // MediaKit: may fail on Android if libmpv.so is not bundled.
  // Non-fatal — video playback will simply not work.
  try {
    MediaKit.ensureInitialized();
  } catch (_) {
    // ignore — media_kit is optional on Android
  }

  // Configure desktop window — desktop only, skipped on Android/iOS
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    await windowManager.setMinimumSize(const Size(900, 600));
    await windowManager.setSize(const Size(1200, 800));
    await windowManager.setTitle(
        'ZJU live better and better — Evergreen 多工具集成版');
    await windowManager.center();
    await windowManager.show();
  }

  // Register mobile OCR (ML Kit + pdfrx) on Android/iOS.
  // Wrapped in try-catch: ML Kit may fail to init if Google Play
  // Services is unavailable or model download is pending.
  if (Platform.isAndroid || Platform.isIOS) {
    try {
      initMobileOcr(Dio());
    } catch (_) {
      // OCR will fall back to DeepSeek-OCR (Level 1) if available
    }
  }

  // 初始化 Greenix 路径（Android 上指向 app documents，桌面端用当前目录）
  await initGreenixPaths();

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
