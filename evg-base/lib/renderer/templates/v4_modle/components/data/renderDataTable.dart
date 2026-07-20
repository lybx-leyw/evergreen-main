/// HTML render: renderDataTable
import 'dart:convert';
import 'package:evergreen_base/renderer/components/shared/html_helpers.dart';

String renderDataTable(Map<String, dynamic> comp) {
  final cfg = comp['config'] as Map<String, dynamic>? ?? {};
  final display = cfg['display'] as String? ?? 'table';
  final title = cfg['title'] as String? ?? '';
  final columns = (cfg['columns'] as List<dynamic>?)
      ?.map((c) => c is Map ? c : {'key': c.toString(), 'label': c.toString()})
      .toList() ?? [{'key': 'id', 'label': 'ID'}, {'key': 'name', 'label': '名称'}, {'key': 'status', 'label': '状态'}];
  final filter = cfg['filter'] == true;
  final sortable = cfg['sortable'] == true;
  // R10 渲染日志升级：真实数据行（由外部数据源拉取后注入 config.rows）。
  final rowsRaw = (cfg['rows'] as List<dynamic>?)
      ?.whereType<Map<dynamic, dynamic>>()
      .toList() ?? const <Map<dynamic, dynamic>>[];
  final rows = rowsRaw.map((r) => r.map((k, v) => MapEntry(k.toString(), v as dynamic))).toList();

  if (display == 'card') return renderDataCards(title, columns, rows);
  return renderDataTableHTML(title, columns, filter, sortable, rows);
}
