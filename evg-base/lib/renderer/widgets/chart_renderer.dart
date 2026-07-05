/// 图表渲染器——柱状图/折线图/饼图占位渲染。
///
/// 公开类：[ChartRenderer]
import 'package:flutter/material.dart';

/// 图表配置模型。
class ChartConfig {
  final String type; // bar | line | pie
  final String title;
  final List<String> labels;
  final List<double> values;

  const ChartConfig({
    required this.type,
    this.title = '',
    this.labels = const [],
    this.values = const [],
  });
}

/// 图表渲染组件。
///
/// 支持 bar / line / pie 三种简图（文字模拟），
/// 后续可接入 fl_chart 等专业图表库。
class ChartRenderer extends StatelessWidget {
  final List<ChartConfig> chartConfigs;

  const ChartRenderer({super.key, this.chartConfigs = const []});

  @override
  Widget build(BuildContext context) {
    if (chartConfigs.isEmpty) return const SizedBox.shrink();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: chartConfigs.map((config) {
          return Container(
            width: 300,
            height: 180,
            margin: const EdgeInsets.all(8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  config.title.isNotEmpty ? config.title : config.type,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _buildChart(config, context),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildChart(ChartConfig config, BuildContext context) {
    if (config.values.isEmpty) {
      return const Center(child: Text('无数据'));
    }

    return switch (config.type.toLowerCase()) {
      'bar' => _buildBarChart(config, context),
      'line' => _buildLineChart(config, context),
      'pie' => _buildPieChart(config, context),
      _ => _buildBarChart(config, context),
    };
  }

  Widget _buildBarChart(ChartConfig config, BuildContext context) {
    final max = config.values.reduce((a, b) => a > b ? a : b);
    if (max == 0) return const Center(child: Text('无数据'));

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(config.values.length, (i) {
        final ratio = config.values[i] / max;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Flexible(
                  flex: (ratio * 100).round(),
                  child: Container(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  config.labels.length > i ? config.labels[i] : '',
                  style: const TextStyle(fontSize: 8),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _buildLineChart(ChartConfig config, BuildContext context) {
    return Center(
      child: Text(
        '折线图 (${config.values.length} 个数据点)',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }

  Widget _buildPieChart(ChartConfig config, BuildContext context) {
    return Center(
      child: Text(
        '饼图 (${config.values.length} 个类别)',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}
