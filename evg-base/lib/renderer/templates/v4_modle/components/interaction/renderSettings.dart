/// HTML render: renderSettings
import 'dart:convert';
import 'package:evergreen_base/renderer/components/shared/html_helpers.dart';

String renderSettings(Map<String, dynamic> comp) {
  final cfg = comp['config'] as Map<String, dynamic>? ?? {};
  final settings = (cfg['settings'] as List<dynamic>? ?? [])
      .whereType<Map<dynamic, dynamic>>()
      .toList();
  if (settings.isEmpty) {
    return renderEmpty('settings', '暂无设置项');
  }
  final rows = settings.map((s) {
    final label = esc((s['label'] ?? s['key'] ?? '').toString());
    final type = esc((s['type'] ?? 'string').toString());
    final hint = s['hint'] != null ? '<div class="evg-set-hint">${esc(s['hint'].toString())}</div>' : '';
    final value = s['value'] ?? s['default'] ?? '';
    final ctrl = switch (type) {
      'bool' => '<input type="checkbox" ${value == true || value == 'true' ? 'checked' : ''} />',
      'option' => '<select>${((s['options'] as List<dynamic>? ?? []).map((o) {
        final ov = o is Map ? o['value'] : o;
        final ol = o is Map ? o['label'] : o;
        return '<option ${ov == value ? 'selected' : ''}>${esc(ol.toString())}</option>';
      }).join(''))}</select>',
      _ => '<input type="text" value="${esc(value.toString())}" />',
    };
    return '''
<div class="evg-set-row">
  <div class="evg-set-label">$label $hint</div>
  <div class="evg-set-ctrl">$ctrl</div>
</div>''';
  }).join('');
  return '''
<div class="evg-comp evg-comp-settings">
  <div class="evg-comp-title">⚙️ 设置</div>
  <div class="evg-set-list">$rows</div>
</div>''';
}
