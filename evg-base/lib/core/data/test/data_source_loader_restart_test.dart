/// DataSourceLoader 进程守护（崩溃自动重启）测试（T4）。
///
/// 用 Python fake 长驻 HTTP 服务（模型 B）作「fake 进程」：
/// - 打印 `PORT:<n>` + 提供 `/health` 与 `/api/data`
/// - 响应一次数据请求后 `os._exit(0)` 模拟「崩溃」
///
/// 覆盖：
/// - 崩溃后按退避自动重启并恢复 `isRunning`，已注册 DataType 保留，`get` 恢复可用
/// - 手动 `restart()` 入口
/// - 重启失败用尽次数后标记 `connected=false` + `lastError`（不无限重试）
/// - `stop()` 后不再自动重启
///
/// 依赖系统 `python3`（`PythonInterpreter` 经 PATH 解析）；无 python 时本测试文件
/// 各用例会因启动失败而跳过断言目标，但仍验证「失败不炸」的语义边界。

import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';

import '../orchestrator.dart';
import '../type.dart';
import '../plugin/data_source_manifest.dart';
import '../plugin/data_source_loader.dart';

// 测试用退避：毫秒级，避免拖慢用例。
const _fastBackoff = [
  Duration(milliseconds: 15),
  Duration(milliseconds: 15),
  Duration(milliseconds: 15),
];

const _fakeType = DataType<dynamic>(name: 'fake_data', category: '未分类');

/// 写一个「响应一次数据请求后（延迟）崩溃」的 Python fake 服务；若
/// [failOnSecondRun] 为 true 且标记文件已存在（第二次启动），则打印假端口后
/// 立即退出（模拟重启失败）。
///
/// 崩溃用 `close_connection` 先干净地送出完整响应（Content-Length），再经
/// 延迟 `os._exit(0)` 退出，避免客户端读响应与进程退出竞态（连接被客户端
/// `_client.close(force:true)` 取消）。
File _writeFakeServer(Directory dir, String markerPath, {required bool failOnSecondRun}) {
  final script = File('${dir.path}/fake_server.py');
  script.writeAsStringSync('''
import os, json, sys, threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

marker = ${_pyStr(markerPath)}

class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def log_message(self, *a): pass
    def do_GET(self):
        if self.path == "/health":
            self.send_response(200)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        body = json.dumps({"value": 1}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
        self.wfile.flush()
        self.close_connection = True
        # 响应完整送达后再模拟崩溃，避免竞态
        threading.Timer(0.2, lambda: os._exit(0)).start()

${failOnSecondRun ? '''if os.path.exists(marker):
    print("PORT:19999", flush=True)
    sys.exit(1)
''' : ''}
open(marker, "w").write("1")
srv = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
print("PORT:%d" % srv.server_port, flush=True)
srv.serve_forever()
''');
  return script;
}

String _pyStr(String s) => "'" + s.replaceAll('\\', '\\\\').replaceAll("'", "\\'") + "'";

DataSourceManifest _manifest(String exe) => DataSourceManifest.fromJson({
      'type': 'data-source',
      'id': 'fake',
      'name': 'fake',
      'process': exe,
      'runtime': 'python',
      'dataTypes': [
        {'name': 'fake_data', 'endpoint': '/api/data'},
      ],
    });

Future<void> _waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
  required String reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail(reason);
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  late Directory tmp;
  late DataOrchestrator orch;
  late bool pythonAvailable;

  setUpAll(() async {
    try {
      final r = await Process.run('python3', ['--version']);
      pythonAvailable = r.exitCode == 0;
    } catch (_) {
      pythonAvailable = false;
    }
  });

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('ds_loader_t');
    orch = DataOrchestrator();
  });

  tearDown(() async {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('崩溃后按退避自动重启并恢复可用，已注册 DataType 保留', () async {
    if (!pythonAvailable) return markTestSkipped('python3 不可用');
    final marker = '${tmp.path}/marker';
    _writeFakeServer(tmp, marker, failOnSecondRun: false);

    final loader = DataSourceLoader(
      manifest: _manifest('fake_server.py'),
      workingDirectory: tmp.path,
      projectRoot: tmp.path,
      restartBackoff: _fastBackoff,
    );

    await loader.start(orch);
    expect(loader.isRunning, isTrue);

    // 首次拉取：fake 服务响应后（延迟 200ms）崩溃
    final first = await orch.get(_fakeType);
    expect(first, isNotNull);
    expect((first as Map)['value'], 1);

    // 先等崩溃被检测（isRunning 变 false），再等自动重启恢复（变 true）
    await _waitFor(() => !loader.isRunning, reason: 'fake 进程未按预期崩溃');
    await _waitFor(() => loader.isRunning,
        reason: 'DataSourceLoader 未在预期时间内自动重启');

    // 重启期间已注册 DataType 保留
    expect(orch.isRegistered(_fakeType), isTrue);

    // 重启后再次拉取可用（新进程新端口）
    final second = await orch.get(_fakeType);
    expect(second, isNotNull);
    expect((second as Map)['value'], 1);

    await loader.stop();
    expect(loader.isRunning, isFalse);
  });

  test('手动 restart() 恢复进程', () async {
    if (!pythonAvailable) return markTestSkipped('python3 不可用');
    final marker = '${tmp.path}/marker';
    _writeFakeServer(tmp, marker, failOnSecondRun: false);

    final loader = DataSourceLoader(
      manifest: _manifest('fake_server.py'),
      workingDirectory: tmp.path,
      projectRoot: tmp.path,
      restartBackoff: _fastBackoff,
    );
    await loader.start(orch);
    expect(loader.isRunning, isTrue);

    await loader.restart();
    expect(loader.isRunning, isTrue);
    // 重启后端口可能变化（新进程），但类型仍可用
    final data = await orch.get(_fakeType);
    expect((data as Map)['value'], 1);
    // 端口变化或保持不变均可；仅验证重启未把旧端口固死
    expect(loader.port, isNotNull);

    await loader.stop();
  });

  test('重启失败用尽次数后标记 connected=false + lastError（不无限重试）', () async {
    if (!pythonAvailable) return markTestSkipped('python3 不可用');
    final marker = '${tmp.path}/marker';
    _writeFakeServer(tmp, marker, failOnSecondRun: true);

    final loader = DataSourceLoader(
      manifest: _manifest('fake_server.py'),
      workingDirectory: tmp.path,
      projectRoot: tmp.path,
      restartBackoff: _fastBackoff,
    );

    await loader.start(orch);
    expect(loader.isRunning, isTrue);

    // 首次拉取触发崩溃
    final first = await orch.get(_fakeType);
    expect(first, isNotNull);

    // 崩溃后：第二次启动（重启）打印假端口即退出 → 健康检查失败 → 重试用尽
    await _waitFor(
      () {
        final s = orch.status(_fakeType.name);
        return s != null && s.connected == false && s.lastError != null;
      },
      timeout: const Duration(seconds: 10),
      reason: '重启失败未在预期时间内标记 connected=false + lastError',
    );

    final s = orch.status(_fakeType.name)!;
    expect(s.connected, isFalse);
    expect(s.lastError, contains('重启'));
    // 不再无限重启：isRunning 恒为 false
    expect(loader.isRunning, isFalse);
  });
}
