/// V2 Style JSON 超参数 → CSS 转换器。
///
/// 将 Manifest V2 的 `style` JSON 对象映射为 CSS inline style 字符串。
/// 覆盖 TARGET_MODULE_JSON.md 第四节定义的全部超参数。
library;

/// 将 V2 style Map 转换为 CSS inline style 字符串。
String styleToCss(Map<String, dynamic>? style) {
  if (style == null || style.isEmpty) return '';

  final css = <String>[];
  final m = style;

  // ── 尺寸 ──
  _add(css, 'width', m['width']);
  _add(css, 'height', m['height']);
  _addIf(css, 'min-width', m['minWidth']);
  _addIf(css, 'max-width', m['maxWidth']);
  _addIf(css, 'min-height', m['minHeight']);
  _addIf(css, 'max-height', m['maxHeight']);

  // ── 间距 ──
  _addPx(css, 'padding', m['padding']);
  _addPxIf(css, 'padding-top', m['paddingTop']);
  _addPxIf(css, 'padding-right', m['paddingRight']);
  _addPxIf(css, 'padding-bottom', m['paddingBottom']);
  _addPxIf(css, 'padding-left', m['paddingLeft']);
  _addPx(css, 'margin', m['margin']);
  _addPxIf(css, 'margin-top', m['marginTop']);
  _addPxIf(css, 'margin-right', m['marginRight']);
  _addPxIf(css, 'margin-bottom', m['marginBottom']);
  _addPxIf(css, 'margin-left', m['marginLeft']);

  // ── 外观 ──
  _addStr(css, 'background', m['background']);
  _addPx(css, 'border-radius', m['borderRadius']);
  _addStr(css, 'border', m['border']);
  _addStr(css, 'box-shadow', m['shadow']);
  _addNum(css, 'opacity', m['opacity']);

  // ── Flex ──
  _addNum(css, 'flex', m['flex']);
  _addStr(css, 'flex-direction', m['flexDirection']);
  _addStrMapped(css, 'justify-content', m['justifyContent'], _alignMap);
  _addStrMapped(css, 'align-items', m['alignItems'], _alignMap);
  _addStrMapped(css, 'align-self', m['alignSelf'], _alignMap);
  _addPx(css, 'gap', m['gap']);
  if (m.containsKey('wrap')) {
    css.add('flex-wrap: ${m['wrap'] == true ? 'wrap' : 'nowrap'}');
  }

  // ── Grid ──
  _addStr(css, 'grid-column', m['gridColumn']);
  _addStr(css, 'grid-row', m['gridRow']);

  // ── Position ──
  _addStr(css, 'position', m['position']);
  _addPxIf(css, 'top', m['top']);
  _addPxIf(css, 'right', m['right']);
  _addPxIf(css, 'bottom', m['bottom']);
  _addPxIf(css, 'left', m['left']);
  _addNum(css, 'z-index', m['zIndex']);

  // ── 文字 ──
  _addStr(css, 'color', m['color']);
  _addPx(css, 'font-size', m['fontSize']);
  _addStr(css, 'font-weight', m['fontWeight']);
  _addStr(css, 'text-align', m['textAlign']);

  // ── 溢出 ──
  _addStr(css, 'overflow', m['overflow']);

  return css.join('; ');
}

/// CSS 值：number → "Npx"，string → 原样。
String cssVal(dynamic v) {
  if (v == null) return '';
  if (v is num) return '${v}px';
  return v.toString();
}

// ── 内部辅助 ──

const _alignMap = <String, String>{
  'start': 'flex-start',
  'end': 'flex-end',
  'between': 'space-between',
  'around': 'space-around',
  'evenly': 'space-evenly',
};

void _add(List<String> css, String key, dynamic val) {
  if (val != null) css.add('$key: ${cssVal(val)}');
}

void _addIf(List<String> css, String key, dynamic val) {
  if (val != null) css.add('$key: ${cssVal(val)}');
}

void _addPx(List<String> css, String key, dynamic val) {
  if (val != null) css.add('$key: ${cssVal(val)}');
}

void _addPxIf(List<String> css, String key, dynamic val) {
  if (val != null) css.add('$key: ${cssVal(val)}');
}

void _addStr(List<String> css, String key, dynamic val) {
  if (val != null && val is String && val.isNotEmpty) {
    css.add('$key: $val');
  }
}

void _addNum(List<String> css, String key, dynamic val) {
  if (val != null) css.add('$key: $val');
}

void _addStrMapped(
    List<String> css, String key, dynamic val, Map<String, String> map) {
  if (val != null && val is String) {
    css.add('$key: ${map[val] ?? val}');
  }
}
