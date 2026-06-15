import 'package:flutter/material.dart';

/// 统一的 Toast / SnackBar 帮助类。
///
/// 替代分散在各处的裸 [SnackBar]，提供一致的样式和时长。
///
/// ```dart
/// Toast.success(context, '设置已保存');
/// Toast.error(context, '加载失败', detail: '网络连接超时');
/// Toast.info(context, '正在检查更新...');
/// ```
class Toast {
  /// 成功消息 — 绿色背景 + 勾选图标，2 秒自动消失。
  static void success(BuildContext context, String message) {
    _show(
      context,
      message: message,
      icon: Icons.check_circle,
      backgroundColor: const Color(0xFF2DA44E),
      duration: const Duration(seconds: 2),
    );
  }

  /// 错误消息 — 红色背景 + 错误图标，4 秒自动消失。
  static void error(BuildContext context, String message, {String? detail}) {
    _show(
      context,
      message: detail != null ? '$message\n$detail' : message,
      icon: Icons.error_outline,
      backgroundColor: const Color(0xFFCF222E),
      duration: const Duration(seconds: 4),
    );
  }

  /// 信息消息 — 中性深色背景，3 秒自动消失。
  static void info(BuildContext context, String message) {
    _show(
      context,
      message: message,
      icon: Icons.info_outline,
      backgroundColor: const Color(0xFF323232),
      duration: const Duration(seconds: 3),
    );
  }

  static void _show(
    BuildContext context, {
    required String message,
    required IconData icon,
    required Color backgroundColor,
    required Duration duration,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontSize: 14, color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: duration,
      ),
    );
  }
}
