/// CRUD 工具栏——根据 [ActionDescriptor] 生成新建/编辑/删除按钮。
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'confirm_dialog.dart';

/// CRUD 操作工具栏。
///
/// 读取 [ActionDescriptor.creatable]、[editable]、[deletable]
/// 生成对应按钮。删除按钮根据 [DeletableDescriptor.confirm] 弹出确认弹窗。
class CrudToolbar extends StatelessWidget {
  final ActionDescriptor actions;
  final VoidCallback? onCreate;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const CrudToolbar({
    super.key,
    required this.actions,
    this.onCreate,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final buttons = <Widget>[];

    if (actions.creatable && onCreate != null) {
      buttons.add(
        IconButton(
          icon: const Icon(Icons.add),
          tooltip: '新建',
          onPressed: onCreate,
        ),
      );
    }

    if (actions.editable && onEdit != null) {
      buttons.add(
        IconButton(
          icon: const Icon(Icons.edit_outlined),
          tooltip: '编辑',
          onPressed: onEdit,
        ),
      );
    }

    if (actions.deletable != null &&
        actions.deletable!.enabled &&
        onDelete != null) {
      buttons.add(
        IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: '删除',
          onPressed: () {
            if (actions.deletable!.confirm) {
              ConfirmDialog.show(
                context,
                title: '确认删除',
                message: '确定要删除此项吗？此操作不可撤销。',
                onConfirm: onDelete,
              );
            } else {
              onDelete?.call();
            }
          },
        ),
      );
    }

    if (buttons.isEmpty) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: buttons,
    );
  }
}
