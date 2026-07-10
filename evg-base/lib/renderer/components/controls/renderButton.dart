/// HTML render: renderButton
import 'dart:convert';
import '../shared/html_helpers.dart';

String renderButton(Map<String, dynamic> comp) {
  final cfg = comp['config'] as Map<String, dynamic>? ?? {};
  final align = cfg['align'] as String? ?? 'left';
  final buttons = (cfg['buttons'] as List<dynamic>? ?? [])
      .map((b) {
        final m = b as Map<String, dynamic>? ?? {};
        final label = m['label'] as String? ?? '';
        final icon = m['icon'] as String? ?? '';
        final style = m['style'] as String? ?? 'filled';
        final event = m['event'] as String? ?? '';
        return '<button class="evg-btn evg-btn-$style" data-event="${esc(event)}">'
            '${icon != null && icon!.isNotEmpty ? '$icon ' : ''}${esc(label)}</button>';
      })
      .join('');
  return '''
<div class="evg-comp evg-comp-button">
  <div class="evg-btn-bar" style="justify-content:${align == 'right' ? 'flex-end' : align == 'center' ? 'center' : 'flex-start'}">$buttons</div>
</div>''';
}
