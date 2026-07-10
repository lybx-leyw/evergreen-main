/// V2 布局范式 → HTML/CSS 布局引擎。
///
/// 支持 5 种布局范式：grid | flex | fullscreen | absolute | dock。
/// 每种范式根据 `layout.preset` 超参数生成对应的 CSS 容器样式。
library;

import 'html_style.dart';

/// 根据 layout 配置生成容器 CSS。
String buildLayoutContainerCss(Map<String, dynamic>? layout) {
  if (layout == null) return 'display: flex; flex-direction: column; height: 100%';
  final type = layout['type'] as String? ?? 'flex';
  final preset = layout['preset'] as Map<String, dynamic>? ?? {};
  final style = layout['style'] as Map<String, dynamic>?;

  final css = <String>[];

  switch (type) {
    case 'grid':
      css.addAll(_buildGridCss(preset));
      break;
    case 'flex':
      css.addAll(_buildFlexCss(preset));
      break;
    case 'fullscreen':
      css.addAll(_buildFullscreenCss(preset));
      break;
    case 'absolute':
      css.addAll(_buildAbsoluteCss(preset));
      break;
    case 'dock':
      css.addAll(_buildDockCss(preset));
      break;
    default:
      css.add('display: flex');
      css.add('flex-direction: column');
  }

  // 合并 layout 自身的 style 超参数
  if (style != null) {
    final extra = styleToCss(style);
    if (extra.isNotEmpty) css.add(extra);
  }

  return css.join('; ');
}

/// 生成 slot 容器的 CSS（包含 grid 定位）。
String buildSlotWrapperCss(
    Map<String, dynamic>? slot, Map<String, dynamic>? layoutPreset) {
  final css = <String>[];
  final style = slot?['style'] as Map<String, dynamic>?;

  if (style != null) {
    final extra = styleToCss(style);
    if (extra.isNotEmpty) css.add(extra);
  }

  return css.join('; ');
}

/// 构建 slot 的 HTML 内容包装。
///
/// [slotName] 槽位名（如 "left", "center"）
/// [componentHtml] 内部组件的 HTML
/// [slot] 槽位的完整 JSON（含 style/process/events/component）
String wrapSlot(
    String slotName, String componentHtml, Map<String, dynamic> slot) {
  // 防御：安全类型转换
  Map<String, dynamic> _safeMap(dynamic v) =>
      v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};
  List<dynamic> _safeList(dynamic v) =>
      v is List ? v : <dynamic>[];

  final style = _safeMap(slot['style']);
  final events = _safeMap(slot['events']);
  final delegates = _safeMap(events['delegates']);
  final processes = _safeList(slot['process']);
  final emitList = _safeList(events['emit']);
  final listenList = _safeList(events['listen']);
  final comp = _safeMap(slot['component']);
  final compType = comp['type'] as String? ?? 'unknown';

  // 事件/进程徽章
  final badges = <String>[];
  if (emitList.isNotEmpty) badges.add(_badge('emit', '📤 ${emitList.length} emit'));
  if (listenList.isNotEmpty) badges.add(_badge('listen', '👂 ${listenList.length} listen'));
  if (delegates['onClick'] != null || delegates['onKeyPress'] != null) {
    badges.add(_badge('delegate', '🎯 delegate'));
  }
  if (processes.isNotEmpty) badges.add(_badge('process', '⚙️ ${processes.length}p'));

  // slot 层级的 padding
  final slotPadding = style['padding'] ?? 12;
  // 构建 slot body 内部的 style（排除 padding，由外层控制）
  final bodyStyleMap = Map<String, dynamic>.from(style);
  bodyStyleMap['padding'] = slotPadding;
  final wrapperCss = styleToCss(bodyStyleMap);

  return '''
<div class="evg-slot" style="$wrapperCss">
  <div class="evg-slot-header">
    <span class="evg-slot-name">📌 $slotName</span>
    <span class="evg-slot-type">$compType</span>
    ${badges.join('')}
  </div>
  <div class="evg-slot-body">
    $componentHtml
  </div>
</div>''';
}

// ── 5 种布局范式 ──

List<String> _buildGridCss(Map<String, dynamic> p) {
  final columns = (p['columns'] as num?)?.toInt() ?? 1;
  final gap = (p['gap'] as num?)?.toInt() ?? 8;
  final rows = p['rows'] as String? ?? 'auto';

  return [
    'display: grid',
    'grid-template-columns: ${List.filled(columns, '1fr').join(' ')}',
    'grid-template-rows: $rows',
    'gap: ${gap}px',
    'width: 100%',
    'height: 100%',
    'overflow: auto',
  ];
}

List<String> _buildFlexCss(Map<String, dynamic> p) {
  final dir = p['direction'] as String? ?? 'row';
  final wrap = p['wrap'] == true;
  final gap = (p['gap'] as num?)?.toInt() ?? 8;
  final justify = (p['justify'] as String?) ?? 'start';
  final align = (p['align'] as String?) ?? 'stretch';

  return [
    'display: flex',
    'flex-direction: $dir',
    'flex-wrap: ${wrap ? 'wrap' : 'nowrap'}',
    'gap: ${gap}px',
    'justify-content: ${_mapFlexAlign(justify)}',
    'align-items: ${_mapFlexAlign(align)}',
    'width: 100%',
    'height: 100%',
    'overflow: auto',
  ];
}

List<String> _buildFullscreenCss(Map<String, dynamic> p) {
  return [
    'display: flex',
    'flex-direction: column',
    'width: 100%',
    'height: 100%',
    'overflow: hidden',
  ];
}

List<String> _buildAbsoluteCss(Map<String, dynamic> p) {
  return [
    'position: relative',
    'width: 100%',
    'height: 100%',
    'overflow: hidden',
  ];
}

List<String> _buildDockCss(Map<String, dynamic> p) {
  // dock 布局用 CSS Grid template areas
  // 优先从嵌套的 "regions" 键读取（manifest 规范格式），回退到顶层直接读取
  final r = (p['regions'] is Map<String, dynamic>)
      ? p['regions'] as Map<String, dynamic>
      : p;
  final topH = ((r['top'] as Map<String, dynamic>?)?['height'] as num?)?.toInt() ?? 0;
  final bottomH = ((r['bottom'] as Map<String, dynamic>?)?['height'] as num?)?.toInt() ?? 0;
  final leftW = ((r['left'] as Map<String, dynamic>?)?['width'] as num?)?.toInt() ?? 0;
  final rightW = ((r['right'] as Map<String, dynamic>?)?['width'] as num?)?.toInt() ?? 0;

  final rows = <String>[];
  if (topH > 0) rows.add('${topH}px');
  rows.add('1fr');
  if (bottomH > 0) rows.add('${bottomH}px');

  final cols = <String>[];
  if (leftW > 0) cols.add('${leftW}px');
  cols.add('1fr');
  if (rightW > 0) cols.add('${rightW}px');

  return [
    'display: grid',
    'grid-template-rows: ${rows.join(' ')}',
    'grid-template-columns: ${cols.join(' ')}',
    'width: 100%',
    'height: 100%',
    'overflow: hidden',
  ];
}

String _mapFlexAlign(String v) {
  return _flexAlignMap[v] ?? v;
}

const _flexAlignMap = <String, String>{
  'start': 'flex-start',
  'end': 'flex-end',
  'between': 'space-between',
  'around': 'space-around',
  'evenly': 'space-evenly',
};

String _badge(String kind, String text) {
  final cls = kind == 'listen' ? 'evg-badge-listen' : 'evg-badge';
  return '<span class="$cls">$text</span>';
}
