/// Chart 槽位——从 [ComponentDescriptor.config] 读取数据渲染图表。
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import '../shared/widgets/chart_renderer.dart';

/// Chart 组件——直接读取 config 中的 type/title/data/legend。
/// 不重复渲染标题（slot card header 已显示），图表占满可用空间。
class ChartSlot extends StatelessWidget {
  final ComponentDescriptor config;

  const ChartSlot({super.key, required this.config});

  @override
  Widget build(BuildContext context) {
    final cfg = config.config;
    final type = cfg['type'] as String? ?? 'bar';
    final title = cfg['title'] as String? ?? '';
    final data = (cfg['data'] as List<dynamic>?) ?? [];

    final labels = <String>[];
    final values = <double>[];
    for (final item in data) {
      if (item is Map<String, dynamic>) {
        labels.add(item['label'] as String? ?? '');
        values.add((item['value'] as num?)?.toDouble() ?? 0);
      }
    }

    return ChartRenderer(
      chartConfigs: [
        ChartConfig(
          type: type,
          title: title,
          labels: labels,
          values: values,
        ),
      ],
    );
  }
}
