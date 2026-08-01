/// CardList 槽位——从 [ComponentDescriptor.config] 读取卡片数据渲染列表。
///
/// 同时保留 [DefaultView] 作为模块级兜底视图。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/slot/data_source_slot.dart';
import 'package:evergreen_base/renderer/components/shared/widgets/data_table.dart';
import 'package:evergreen_base/renderer/components/shared/widgets/data_list.dart';
import 'package:evergreen_base/renderer/components/shared/widgets/data_card_grid.dart';
import 'package:evergreen_base/renderer/components/shared/widgets/empty_state.dart';

// ═══════ CardListSlot — slot 级组件（从 config 读数据）═══════

/// CardList 组件——读取 config 中的 title 和 cards。
/// 支持 M2 dataSource 注入：拉取到的数据合并进 config['cards']。
class CardListSlot extends DataSourceSlot {
  const CardListSlot({super.key, required super.config});

  // Phase 2: 声明式数据绑定
  @override
  DataMapping get dataMapping => const DataMapping(targetKey: 'cards');

  @override
  DataSourceSlotState<CardListSlot> createState() => _CardListSlotState();
}

class _CardListSlotState extends DataSourceSlotState<CardListSlot> {

  @override
  Widget buildStatic(Map<String, dynamic> cfg) {
    final title = cfg['title'] as String? ?? '';
    final cards = (cfg['cards'] as List<dynamic>?) ?? [];

    // 去掉 Expanded：外层 _buildSlotCard 已用 Expanded+SCSV 处理滚动，
    // 这里用 shrinkWrap: true 让 GridView 取内容自然高度，避免嵌套 flex 底溢出。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (title.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ),
        if (cards.isEmpty)
          _emptyState(context)
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.5,
            ),
            itemCount: cards.length,
            itemBuilder: (context, index) {
              final card = cards[index] as Map<String, dynamic>;
              return _CardItem(
                title: card['title'] as String? ?? '',
                body: card['body'] as String? ??
                    card['description'] as String? ??
                    '',
              );
            },
          ),
      ],
    );
  }

  Widget _emptyState(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.dashboard_customize,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(height: 8),
          Text('暂无卡片数据',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _CardItem extends StatelessWidget {
  final String title;
  final String body;

  const _CardItem({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Expanded(
              child: Text(
                body,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════ DefaultView — 模块级兜底视图（从 descriptor.dataBindings 读数据）══════

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
      _ => DataList(
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


