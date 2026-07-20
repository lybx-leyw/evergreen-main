/// HTML render: renderVideo
import 'dart:convert';
import 'package:evergreen_base/renderer/components/shared/html_helpers.dart';

String renderVideo(Map<String, dynamic> comp) {
  final cfg = comp['config'] as Map<String, dynamic>? ?? {};
  final url = cfg['url'] as String? ?? '';
  if (url.isNotEmpty) {
    return '''
<div class="evg-comp evg-comp-video">
  <div class="evg-video-placeholder">
    <video src="${esc(url)}" controls style="max-width:100%;border-radius:8px"></video>
  </div>
</div>''';
  }
  return '''
<div class="evg-comp evg-comp-video">
  <div class="evg-video-placeholder">
    <div class="evg-video-icon">▶</div>
    <div class="evg-video-text">视频播放器</div>
    <div class="evg-video-controls">
      <span>▶</span><span>⏸</span><span>🔊</span>
      <span style="flex:1;height:4px;background:var(--evg-border-default);border-radius:2px;margin:0 8px"></span>
      <span>⛶</span><span>⚙</span>
    </div>
  </div>
</div>''';
}
