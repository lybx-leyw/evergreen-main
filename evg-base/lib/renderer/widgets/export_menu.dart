/// 导出菜单——根据 [ActionDescriptor.exportable] 生成 CSV/PDF/JSON 导出选项。
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';

/// 导出格式。
enum ExportFormat { csv, pdf, json }

/// 导出按钮 + 弹出菜单。
///
/// 读取 [ActionDescriptor.exportable] 过滤可用的导出格式。
class ExportMenu extends StatelessWidget {
  final ActionDescriptor actions;
  final void Function(ExportFormat format)? onExport;

  const ExportMenu({
    super.key,
    required this.actions,
    this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    if (actions.exportable.isEmpty) return const SizedBox.shrink();

    return PopupMenuButton<ExportFormat>(
      icon: const Icon(Icons.ios_share),
      tooltip: '导出',
      onSelected: onExport,
      itemBuilder: (context) {
        return actions.exportable.map((fmt) {
          return switch (fmt.toLowerCase()) {
            'csv' => const PopupMenuItem(
                value: ExportFormat.csv,
                child: ListTile(
                  leading: Icon(Icons.table_chart),
                  title: Text('导出 CSV'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            'pdf' => const PopupMenuItem(
                value: ExportFormat.pdf,
                child: ListTile(
                  leading: Icon(Icons.picture_as_pdf),
                  title: Text('导出 PDF'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            'json' => const PopupMenuItem(
                value: ExportFormat.json,
                child: ListTile(
                  leading: Icon(Icons.code),
                  title: Text('导出 JSON'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            _ => const PopupMenuItem(
                value: ExportFormat.csv,
                child: ListTile(
                  leading: Icon(Icons.insert_drive_file),
                  title: Text('导出文件'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
          };
        }).toList();
      },
    );
  }
}
