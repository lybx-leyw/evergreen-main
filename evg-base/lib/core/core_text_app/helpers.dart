/// Core Text App — 共享 HTTP 辅助函数。
library;

import 'dart:convert';
import 'dart:io';

Future<Map<String, dynamic>> ctaGet(int port, String path) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse('http://127.0.0.1:$port$path'));
    final resp = await req.close();
    final raw = await resp.transform(utf8.decoder).join();
    return jsonDecode(raw) as Map<String, dynamic>;
  } finally {
    client.close();
  }
}

Future<Map<String, dynamic>> ctaPost(int port, String path, Map<String, dynamic> body) async {
  final client = HttpClient();
  try {
    final req = await client.postUrl(Uri.parse('http://127.0.0.1:$port$path'));
    req.headers.contentType = ContentType.json;
    final bytes = utf8.encode(jsonEncode(body));
    req.contentLength = bytes.length;
    req.add(bytes);
    final resp = await req.close();
    final raw = await resp.transform(utf8.decoder).join();
    return jsonDecode(raw) as Map<String, dynamic>;
  } finally {
    client.close();
  }
}

Future<List<Map<String, dynamic>>> ctaSse(int port, String path, Map<String, dynamic> body) async {
  final client = HttpClient();
  try {
    final req = await client.postUrl(Uri.parse('http://127.0.0.1:$port$path'));
    req.headers.contentType = ContentType.json;
    final bytes = utf8.encode(jsonEncode(body));
    req.contentLength = bytes.length;
    req.add(bytes);
    final resp = await req.close();
    final events = <Map<String, dynamic>>[];
    await for (final line in resp.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.startsWith('data: ')) {
        try { events.add(jsonDecode(line.substring(6)) as Map<String, dynamic>); } catch (_) {}
      }
    }
    return events;
  } finally {
    client.close();
  }
}

void ctaHeader(String title) {
  print('\n══════════════════════════════════════════════');
  print('  $title');
  print('══════════════════════════════════════════════');
}

void ctaMenu(Map<String, int> ports) {
  print('\n╔══════════════════════════════════════════════╗');
  print('║   🌲 Evergreen Base — 文本模式               ║');
  print('╠══════════════════════════════════════════════╣');
  print('║  [1] 工作台   [2] 市场   [3] AI 对话        ║');
  print('║  [4] 我的插件  [5] 设置  [0] 退出            ║');
  print('╚══════════════════════════════════════════════╝');
}
