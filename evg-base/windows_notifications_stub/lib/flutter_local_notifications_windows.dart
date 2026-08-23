import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';

/// Minimal Windows settings type required by `flutter_local_notifications`.
class WindowsInitializationSettings {
  const WindowsInitializationSettings({
    required this.appName,
    required this.appUserModelId,
    required this.guid,
    this.iconPath,
  });

  final String appName;
  final String appUserModelId;
  final String guid;
  final String? iconPath;
}

/// Minimal Windows notification details type required by
/// `flutter_local_notifications`.
class WindowsNotificationDetails {
  const WindowsNotificationDetails();
}

/// No-op Windows implementation.
///
/// The upstream `flutter_local_notifications_windows` FFI plugin currently
/// crashes the Dart AOT snapshotter on Windows Release builds with:
/// `Unexpected object (Class with illegal cid, full-aot) ... NativeLaunchDetails`.
/// This stub keeps the Android notification path working while unblocking
/// Windows Release builds. Windows toast notifications are intentionally
/// disabled until the upstream FFI/AOT issue is resolved.
class FlutterLocalNotificationsWindows
    extends FlutterLocalNotificationsPlatform {
  FlutterLocalNotificationsWindows();

  static void registerWith() {
    FlutterLocalNotificationsPlatform.instance =
        FlutterLocalNotificationsWindows();
  }

  Future<bool> initialize({
    required WindowsInitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
  }) async {
    return true;
  }

  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
    String? payload,
    WindowsNotificationDetails? notificationDetails,
  }) async {
    // No-op: Windows notifications disabled to avoid the FFI AOT crash.
  }

  Future<void> zonedSchedule({
    required int id,
    String? title,
    String? body,
    required DateTime scheduledDate,
    String? payload,
    DateTimeComponents? matchDateTimeComponents,
    WindowsNotificationDetails? notificationDetails,
  }) async {
    // No-op.
  }

  Future<void> periodicallyShow({
    required int id,
    String? title,
    String? body,
    required RepeatInterval repeatInterval,
    String? payload,
    WindowsNotificationDetails? notificationDetails,
  }) async {
    // No-op.
  }

  void dispose() {}
}
