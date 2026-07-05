/// 默认视图——根据 [DataBindingDescriptor] 列表渲染 table/list/card。
///
/// 公开类：[DefaultView]
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import '../widgets/data_table.dart';
import '../widgets/data_list.dart';
import '../widgets/data_card_grid.dart';
import '../widgets/empty_state.dart';

/// 默认通用视图。
///
/// 遍历 [ModuleDescriptor.dataBindings]，按每个 binding 的
/// `display` 字段渲染对应数据视图（table/list/card）。
/// 无 dataBindings 时渲染空状态占位。
///
/// 行数据通过 [tableData] 参数由上层（DataOrchestrator）注入。
/// key = dataType, value = 行数据列表。
/// 未提供时各视图渲染空数据。
class DefaultView extends StatelessWidget {
  final ModuleDescriptor descriptor;

  /// dataType → 行数据列表的映射。
  final Map<String, List<Map<String, dynamic>>> tableData;

  const DefaultView({
    super.key,
    required this.descriptor,
    this.tableData = const {},
  });

  @override
  Widget build(BuildContext context) {
    final bindings = descriptor.dataBindings;

    if (bindings.isEmpty) {
      return const EmptyState(
        icon: Icons.widgets_outlined,
        title: '暂无内容',
        subtitle: '此模块未配置数据绑定',
      );
    }

    if (bindings.length == 1) {
      return _buildBindingView(context, bindings.first);
    }

    // 多个 binding → 垂直排列
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: bindings
            .map((b) => Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _buildBindingView(context, b),
                ))
            .toList(),
      ),
    );
  }

  Widget _buildBindingView(BuildContext context, DataBindingDescriptor binding) {
    final data = tableData[binding.dataType] ?? <Map<String, dynamic>>[];

    return switch (binding.display) {
      'table' => EvergreenDataTable(
          binding: binding,
          actions: descriptor.actions,
          rows: data,
          columns: _inferColumns(data),
        ),
      'card' => DataCardGrid(
          binding: binding,
          actions: descriptor.actions,
          items: data,
        ),
      _ => DataList( // 'list' + 'raw' + 未知
          binding: binding,
          actions: descriptor.actions,
          items: data,
        ),
    };
  }

  /// 从数据行推断列名。
  List<String> _inferColumns(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return ['标题', '内容'];
    final keys = <String>{};
    for (final row in rows.take(5)) {
      keys.addAll(row.keys);
    }
    return keys.toList();
  }
}
