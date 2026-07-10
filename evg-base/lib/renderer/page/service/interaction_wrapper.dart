/// 交互包装器——根据 [ActionDescriptor] + [InputOptions] 包裹子组件交互层。
///
/// 公开类：[InteractionWrapper]
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import '../components/shared/widgets/crud_toolbar.dart';
import '../components/shared/widgets/export_menu.dart';
import '../components/shared/widgets/refresh_widget.dart';

/// 交互包装器。
///
/// 按序包裹：下拉刷新 → CRUD 工具栏 → 导出菜单。
/// 将手势配置（onTap/onLongPress/onSwipe）向下透传至数据视图。
class InteractionWrapper extends StatelessWidget {
  final ActionDescriptor? actions;
  final InputOptions? input;
  final Widget child;
  final VoidCallback? onCreate;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final Future<void> Function()? onRefresh;
  final void Function(ExportFormat)? onExport;

  const InteractionWrapper({
    super.key,
    this.actions,
    this.input,
    required this.child,
    this.onCreate,
    this.onEdit,
    this.onDelete,
    this.onRefresh,
    this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    Widget result = child;

    // 下拉刷新 / 自动刷新
    if (actions?.refresh != null) {
      result = RefreshWidget(
        refreshConfig: actions!.refresh,
        onRefresh: onRefresh,
        child: result,
      );
    }

    // 操作栏（新建/编辑/删除 + 导出）
    final hasActions = actions != null &&
        (actions!.creatable || actions!.editable ||
            (actions!.deletable?.enabled ?? false) ||
            actions!.exportable.isNotEmpty);

    if (hasActions) {
      result = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                CrudToolbar(
                  actions: actions!,
                  onCreate: onCreate,
                  onEdit: onEdit,
                  onDelete: onDelete,
                ),
                ExportMenu(
                  actions: actions!,
                  onExport: onExport,
                ),
              ],
            ),
          ),
          result,
        ],
      );
    }

    return result;
  }
}
