/// HTML render: renderDataDashboard — 数据中枢面板（静态导出）。
///
/// Dart 端 [DataDashboardView]（page/data_dashboard_view.dart）在运行时直连
/// DataOrchestrator，实时展示已注册数据源的连通/新鲜度状态，永不静态渲染。
/// 静态 HTML 导出无运行时 orchestrator 状态，因此本渲染器按 config 真实字段渲染：
/// - 优先渲染 `config.cards[]`（卡片网格，每项 `title`/`label` + `value`）；
/// - 无 cards 时读取 `config.sources[]` / `config.dataSources[]` 数据源清单
///   （每项 `name` / `displayName` / `category`），按 category 分组呈现；
/// - 两者皆无时渲染说明性面板，如实标注该组件的运行时动态特性。
/// 全程读取 config 真实字段，不写死示例冒充（遵循 M1 R4 / R11）。
library;

import '../shared/html_helpers.dart';

String renderDataDashboard(Map<String, dynamic> comp) {
  final cfg = comp['config'] as Map<String, dynamic>? ?? {};
  final title = cfg['title'] as String? ?? '数据中枢';

  // ① 卡片网格（对齐 P1-4 原意：复用 dataBindings/cards 渲染卡片）
  final cards = (cfg['cards'] is List ? cfg['cards'] as List : const <dynamic>[])
      .whereType<Map>()
      .map((e) => e.cast<String, dynamic>())
      .toList();
  if (cards.isNotEmpty) {
    final cardsHtml = cards.map((c) {
      final ct = esc((c['title'] ?? c['label'] ?? '').toString());
      final cv = esc((c['value'] ?? '').toString());
      return '''
<div class="evg-dd-card" style="padding:10px 12px;border:1px solid var(--evg-border,#3334);border-radius:8px">
  <div class="evg-dd-name" style="font-size:12px;opacity:.7">$ct</div>
  ${cv.isNotEmpty ? '<div class="evg-dd-value" style="font-size:20px;font-weight:700">$cv</div>' : ''}
</div>''';
    }).join('');
    return '''
<div class="evg-comp evg-comp-data-dashboard">
  <div class="evg-comp-title">📊 ${esc(title)}</div>
  <div class="evg-dd-grid" style="display:grid;grid-template-columns:repeat(auto-fill,minmax(140px,1fr));gap:8px">$cardsHtml</div>
</div>''';
  }

  // ② 数据源清单（按 category 分组，对齐 Dart 端 DataDashboardView 分组语义）
  final rawSources = cfg['sources'] ?? cfg['dataSources'];
  final sources = (rawSources is List ? rawSources : const <dynamic>[])
      .whereType<Map>()
      .map((e) => e.cast<String, dynamic>())
      .toList();
  if (sources.isNotEmpty) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final s in sources) {
      final cat = (s['category'] as String?)?.isNotEmpty == true
          ? s['category'] as String
          : '其他';
      grouped.putIfAbsent(cat, () => []).add(s);
    }
    final groupsHtml = grouped.entries.map((entry) {
      final cardsHtml = entry.value.map((s) {
        final name = esc((s['displayName'] ?? s['name'] ?? '未命名').toString());
        final id = esc((s['name'] ?? '').toString());
        return '''
<div class="evg-dd-card" style="display:flex;align-items:center;gap:8px;padding:8px 10px;margin:4px 0;border:1px solid var(--evg-border,#3334);border-radius:8px">
  <span class="evg-dd-dot" style="width:8px;height:8px;border-radius:50%;background:#4caf50;flex:none"></span>
  <div class="evg-dd-body">
    <div class="evg-dd-name">$name</div>
    ${id.isNotEmpty && id != name ? '<div class="evg-dd-id" style="font-size:11px;opacity:.6">$id</div>' : ''}
  </div>
</div>''';
      }).join('');
      return '<div class="evg-dd-group"><div class="evg-dd-group-title" style="font-weight:600;margin:8px 0 4px;opacity:.8">${esc(entry.key)}</div>$cardsHtml</div>';
    }).join('');
    return '''
<div class="evg-comp evg-comp-data-dashboard">
  <div class="evg-comp-title">📊 ${esc(title)}</div>
  <div class="evg-dd-summary" style="font-size:12px;opacity:.7;margin-bottom:8px">共 ${sources.length} 个数据源</div>
  $groupsHtml
</div>''';
  }

  // ③ 说明性面板（运行时动态，静态导出无实时状态）
  return '''
<div class="evg-comp evg-comp-data-dashboard">
  <div class="evg-comp-title">📊 ${esc(title)}</div>
  <div class="evg-dd-note" style="font-size:13px;opacity:.7;padding:8px 0">运行时展示已注册数据源的连通与新鲜度状态；静态导出不含实时状态。</div>
</div>''';
}
