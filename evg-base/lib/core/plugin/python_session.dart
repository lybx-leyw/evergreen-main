/// 平台级「常驻 Python 会话」抽象——基于 stdio JSON Lines 双向协议。
///
/// 复用 [paper_reader.py] 的 stdin 命令 / stdout 事件先例（`scripts/paper_reader.py`
/// 的 `{"command":"extract"/"exit"}` → `{"type":"result"/"error"}` JSON Lines），
/// 把「长驻 python 进程 + 双向 stdio」抽象成统一 API，桌面 [SubprocessRunner]
/// 与安卓 [ChaquopyRunner]（经 [ChaquopyLongProcess.stdin]）同一抽象：
///
/// - [start]：经 [PluginRunner.startLong] 起 python 进程，逐行解析 stdout 事件
/// - [send]：写一条 JSON Lines 命令到子进程 stdin
/// - [onEvent]：stdout 逐行事件流（解析后的 Map，广播）
/// - [onStderr]：stderr 逐行文本流（供日志/诊断）
/// - [close]：阶梯终止——发退出命令 → 2s → SIGTERM → 2s → SIGKILL
///
/// 协议约定（与 paper_reader.py 对齐）：每行一个 JSON 对象；退出命令缺省
/// `{"command":"exit"}`（子进程据此优雅收尾）。非 JSON 的 stdout 行被静默忽略，
/// 不污染事件流。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:evergreen_base/core/plugin/plugin_runner.dart';

/// stdout JSON Lines 事件：每行一个 JSON 对象（`Map<String, dynamic>`）。
typedef PythonSessionEvent = Map<String, dynamic>;

class PythonSession {
  final PluginRunner runner;
  final String entry;
  final List<String> args;
  final String? workingDirectory;
  final String? runtime;

  /// 优雅退出命令（发到 stdin 的 JSON 行）。缺省 `{"command":"exit"}`。
  final Map<String, dynamic> exitCommand;

  Process? _process;
  StreamController<PythonSessionEvent>? _events;
  StreamController<String>? _stderrCtl;
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;
  bool _closeStarted = false;

  PythonSession({
    required this.runner,
    required this.entry,
    this.args = const [],
    this.workingDirectory,
    this.runtime,
    this.exitCommand = const {'command': 'exit'},
  });

  /// stdout 逐行 JSON Lines 事件流（广播）。
  Stream<PythonSessionEvent> get onEvent =>
      (_events ??= StreamController<PythonSessionEvent>.broadcast()).stream;

  /// stderr 逐行文本流（广播，供日志/诊断）。
  Stream<String> get onStderr =>
      (_stderrCtl ??= StreamController<String>.broadcast()).stream;

  bool get isStarted => _process != null;

  /// 子进程退出码（未启动时返回一个永不完成的 Future，供外部 await）。
  Future<int> get exitCode => _process?.exitCode ?? Completer<int>().future;

  /// 启动常驻 python 进程并开始解析 stdout JSON Lines。
  Future<void> start() async {
    if (_process != null) return;
    _process = await runner.startLong(
      entry,
      args,
      workingDirectory: workingDirectory,
      runtime: runtime,
    );

    _stdoutSub = _process!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onStdoutLine);
    _stderrSub = _process!.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      if (_stderrCtl != null && !_stderrCtl!.isClosed) _stderrCtl!.add(line);
    });

    // 进程自然退出：关闭事件流，避免消费者悬挂。
    _process!.exitCode.then((_) => _completeStreams());
  }

  void _onStdoutLine(String line) {
    final t = line.trim();
    if (t.isEmpty) return;
    try {
      final obj = jsonDecode(t);
      if (obj is Map<String, dynamic>) {
        if (_events != null && !_events!.isClosed) _events!.add(obj);
      }
    } catch (_) {
      // 非 JSON 行（如裸文本日志）静默忽略，不污染事件流。
    }
  }

  /// 发送一条 JSON Lines 命令到子进程 stdin。
  void send(Map<String, dynamic> command) {
    final proc = _process;
    if (proc == null) {
      throw StateError('PythonSession 未启动，请先调用 start()');
    }
    proc.stdin.writeln(jsonEncode(command));
  }

  /// 阶梯终止：发退出命令 → 2s → SIGTERM → 2s → SIGKILL。
  ///
  /// 幂等：重复调用只会执行一次阶梯终止。
  Future<void> close() async {
    if (_closeStarted) return;
    _closeStarted = true;
    final proc = _process;
    if (proc == null) return;

    // 1. 应用层退出命令（优雅退出，如 paper_reader.py 的 {"command":"exit"}）
    try {
      proc.stdin.writeln(jsonEncode(exitCommand));
      await proc.stdin.flush();
    } catch (_) {
      // 进程已死或 stdin 不可写：继续走信号终止兜底。
    }

    // 2. 短超时等待自然退出
    if (await _waitExit(proc, const Duration(seconds: 2))) {
      await _completeStreams();
      return;
    }

    // 3. SIGTERM
    _signal(proc, ProcessSignal.sigterm);
    if (await _waitExit(proc, const Duration(seconds: 2))) {
      await _completeStreams();
      return;
    }

    // 4. SIGKILL
    _signal(proc, ProcessSignal.sigkill);
    await _waitExit(proc, const Duration(seconds: 1));
    await _completeStreams();
  }

  Future<bool> _waitExit(Process proc, Duration timeout) async {
    try {
      await proc.exitCode.timeout(timeout);
      return true;
    } on TimeoutException {
      return false;
    } catch (_) {
      // exitCode 异常完成（进程已死 / 通道断开）视为已退出。
      return true;
    }
  }

  void _signal(Process proc, ProcessSignal signal) {
    try {
      proc.kill(signal);
    } catch (_) {
      // 已退出 / 安卓占位 kill 返回 false，均忽略。
    }
  }

  Future<void> _completeStreams() async {
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;
    if (_events != null && !_events!.isClosed) await _events!.close();
    if (_stderrCtl != null && !_stderrCtl!.isClosed) await _stderrCtl!.close();
  }
}
