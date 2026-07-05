import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:media_kit/media_kit.dart';
import 'app.dart';
import 'core/config/app_config.dart';
import 'core/config/app_config_notifier.dart';
import 'core/config/providers.dart';
import 'core/feedback/feedback_bar.dart';
import 'core/feedback/screenshot.dart';
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

  // 修复旧版本可能残留的非 String 类型值（避免 String→bool 崩溃）
  // 可安全删除：2026-07 之后所有用户都已迁移。
  _healLegacyPrefs(prefs);

  // 新配置系统：AppConfigNotifier → 写入 AppConfigData + 同步旧 AppConfig
  final configNotifier = AppConfigNotifier(prefs);
  await configNotifier.initialize();

  // 旧配置系统：保持兼容（未迁移的消费者仍可读取 AppConfig）
  await AppConfig.initialize();

  final app = ProviderScope(
    overrides: [
      appConfigProvider.overrideWith((ref) => configNotifier),
      sharedPreferencesProvider.overrideWith((ref) => prefs),
    ],
    child: const EvergreenApp(),
  );

  runApp(
    kDebugMode
        ? _FeedbackPlugin(child: app)
        : app,
  );
}

/// 修复旧版本 SharedPreferences 中可能以非 String 类型存储的键。
///
/// 老版本可能以 bool/int 存储 AUTO_REFRESH_ENABLED 等键，
/// 导致新版本 getString() 返回 null、或触发 'String' is not a
/// subtype of 'bool' 运行时崩溃。
///
/// 遍历所有已知键，非 String 则重新写入。未设置的键跳过。
/// TODO: 2026-07 后可安全删除。
void _healLegacyPrefs(SharedPreferences prefs) {
  const healKeys = [
    'AUTO_REFRESH_ENABLED', 'AUTO_REFRESH_INTERVAL',
    'DEEPSEEK_THINKING', 'DEEPSEEK_MODEL', 'DEEPSEEK_API_KEY',
    'DEEPSEEK_OCR_API_KEY', 'PTA_SESSION',
    'ZJU_USERNAME', 'ZJU_PASSWORD',
    'TRANSLATE_LANG_OUT', 'TRANSLATE_LANG_IN',
    'MATERIAL_DOWNLOAD_PATH', 'VIDEO_OPENER',
    'STUDENT_GRADE', 'STUDENT_MAJOR', 'STUDENT_MINOR',
    'PERSONAL_TRAINING_PLAN_OCR', 'OTHER_TRAINING_PLAN_OCR',
    'MEMORY_RIGOR', 'DINGTALK_WEBHOOK',
  ];
  for (final key in healKeys) {
    try {
      final raw = prefs.get(key);
      if (raw == null) continue;
      if (raw is! String) {
        prefs.setString(key, raw.toString());
      }
    } catch (_) {
      prefs.remove(key);
    }
  }
}

/// 仅 debug 模式启用——全屏 RepaintBoundary 截图 + 反馈底栏。
class _FeedbackPlugin extends StatelessWidget {
  final Widget child;
  const _FeedbackPlugin({required this.child});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: screenshotKey,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          children: [
            child,
            const FeedbackFab(),
          ],
        ),
      ),
    );
  }
}
