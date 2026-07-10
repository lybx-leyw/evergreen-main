/// HTML render: renderChart
import 'dart:convert';
import '../shared/html_helpers.dart';

String renderChart(Map<String, dynamic> comp) {
  final chartCfg = (comp['config'] as Map<String, dynamic>? ?? {})['chart'] as Map<String, dynamic>? ?? {};
  final type = chartCfg['type'] as String? ?? 'bar';
  final title = chartCfg['title'] as String? ?? '';
  final legend = chartCfg['legend'] == true;

  switch (type) {
    case 'pie':
    case 'donut':
      return renderPieChart(title, type == 'donut', legend, chartCfg);
    case 'line':
    case 'radar':
      return renderLineChart(title, type, chartCfg);
    case 'bar':
    default:
      return renderBarChart(title, chartCfg, legend);
  }
}
