/// 插件执行抽象层 —— 屏蔽「.exe 子进程」与「进程内 Python」的差异。
///
/// 桌面端由 [SubprocessRunner] 实现（仍是 `Process.start`，但按 [runtime] 或 `.py`
/// 扩展名自动拼出 `python <entry>` 或 `<entry>`）；安卓端（P1）由 `ChaquopyRunner`
/// 实现，在 app 进程内执行同一份 `.py`。
///
/// 详见 `统一py插件-安卓适配规划.md` §3。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:evergreen_base/core/utils/python_env.dart';

/// 一次性执行的结果。
class RunResult {
  final String stdout;
  final String stderr;
  final int exitCode;
  const RunResult(this.stdout, this.stderr, this.exitCode);
}

/// 插件执行抽象。
///
/// - [runOnce]：一次性运行（stdio 或短任务），收集后返回 [RunResult]。
/// - [startLong]：启动长驻进程，返回原生 [Process]（桌面）；安卓 P1 另作适配。
abstract class PluginRunner {
  Future<RunResult> runOnce(
    String entry,
    List<String> args, {
    Map<String, dynamic>? stdinJson,
    String? workingDirectory,
    String? runtime,
  });

  Future<Process> startLong(
    String entry,
    List<String> args, {
    String? workingDirectory,
    int preferredPort = 0,
    String? runtime,
  });
}

/// 桌面实现：仍是 `Process.start`，但按 [runtime] 或 `.py` 扩展名决定首参是
/// python 解释器还是 entry 本身。
class SubprocessRunner implements PluginRunner {
  final String? pythonExe;

  const SubprocessRunner(this.pythonExe);

  bool _isPython(String entry, [String? runtime]) =>
      runtime == 'python' || entry.endsWith('.py');

  List<String> _buildExec(String entry, List<String> args, [String? runtime]) {
    if (_isPython(entry, runtime)) {
      if (pythonExe == null) {
        throw StateError('Python 解释器不可用（resolvePythonExe 返回 null），'
            '无法运行 $entry。请在设置中配置 Python 路径。');
      }
      return [pythonExe!, entry, ...args];
    }
    return [entry, ...args];
  }

  @override
  Future<RunResult> runOnce(
    String entry,
    List<String> args, {
    Map<String, dynamic>? stdinJson,
    String? workingDirectory,
    String? runtime,
  }) async {
    final exec = _buildExec(entry, args, runtime);
    final process = await Process.start(
      exec.first,
      exec.skip(1).toList(),
      workingDirectory: workingDirectory,
    );
    if (stdinJson != null) {
      process.stdin.write(jsonEncode(stdinJson));
      await process.stdin.close();
    }
    final out = await process.stdout.transform(utf8.decoder).join();
    final err = await process.stderr.transform(utf8.decoder).join();
    final code = await process.exitCode;
    return RunResult(out, err, code);
  }

  @override
  Future<Process> startLong(
    String entry,
    List<String> args, {
    String? workingDirectory,
    int preferredPort = 0,
    String? runtime,
  }) async {
    final exec = _buildExec(entry, args, runtime);
    return Process.start(
      exec.first,
      exec.skip(1).toList(),
      workingDirectory: workingDirectory,
    );
  }
}

// ═══════ 共享实例（桌面） ═══════

Future<PluginRunner>? _pendingRunner;

/// 获取进程内/跨进程共享的 [PluginRunner]。
///
/// 桌面返回 [SubprocessRunner]（python 路径经 [resolvePythonExe] 探测）；
/// 安卓（P1）在此切换为 `ChaquopyRunner`，调用方代码无需改动。
Future<PluginRunner> get sharedPluginRunner {
  _pendingRunner ??= _createRunner();
  return _pendingRunner!;
}

Future<PluginRunner> _createRunner() async {
  if (Platform.isAndroid) {
    // P1: 安卓走进程内 Chaquopy（MethodChannel 原生桥见 P1b）。
    return const ChaquopyRunner();
  }
  final pythonExe = await resolvePythonExe();
  return SubprocessRunner(pythonExe);
}

/// 安卓实现：经 `MethodChannel('evergreen/python')` 在 app 进程内执行 `.py`。
///
/// 原生侧（Kotlin，`android/app/.../MainActivity.kt`）需注册同名 channel 并实现
/// `runScript`，调用 Chaquopy（`Python.start` / `Python.runModule`）。该原生桥属于 P1b。
///
/// 详见 `统一py插件-安卓适配规划.md` §3.2。本类在 Windows 上不会被实例化
/// （[Platform.isAndroid] 为 false），因此对桌面行为零影响。
class ChaquopyRunner implements PluginRunner {
  static const MethodChannel _ch = MethodChannel('evergreen/python');

  const ChaquopyRunner();

  @override
  Future<RunResult> runOnce(
    String entry,
    List<String> args, {
    Map<String, dynamic>? stdinJson,
    String? workingDirectory,
    String? runtime,
  }) async {
    final resp = await _ch.invokeMethod<Map<dynamic, dynamic>>('runScript', {
      'entry': entry,
      'args': args,
      'stdinJson': stdinJson,
      'workingDirectory': workingDirectory,
      'runtime': runtime,
    });
    final out = (resp?['stdout'] as String?) ?? '';
    final err = (resp?['stderr'] as String?) ?? '';
    final code = (resp?['exitCode'] as int?) ?? -1;
    return RunResult(out, err, code);
  }

  @override
  Future<Process> startLong(
    String entry,
    List<String> args, {
    String? workingDirectory,
    int preferredPort = 0,
    String? runtime,
  }) async {
    // 方案 A（规划 §5.3）：安卓无 exec，长驻 HTTP 数据源走 Chaquopy 后台线程
    // server，stdout 经 EventChannel 流式回传，原生侧 [ChaquopyLongProcess]
    // 把其包装成 [Process]，使 [DataSourceLoader] 的 PORT:/health/{port} 协议
    // 与桌面完全一致。
    final proc = ChaquopyLongProcess();
    await _ch.invokeMethod<void>('startLongServer', {
      'entry': entry,
      'args': args,
      'workingDirectory': workingDirectory,
      'preferredPort': preferredPort,
      'runtime': runtime,
    });
    return proc;
  }
}

/// 安卓长驻数据源在 app 进程内（Chaquopy 后台线程）起的 HTTP server，
/// 包装成 [Process] 接口，使 [DataSourceLoader] 的 stdout 端口探测 / kill
/// 逻辑与桌面完全一致（方案 A，规划 §5.3）。
///
/// stdout/stderr 来自原生 [EventChannel]('evergreen/python_stream') 的行事件；
/// [DataSourceLoader] 仅用到 [stdout] / [stderr] / [exitCode] / [kill]，其余
/// 接口为占位（安卓进程内 server 无真实 pid / stdin）。
class ChaquopyLongProcess implements Process {
  static const EventChannel _streamCh = EventChannel('evergreen/python_stream');
  static const MethodChannel _ctrlCh = MethodChannel('evergreen/python');

  final StreamController<List<int>> _stdoutCtl = StreamController<List<int>>();
  final StreamController<List<int>> _stderrCtl = StreamController<List<int>>();
  final Completer<int> _exitCtl = Completer<int>();
  bool _killed = false;
  StreamSubscription? _streamSub;

  ChaquopyLongProcess() {
    _streamSub = _streamCh.receiveBroadcastStream().listen(
      (event) {
        final map = event as Map<dynamic, dynamic>;
        final type = map['type'] as String?;
        final line = (map['line'] as String?) ?? '';
        if (type == 'stdout') {
          if (!_stdoutCtl.isClosed) _stdoutCtl.add(utf8.encode('$line\n'));
        } else if (type == 'stderr') {
          if (!_stderrCtl.isClosed) _stderrCtl.add(utf8.encode('$line\n'));
        } else if (type == 'exit') {
          final code = (map['code'] as int?) ?? 0;
          _completeExit(code);
        }
      },
      onError: (_) => _completeExit(1),
      onDone: () => _completeExit(0),
    );
  }

  void _completeExit(int code) {
    if (!_exitCtl.isCompleted) _exitCtl.complete(code);
    // 先取消订阅，防止后续事件再写已关闭的 controller
    _streamSub?.cancel();
    _streamSub = null;
    if (!_stdoutCtl.isClosed) _stdoutCtl.close();
    if (!_stderrCtl.isClosed) _stderrCtl.close();
  }

  @override
  Stream<List<int>> get stdout => _stdoutCtl.stream;

  @override
  Stream<List<int>> get stderr => _stderrCtl.stream;

  @override
  Future<int> get exitCode => _exitCtl.future;

  @override
  int get pid => -1;

  @override
  IOSink get stdin =>
      throw UnsupportedError('安卓长驻进程不支持 stdin 写入');

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    if (_killed) return false;
    _killed = true;
    _ctrlCh.invokeMethod<void>('stopLongServer');
    _completeExit(0);
    return true;
  }
}
