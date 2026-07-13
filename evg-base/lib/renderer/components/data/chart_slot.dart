/// Chart 槽位——从 [ComponentDescriptor.config] 读取数据渲染图表。
/// 支持 M2 dataSource 注入：拉取到的数据合并进 config['data']。
/// 兼容两种标准形态：List<{label,value}> 或 {labels, series:[{name,data}]}。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/renderer/data/data_source_slot.dart';
import '../shared/widgets/chart_renderer.dart';

/// Chart 组件——读取 config 中的 type/title/data。
class ChartSlot extends DataSourceSlot {
  const ChartSlot({super.key, required super.config});

  @override
  DataSourceSlotState<ChartSlot> createState() => _ChartSlotState();
}

class _ChartSlotState extends DataSourceSlotState<ChartSlot> {
  @override
  Map<String, dynamic> mergeData(Map<String, dynamic> base, dynamic resolved) {
    final merged = <String, dynamic>{...base};
    if (resolved is List) {
      merged['data'] = resolved;
    } else if (resolved is Map) {
      if (resolved['data'] is List) {
        merged['data'] = resolved['data'];
      } else if (resolved['labels'] is List && resolved['series'] is List) {
        // {labels, series:[{name,data:[...]}]} → List<{label,value}>
        final labels = resolved['labels'] as List;
        final series = resolved['series'] as List;
        final firstSeries = series.isNotEmpty ? series[0] : null;
        final pts = (firstSeries is Map && firstSeries['data'] is List)
            ? firstSeries['data'] as List
            : const <dynamic>[];
        final data = <Map<String, dynamic>>[];
        for (var i = 0; i < labels.length; i++) {
          data.add({
            'label': labels[i],
            'value': i < pts.length ? pts[i] : 0,
          });
        }
        merged['data'] = data;
      } else {
        merged.addAll(resolved as Map<String, dynamic>);
      }
    }
    return merged;
  }

  @override
  Widget buildStatic(Map<String, dynamic> cfg) {
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
