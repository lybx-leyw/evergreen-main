/// HTML render: renderWebView
import 'dart:convert';
import 'package:evergreen_base/renderer/components/shared/html_helpers.dart';

String renderWebView(Map<String, dynamic> comp) {
  final cfg = comp['config'] as Map<String, dynamic>? ?? {};
  final url = cfg['url'] as String? ?? 'about:blank';
  final allowScripts = cfg['allowScripts'] as bool? ?? true;

  return '''
<div class="evg-comp evg-comp-webview">
  <div class="evg-wv-toolbar">
    <button class="evg-wv-btn" title="后退">◀</button>
    <button class="evg-wv-btn" title="前进">▶</button>
    <button class="evg-wv-btn" title="刷新">🔄</button>
    <span class="evg-wv-url">${esc(url)}</span>
  </div>
  <div class="evg-wv-content">
    <iframe src="${esc(url)}" class="evg-wv-iframe" ${allowScripts ? 'sandbox="allow-scripts allow-same-origin"' : 'sandbox=""'}></iframe>
  </div>
</div>''';
}
