/// 范式视图演示——展示 shared/ 层的 ModuleDispatch 范式调度机制。
///
/// 使用 mock ModuleDescriptor 触发三种 UI 范式：
/// - chat（AI 对话）
/// - dashboard（仪表盘）
/// - composite（复合视图）

import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import '../module/module_dispatch.dart';
import '../components/shared/widgets/models.dart';

/// 范式选择器——让用户在三种范式之间切换。
class ParadigmDemo extends StatefulWidget {
  const ParadigmDemo({super.key});

  @override
  State<ParadigmDemo> createState() => _ParadigmDemoState();
}

class _ParadigmDemoState extends State<ParadigmDemo> {
  String _selectedParadigm = 'chat';

  static const _paradigms = [
    ('chat', 'Chat', 'AI 对话范式'),
    ('dashboard', 'Dashboard', '仪表盘范式'),
    ('composite', 'Composite', '复合视图范式'),
  ];

  // ── Mock ModuleDescriptor ──
  ModuleDescriptor _buildDescriptor(String ui) {
    switch (ui) {
      case 'chat':
        return ModuleDescriptor(
          id: 'demo-chat',
          name: 'Chat 演示',
          description: 'AI 对话范式演示模块',
          ui: 'chat',
          chat: const ChatOptions(),
        );
      case 'dashboard':
        return ModuleDescriptor(
          id: 'demo-dashboard',
          name: 'Dashboard 演示',
          description: '仪表盘范式演示模块',
          ui: 'dashboard',
          dataBindings: [
            const DataBindingDescriptor(
              dataType: 'kpi',
              display: 'card',
              columns: ['title', 'value', 'trend', 'subtitle'],
            ),
          ],
        );
      case 'composite':
        return ModuleDescriptor(
          id: 'demo-composite',
          name: 'Composite 演示',
          description: '复合视图范式演示模块',
          ui: 'composite',
          pages: [
            const PageDescriptor(
              id: 'page1',
              label: '工作区',
              layout: LayoutDescriptor(
                grid: GridOptions(columns: 1, gap: 16),
              ),
              slots: {},
            ),
            const PageDescriptor(
              id: 'page2',
              label: '数据',
              layout: LayoutDescriptor(
                grid: GridOptions(columns: 2, gap: 16),
              ),
              slots: {},
            ),
          ],
        );
      default:
        return ModuleDescriptor(
          id: 'demo-default',
          name: '默认演示',
          ui: 'default',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final descriptor = _buildDescriptor(_selectedParadigm);

    return Column(
      children: [
        // 范式选择器
        _buildParadigmSelector(),
        // 当前范式的 ModuleDispatch 渲染
        Expanded(
          child: ModuleDispatch(descriptor: descriptor),
        ),
      ],
    );
  }

  Widget _buildParadigmSelector() {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ModuleDispatch 范式调度演示',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              '根据 descriptor.ui 字段 → switch → 对应范式视图',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: _paradigms.map((p) {
                final selected = _selectedParadigm == p.$1;
                return ChoiceChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(p.$2),
                      const SizedBox(width: 4),
                      Text(
                        p.$3,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: selected
                                  ? Theme.of(context).colorScheme.onPrimaryContainer
                                  : Theme.of(context).colorScheme.outline,
                            ),
                      ),
                    ],
                  ),
                  selected: selected,
                  onSelected: (v) {
                    if (v) setState(() => _selectedParadigm = p.$1);
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
