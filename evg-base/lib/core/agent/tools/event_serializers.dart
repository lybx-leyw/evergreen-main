/// AgentEvent ↔ SSE / JSON Map 序列化工具（AgentHttpServer + ScriptedAgentHttpServer 共享）。
library;

import 'dart:convert';

import '../event.dart';

/// AgentEvent → SSE 帧字符串。
String eventToSseFrame(AgentEvent e) {
  switch (e.kind) {
    case EventKind.turnStarted:  return jsonEncode({'type': 'turn_started'});
    case EventKind.reasoning:    return jsonEncode({'type': 'reasoning', 'text': e.reasoning ?? ''});
    case EventKind.text:         return jsonEncode({'type': 'text', 'text': e.text ?? ''});
    case EventKind.toolDispatch: return jsonEncode({'type': 'tool_dispatch', 'id': e.tool?.id, 'name': e.tool?.name, 'arguments': e.tool?.arguments});
    case EventKind.toolResult:   return jsonEncode({'type': 'tool_result', 'id': e.tool?.id, 'name': e.tool?.name, 'output': e.tool?.output, 'error': e.tool?.error});
    case EventKind.notice:       return jsonEncode({'type': 'notice', 'text': e.text ?? '', 'level': e.noticeLevel?.name});
    case EventKind.approvalRequest: return jsonEncode({'type': 'approval_request', 'name': e.tool?.name, 'arguments': e.tool?.arguments});
    case EventKind.turnDone:     return jsonEncode({'type': 'turn_done', 'usage': e.usage != null ? {'total': e.usage!.totalTokens} : null, 'error': e.error});
    default:                     return jsonEncode({'type': 'unknown', 'kind': e.kind.name});
  }
}

/// AgentEvent → Map（用于 /agent/chat 非流式响应）。
Map<String, dynamic> eventToJsonMap(AgentEvent e) {
  return {
    'kind': e.kind.name,
    'text': e.text,
    'reasoning': e.reasoning,
    'tool': e.tool != null
        ? {'id': e.tool!.id, 'name': e.tool!.name, 'arguments': e.tool!.arguments, 'output': e.tool!.output, 'error': e.tool!.error}
        : null,
    'usage': e.usage != null ? {'total': e.usage!.totalTokens} : null,
    'error': e.error,
  };
}
