/// 端到端验证脚本（一次性，非测试套件常驻）。
///
/// 用系统 node 起一个最小 HTTP server（回 PORT: 行 + /health 200），
/// 通过真实 [ProcessSidecarRuntime] + [NodeSidecarController] 启动它，
/// 验证「进程启动 → 端口解析 → 健康探测」整链打通。
///
/// 运行：dart run lib/core/module/example/sidecar_node_e2e.dart
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../runtime.dart';
import '../sidecar/sidecar_controller.dart';
import '../sidecar/process_sidecar_runtime.dart';
import '../sidecar/node_sidecar.dart';

const _nodeScript = '''
const http = require('http');
const server = http.createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200, {'Content-Type': 'application/json'});
    res.end(JSON.stringify({status: 'ok'}));
    return;
  }
  res.writeHead(404); res.end();
});
server.listen(0, () => {
  const p = server.address().port;
  process.stdout.write('PORT:' + p + '\\n');
});
''';

Future<void> main() async {
  // 把脚本写到临时文件，供 node 执行。
  final tmp = File('${Directory.systemTemp.path}/_e2e_sidecar.js');
  await tmp.writeAsString(_nodeScript);

  final descriptor = RuntimeDescriptor(
    kind: RuntimeKind.node,
    entry: tmp.path,
  );

  final runtime = ProcessSidecarRuntime();
  final controller = NodeSidecarController(
    descriptor,
    runtime,
    portReadTimeout: const Duration(seconds: 8),
  );

  print('[E2E] 启动 node sidecar...');
  try {
    await controller.start().timeout(const Duration(seconds: 40));
  } on TimeoutException {
    print('[E2E] FAIL: start() 超时未返回');
    controller.kill();
    await tmp.delete();
    exit(1);
  }

  stderr.writeln('[E2E] start 返回: healthy=${controller.isHealthy}, port=${controller.port}');

  if (!controller.isHealthy || controller.port == null) {
    print('[E2E] FAIL: sidecar 未健康启动 (healthy=${controller.isHealthy}, '
        'port=${controller.port})');
    await controller.stop();
    await tmp.delete();
    exit(1);
  }

  print('[E2E] OK: sidecar 监听 port=${controller.port}, healthy=${controller.isHealthy}');

  // 真实打一次 /health 确认。
  final client = HttpClient();
  final req = await client.get('localhost', controller.port!, '/health');
  final resp = await req.close();
  final body = await resp.transform(utf8.decoder).join();
  print('[E2E] GET /health → ${resp.statusCode} $body');
  client.close();

  final meta = sidecarMetaOf(controller);
  print('[E2E] meta=${meta.toJson()}');

  await controller.stop();
  controller.kill(); // 兜底强杀，避免子进程残留阻止 dart 退出
  await tmp.delete();
  print('[E2E] 已优雅停止，验证完成。');
  exit(0);
}
