/// Dashboard 视图——仪表盘卡片网格。
///
/// 公开类：[DashboardView]
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import '../widgets/dashboard_card.dart';
import '../widgets/empty_state.dart';

/// 仪表盘范式完整视图。
///
/// 遍历 [ModuleDescriptor.dataBindings]，每个渲染为一张 [DashboardCard]。
///
/// KPI 数值通过 [kpiData] 参数由上层（DataOrchestrator）注入。
/// key = dataType, value = (value, trend, subtitle)。
/// 未提供时卡片仅显示标题。
class DashboardView extends StatelessWidget {
  final ModuleDescriptor descriptor;

  /// dataType → (value, trend, subtitle) 的 KPI 数据映射。
  final Map<String, ({String? value, String? trend, String? subtitle})> kpiData;

  const DashboardView({
    super.key,
    required this.descriptor,
    this.kpiData = const {},
  });

  @override
  Widget build(BuildContext context) {
    final bindings = descriptor.dataBindings;

    if (bindings.isEmpty) {
      return const EmptyState(
        icon: Icons.dashboard_outlined,
        title: '暂无仪表盘数据',
        subtitle: '添加数据绑定以显示 KPI 卡片',
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 900
            ? 4
            : constraints.maxWidth > 600
                ? 3
                : 2;

        return GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.5,
          ),
          padding: const EdgeInsets.all(16),
          itemCount: bindings.length,
          itemBuilder: (context, index) {
            final binding = bindings[index];
            final kpi = kpiData[binding.dataType];
            return DashboardCard(
              title: binding.dataType,
              display: binding.display,
              value: kpi?.value?.toString(),
              trend: kpi?.trend,
              subtitle: kpi?.subtitle,
            );
          },
        );
      },
    );
  }
}
