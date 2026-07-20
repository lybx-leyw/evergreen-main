/// HTML render: renderChat
import 'dart:convert';
import 'package:evergreen_base/renderer/components/shared/html_helpers.dart';

String renderChat(Map<String, dynamic> comp) {
  final cfg = comp['config'] as Map<String, dynamic>? ?? {};
  final input = comp['input'] as Map<String, dynamic>? ?? {};
  final placeholder = cfg['placeholder'] as String? ?? '输入消息...';
  final thinking = cfg['thinking'] as Map<String, dynamic>? ?? {};
  final thinkingVisible = thinking['visible'] == true;
  final bubble = cfg['bubble'] as Map<String, dynamic>? ?? {};
  final showAvatar = bubble['showAvatar'] == true;

  // ai-assistant 专用真实字段
  final preset = cfg['preset'] as String?;
  final systemPrompt = cfg['system_prompt'] as String?;
  final toolsRaw = cfg['tools'];
  final toolsList = toolsRaw is List
      ? toolsRaw
      : (toolsRaw is Map ? toolsRaw.values.toList() : <dynamic>[]);
  final tools = toolsList
      .map((t) => esc((t is Map ? (t['name'] ?? t['id']) : t).toString()))
      .join('、');
  final multiSession = cfg['multi_session'] == true;
  final globalMemory = cfg['global_memory'] == true;

  final configPanel = (preset != null || systemPrompt != null || tools.isNotEmpty)
      ? '''
  <div class="evg-chat-config">
    ${preset != null ? '<div class="evg-chat-cfg-row"><b>预设</b>: ${esc(preset)}</div>' : ''}
    ${systemPrompt != null ? '<div class="evg-chat-cfg-row"><b>系统提示</b>: ${esc(systemPrompt)}</div>' : ''}
    ${tools.isNotEmpty ? '<div class="evg-chat-cfg-row"><b>工具</b>: $tools</div>' : ''}
    <div class="evg-chat-cfg-row"><b>多会话</b>: ${multiSession ? '开' : '关'} ｜ <b>全局记忆</b>: ${globalMemory ? '开' : '关'}</div>
  </div>'''
      : '';

  final qrRaw = input['quickReplies'];
  final quickReplies = (qrRaw is List ? qrRaw : <dynamic>[])
      .map((q) => '<span class="evg-quick-reply">${esc(q is Map ? (q['label'] ?? '') : '')}</span>')
      .join('');

  return '''
<div class="evg-comp evg-comp-chat">
  $configPanel
  <div class="evg-chat-msgs">
    <div class="evg-msg assistant">
      ${showAvatar ? '<div class="evg-avatar">AI</div>' : ''}
      <div class="evg-bubble">${preset != null ? '已加载预设「${esc(preset)}」，实时会话运行态加载。' : '实时会话运行态加载。'}${thinkingVisible ? '<br><i style="color:var(--evg-text-secondary);font-size:11px">思考中…</i>' : ''}</div>
    </div>
  </div>
  <div class="evg-chat-input">
    <input type="text" placeholder="${esc(placeholder)}" />
    <button>发送</button>
  </div>
  ${quickReplies.isNotEmpty ? '<div class="evg-quick-replies">$quickReplies</div>' : ''}
</div>''';
}
