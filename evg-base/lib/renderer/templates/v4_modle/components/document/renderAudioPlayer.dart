/// HTML render: renderAudioPlayer
import 'dart:convert';
import 'package:evergreen_base/renderer/components/shared/html_helpers.dart';

String renderAudioPlayer(Map<String, dynamic> comp) {
  final cfg = comp['config'] as Map<String, dynamic>? ?? {};
  final src = cfg['src'] as String? ?? '';
  final title = cfg['title'] as String? ?? '音频播放器';

  final audioEl = src.isNotEmpty
      ? '<audio controls style="width:100%"><source src="${esc(src)}" /></audio>'
      : '<div class="evg-audio-placeholder">🎵 音频文件未指定<br><span style="font-size:11px;color:var(--evg-text-tertiary)">在 config.src 中设置音频 URL</span></div>';

  return '''
<div class="evg-comp evg-comp-audio">
  <div class="evg-comp-title">🎵 ${esc(title)}</div>
  <div class="evg-audio-body">$audioEl</div>
</div>''';
}
