/// AI 对话页面——SSE 流式输出 + 工具调用展示。
library;

import 'dart:io';
import 'helpers.dart';

Future<void> textChat(Map<String, int> ports) async {
  ctaHeader('AI 对话 — SSE 流式');
  print('  (输入消息，回车发送。输入 /q 返回)');

  while (true) {
    stdout.write('\n  You > ');
    final input = stdin.readLineSync()?.trim() ?? '';
    if (input.isEmpty) continue;
    if (input == '/q') break;

    stdout.write('  AI > ');
    try {
      final events = await ctaSse(ports['Agent']!, '/agent/chat/stream', {'input': input});
      for (final e in events) {
        if (e['type'] == 'text') {
          stdout.write(e['text']);
        } else if (e['type'] == 'tool_dispatch') {
          stdout.write('\n       🔧 调用工具: ${e['name']}');
        } else if (e['type'] == 'tool_result') {
          final out = e['output'] as String? ?? '';
          stdout.write('\n       📋 结果: ${out.length > 80 ? '${out.substring(0, 80)}...' : out}');
        }
      }
      print('');
    } catch (e) {
      print('\n  ❌ 对话失败: $e');
    }
  }
}
