/// 组合视图演示——展示 compositions/ 层的高级组合能力。
///
/// 展示 WorkspaceHub（工作区中枢：文件树 + 编辑器 + Chat 侧栏三合一）。

import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import '../compositions/workspace_hub.dart';

class CompositionDemo extends StatelessWidget {
  const CompositionDemo({super.key});

  @override
  Widget build(BuildContext context) {
    // Mock ModuleDescriptor for WorkspaceHub
    const descriptor = ModuleDescriptor(
      id: 'demo-workspace',
      name: '工作区演示',
      description: 'WorkspaceHub 组合视图演示',
      ui: 'composite',
      workspace: WorkspaceDescriptor(enabled: true),
    );

    return Column(
      children: [
        // 说明区域
        _buildInfoBar(context),
        // WorkspaceHub 全屏渲染
        const Expanded(
          child: WorkspaceHub(descriptor: descriptor),
        ),
      ],
    );
  }

  Widget _buildInfoBar(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'WorkspaceHub 组合视图',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              '第 3 层 compositions/ — 文件树 + 编辑器 + Chat 侧栏三合一',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildArchBadge(context, 'widgets/', Colors.green),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text('→', style: TextStyle(fontSize: 12)),
                ),
                _buildArchBadge(context, 'shared/', Colors.blue),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text('→', style: TextStyle(fontSize: 12)),
                ),
                _buildArchBadge(context, 'compositions/', Colors.purple),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildArchBadge(BuildContext context, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}
