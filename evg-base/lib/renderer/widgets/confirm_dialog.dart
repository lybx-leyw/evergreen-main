/// 确认弹窗——用于删除等破坏性操作前的确认。
import 'package:flutter/material.dart';

/// 通用确认弹窗。
///
/// ```dart
/// ConfirmDialog.show(context,
///   title: '确认删除',
///   message: '确定要删除此项吗？');
/// ```
class ConfirmDialog extends StatelessWidget {
  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final VoidCallback? onConfirm;

  const ConfirmDialog._({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.cancelLabel,
    this.onConfirm,
  });

  /// 显示确认弹窗。返回 true 表示用户确认。
  static Future<bool?> show(
    BuildContext context, {
    String title = '确认操作',
    String message = '确定要继续吗？',
    String confirmLabel = '确认',
    String cancelLabel = '取消',
    VoidCallback? onConfirm,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => ConfirmDialog._(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        onConfirm: onConfirm,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          onPressed: () {
            onConfirm?.call();
            Navigator.of(context).pop(true);
          },
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}
