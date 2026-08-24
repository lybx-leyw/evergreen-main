/// SubprocessRunner.startLong 常驻进程双向流端到端测试。
///
/// 常驻终端（HTML 插件 `platform.process.start/write/read`）的地基是
/// [SubprocessRunner.startLong] 返回的原生 [Process]：可启动常驻进程、
/// 向 stdin 写数据、逐行读取 stdout/stderr、优雅 kill。本测试用真实
/// Python 交互进程端到端验证这套能力，确保常驻终端核心链路可用。
///
/// 测试环境需可访问 `python`（Windows 桌面默认 `resolvePythonExe` 命中
/// 系统 Python 或嵌入式 `.greenix/python/python.exe`）。若环境无 Python，
/// 相关用例跳过（`skip`），避免在 CI 无 Python 时误报失败。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_base/core/plugin/plugin_runner.dart';

/// 一个交互式 echo 常驻进程脚本：逐行读取 stdin，回显 `echo: <line>`；
/// 读到 `exit` 时退出。用于验证常驻进程的 stdin 写入 + stdout 逐行读取。
const String _echoScript = r'''
import sys
sys.stdout.flush()
for line in sys.stdin:
    s = line.rstrip('\n')
    if s == 'exit':
        break
    print('echo: ' + s, flush=True)
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String? pythonExe;

  setUpAll(() async {
    // 探测 python：优先 python，其次 py -3。
    pythonExe = await _findPython();
  });

  group('SubprocessRunner.startLong（常驻进程双向流）', () {
    test('startLong 启动 Python 常驻进程 + stdin 写 + stdout 逐行读 + kill',
        () async {
      if (pythonExe == null) {
        markTestSkipped('环境无 Python，跳过常驻进程端到端测试');
        return;
      }

      // 写一个临时 echo 脚本。
      final dir = Directory.systemTemp.createTempSync('evg_long_proc_');
      addTearDown(() {
        try {
          dir.deleteSync(recursive: true);
        } catch (_) {}
      });
      final script = File('${dir.path}/echo.py');
      script.writeAsStringSync(_echoScript);

      final runner = SubprocessRunner(pythonExe);
      // runtime='python' → 用 pythonExe 执行 script。
      final proc = await runner.startLong(
        script.path,
        [],
        workingDirectory: dir.path,
        runtime: 'python',
      );

      // 逐行读取 stdout。
      final lines = <String>[];
      final sub = proc.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(lines.add);

      // 写两行 stdin。
      proc.stdin.write('hello\n');
      proc.stdin.write('world\n');

      // 等待两行回显。
      await _waitFor(() => lines.length >= 2,
          timeout: const Duration(seconds: 5));
      expect(lines, contains('echo: hello'));
      expect(lines, contains('echo: world'));

      // 写 exit → 进程退出。
      proc.stdin.write('exit\n');
      await proc.stdin.close();

      final code = await proc.exitCode.timeout(const Duration(seconds: 5));
      expect(code, 0);

      await sub.cancel();
    });

    test('startLong 进程可被 kill（SIGTERM 优雅终止）', () async {
      if (pythonExe == null) {
        markTestSkipped('环境无 Python，跳过常驻进程端到端测试');
        return;
      }

      // 一个不主动退出的常驻进程（无限等待 stdin）。
      final dir = Directory.systemTemp.createTempSync('evg_long_proc_');
      addTearDown(() {
        try {
          dir.deleteSync(recursive: true);
        } catch (_) {}
      });
      final script = File('${dir.path}/idle.py');
      script.writeAsStringSync(
          'import sys\nsys.stdin.read()\n'); // 阻塞直到 stdin 关闭

      final runner = SubprocessRunner(pythonExe);
      final proc = await runner.startLong(
        script.path,
        [],
        workingDirectory: dir.path,
        runtime: 'python',
      );

      // 等进程就绪后 kill。
      await Future<void>.delayed(const Duration(milliseconds: 300));
      proc.kill(ProcessSignal.sigterm);

      final code = await proc.exitCode.timeout(const Duration(seconds: 5));
      expect(code, isNotNull);
    });

    test('startLong 非 python（native）直接执行', () async {
      if (pythonExe == null) {
        markTestSkipped('环境无 Python，跳过常驻进程端到端测试');
        return;
      }

      // runtime 缺省且 entry 非 .py → 直接执行 entry（此处用 python 作 entry）。
      final runner = SubprocessRunner(null);
      final proc = await runner.startLong(
        pythonExe!,
        ['-c', 'print("native-ok", flush=True)'],
      );

      final out = await proc.stdout
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 5));
      final code = await proc.exitCode.timeout(const Duration(seconds: 5));

      expect(out, contains('native-ok'));
      expect(code, 0);
    });
  });
}

/// 探测可用的 python 解释器路径（仅单 token 可执行名，避免 `py -3` 带空格）。
Future<String?> _findPython() async {
  for (final candidate in ['python', 'python3']) {
    try {
      final r = await Process.run(candidate, ['--version'])
          .timeout(const Duration(seconds: 5));
      if (r.exitCode == 0) return candidate;
    } catch (_) {}
  }
  return null;
}

/// 轮询等待条件成立。
Future<void> _waitFor(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  throw TimeoutException('等待条件超时');
}
