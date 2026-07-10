/// HTML render: renderStatTile
import 'dart:convert';
import '../shared/html_helpers.dart';

String renderStatTile(Map<String, dynamic> comp) {
  final cfg = comp['config'] as Map<String, dynamic>? ?? {};
  final title = cfg['title'] as String? ?? '统计';
  final value = cfg['value'] as String? ?? '—';
  final subtitle = cfg['subtitle'] as String? ?? '';
  final trend = cfg['trend'] as String?;
  final trendUp = cfg['trendUp'] as bool?;
  final icon = cfg['icon'] as String? ?? '';

  final trendHtml = trend != null
      ? '<span class="evg-stat-trend${trendUp == true ? ' up' : ' down'}">${trendUp == true ? '▲' : '▼'} $trend</span>'
      : '';

  return '''
<div class="evg-comp evg-comp-stat-tile">
  <div class="evg-stat-header">
    ${icon.isNotEmpty ? '<span class="evg-stat-icon">$icon</span>' : ''}
    <span class="evg-stat-title">${esc(title)}</span>
  </div>
  <div class="evg-stat-value">${esc(value)}</div>
  $trendHtml
  ${subtitle.isNotEmpty ? '<div class="evg-stat-subtitle">${esc(subtitle)}</div>' : ''}
</div>''';
}
