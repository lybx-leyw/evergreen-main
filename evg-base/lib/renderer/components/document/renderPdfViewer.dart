/// HTML render: renderPdfViewer（M3 `pdf-viewer`）。
library;

import 'dart:convert';

import '../shared/html_helpers.dart';

String renderPdfViewer(Map<String, dynamic> comp) {
  final rawCfg = comp['config'];
  final cfg = rawCfg is Map ? rawCfg.cast<String, dynamic>() : <String, dynamic>{};
  final url = cfg['url'] as String? ?? '';
  final path = cfg['path'] as String? ?? '';
  final title = esc(cfg['title'] as String? ?? 'PDF 预览');
  final page = (cfg['page'] as num?)?.toInt() ?? 1;

  if (url.isEmpty && path.isEmpty) {
    return '''
<div class="evg-comp evg-comp-pdf">
  <div class="evg-empty">未提供 PDF 地址</div>
</div>''';
  }

  // 本地 path（asset）在 WebView / Web 内无法用 file:// 直接打开，降级提示移动端查看；
  // 远程 url 用原生 iframe 渲染（多数浏览器内置 PDF 查看器）。
  final src = url.isNotEmpty ? url : path;
  final isLocalOnly = url.isEmpty && path.isNotEmpty;
  final note = isLocalOnly
      ? '<div class="evg-pdf-note">本地文件，建议在桌面端 / 移动端查看</div>'
      : '';
  return '''
<div class="evg-comp evg-comp-pdf">
  <div class="evg-pdf-bar">📕 $title</div>$note
  <iframe src="${esc(src)}#page=$page" style="width:100%;height:70vh;border:0;border-radius:8px"></iframe>
</div>''';
}
