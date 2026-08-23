/// 数据变更通知服务 —— 订阅 [DataOrchestrator] 的 [DataChangeEvent]，
/// 通过系统通知（Android 状态栏 / Windows Toast）提示用户数据变化。
///
/// 分层：核心层（core/data）只发纯 Dart 事件，本服务在 renderer 层
/// 持有 flutter_local_notifications 插件实现；初始化/发送全部异步且
/// 容错——任何失败仅记日志，绝不影响数据刷新主流程。
///
/// ⚠️ Windows Toast 前置条件：应用需以「开始菜单快捷方式 + AppUserModelID」
/// 安装（Inno Setup 安装包会创建快捷方式）；裸 flutter run 的临时进程
/// 可能无法弹 Toast，此时降级为仅日志，不影响其他功能。
library;

import 'dart:async' show unawaited;
import 'dart:io' show Platform;

import 'package:evergreen_base/core/data/data.dart'
    show DataChangeEvent, DataOrchestrator;
import 'package:evergreen_base/core/log.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 单例服务（无状态，可直接跨 provider 使用）。
class DataChangeNotificationService {
  DataChangeNotificationService._();

  /// 全局实例。
  static final DataChangeNotificationService instance =
      DataChangeNotificationService._();

  static const String _channelId = 'data_changes';
  static const String _channelName = '数据变更';
  static const String _channelDesc = '后台数据刷新发现变化时通知';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _initFailed = false;

  /// 订阅 orchestrator 的变更事件并转发到系统通知。
  void listenTo(DataOrchestrator orchestrator) {
    orchestrator.addDataChangeListener(notify);
  }

  /// 初始化通知渠道 + Android 13+ 权限请求（幂等，异步，不阻塞启动）。
  Future<void> ensureInitialized() async {
    if (_initialized || _initFailed || kIsWeb) return;
    try {
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        windows: WindowsInitializationSettings(
          appName: 'Evergreen',
          appUserModelId: 'com.example.evergreen_base.DataChanges',
          // 固定 GUID：Windows 通知身份标识
          guid: '{3E5F7A21-8B4D-4C6E-9A1F-2D8C7B6A5E4F}',
        ),
      );
      await _plugin.initialize(settings: settings);

      // Android 8.0+ 通知渠道
      const channel = AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDesc,
        importance: Importance.high,
      );
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel);

      // Android 13+ 运行时通知权限（POST_NOTIFICATIONS）
      if (Platform.isAndroid) {
        await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission();
      }
      _initialized = true;
      Log().info('[notify] 数据变更通知服务就绪');
    } catch (e) {
      _initFailed = true;
      Log().warn('[notify] 通知服务初始化失败（降级为静默）', data: {'error': e.toString()});
    }
  }

  /// 发送一条数据变更通知（fire-and-forget）。
  void notify(DataChangeEvent event) {
    if (_initFailed || kIsWeb) return;
    unawaited(_show(event));
  }

  Future<void> _show(DataChangeEvent event) async {
    try {
      await ensureInitialized();
      if (!_initialized) return;

      final title = '数据更新 · ${event.displayName}';
      final body = event.diff.summarize(maxExamples: 3);
      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high,
        ),
        windows: const WindowsNotificationDetails(),
      );
      await _plugin.show(
        id: event.sourceName.hashCode, // 稳定 id：同一数据源的变更覆盖旧通知
        title: title,
        body: body,
        notificationDetails: details,
      );
      Log().info('[notify] 已发送: $title | $body');
    } catch (e) {
      Log().warn(
        '[notify] 发送失败（已降级为日志）',
        data: {'source': event.sourceName, 'error': e.toString()},
      );
    }
  }
}
