/// HTML render: renderWhiteboard
import 'dart:convert';
import '../shared/html_helpers.dart';

String renderWhiteboard(Map<String, dynamic> comp) {
  final cfg = comp['config'] as Map<String, dynamic>? ?? {};

  return '''
<div class="evg-comp evg-comp-whiteboard">
  <div class="evg-wb-toolbar">
    <button class="evg-wb-tool" title="画笔">✏️</button>
    <button class="evg-wb-tool" title="橡皮">🧹</button>
    <button class="evg-wb-tool" title="形状">⬜</button>
    <button class="evg-wb-tool" title="文字">🔤</button>
    <span style="flex:1"></span>
    <button class="evg-wb-tool" title="撤销">↩️</button>
    <button class="evg-wb-tool" title="重做">↪️</button>
    <button class="evg-wb-tool" title="清空">🗑️</button>
  </div>
  <div class="evg-wb-canvas">
    <div class="evg-wb-placeholder">
      <span style="font-size:48px;opacity:.3">🎨</span>
      <span style="font-size:14px;color:var(--evg-text-secondary)">白板画布 — 在此区域绘图</span>
    </div>
  </div>
</div>''';
}
