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

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'package:evergreen_base/core/utils/python_env.dart';

/// Greenix 脚本目录提供者（无 Flutter 依赖的注入点，`PYTHONPATH` 注入源）。
typedef GreenixScriptsDirProvider = String Function();

GreenixScriptsDirProvider _greenixScriptsDirProvider =
    _defaultGreenixScriptsDir;

/// 未绑定时按历史行为：`cwd/.greenix/scripts`（开发模式 cwd = 项目根）。
String _defaultGreenixScriptsDir() =>
    p.join(Directory.current.path, '.greenix', 'scripts');

/// 绑定 Greenix 脚本目录——平台 Python 库 `evg_lib` 落盘处。
///
/// app 启动（`app_bootstrap` 的 `initGreenixPaths()` 之后）绑定为
/// `greenix_path.greenixScriptsDir`（`.greenix/scripts/`），使启动 Python
/// 子进程时注入 `PYTHONPATH` 后 `import evg_lib` 可用而不需拷贝。
/// 子包测试未绑定时保持 [Directory.current] 历史行为。
void bindGreenixScriptsDir(GreenixScriptsDirProvider provider) {
  _greenixScriptsDirProvider = provider;
}

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
    Map<String, String>? environment,
    Duration? timeout,
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

  /// 合并环境变量并注入 `PYTHONPATH`（`.greenix/scripts/`），使 `import evg_lib`
  /// 可用而不需拷贝。仅对 Python 入口（[runtime]=='python' 或 `.py`）注入，
  /// 避免影响原生 `.exe` 子进程的环境契约。
  ///
  /// [environment] 为 null 时基于父进程环境（[Platform.environment]）合并；
  /// 非 null 时基于传入环境合并（保留调用方注入的 PROJECT_ROOT 等变量）。
  Map<String, String>? _withPythonPath(
      String entry, Map<String, String>? environment,
      [String? runtime]) {
    if (!_isPython(entry, runtime)) return environment;
    final scriptsDir = _greenixScriptsDirProvider();
    if (scriptsDir.isEmpty) return environment;
    final env = Map<String, String>.from(environment ?? Platform.environment);
    final sep = Platform.isWindows ? ';' : ':';
    final existing = env['PYTHONPATH'];
    env['PYTHONPATH'] = (existing == null || existing.isEmpty)
        ? scriptsDir
        : '$scriptsDir$sep$existing';
    return env;
  }

  @override
  Future<RunResult> runOnce(
    String entry,
    List<String> args, {
    Map<String, dynamic>? stdinJson,
    String? workingDirectory,
    String? runtime,
    Map<String, String>? environment,
    Duration? timeout,
  }) async {
    final exec = _buildExec(entry, args, runtime);
    final process = await Process.start(
      exec.first,
      exec.skip(1).toList(),
      workingDirectory: workingDirectory,
      environment: _withPythonPath(entry, environment, runtime),
    );
    if (stdinJson != null) {
      process.stdin.write(jsonEncode(stdinJson));
      await process.stdin.close();
    }
    final outF = process.stdout.transform(utf8.decoder).join();
    final errF = process.stderr.transform(utf8.decoder).join();

    Future<RunResult> collect() async {
      final out = await outF;
      final err = await errF;
      final code = await process.exitCode;
      return RunResult(out, err, code);
    }

    if (timeout == null) return collect();

    // 超时必须 kill 子进程，避免 `Future.timeout` 丢下孤儿进程。
    return collect().timeout(timeout, onTimeout: () {
      try {
        process.kill(ProcessSignal.sigterm);
      } catch (_) {}
      try {
        process.kill(ProcessSignal.sigkill);
      } catch (_) {}
      throw TimeoutException(
        'runOnce 超时（>${timeout.inSeconds}s），已终止子进程: $entry',
        timeout,
      );
    });
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
      environment: _withPythonPath(entry, null, runtime),
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
  final pythonExe = await PythonInterpreter.instance.resolveExePath();
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
    Map<String, String>? environment,
    Duration? timeout,
  }) async {
    final invoke = () async {
      final resp = await _ch.invokeMethod<Map<dynamic, dynamic>>('runScript', {
        'entry': entry,
        'args': args,
        'stdinJson': stdinJson,
        'workingDirectory': workingDirectory,
        'runtime': runtime,
        // 安卓进程内解释器：environment 由原生侧合并（未实现则忽略，
        // 凭据经 .greenix/config.json 镜像（Tier 1）兜底读取）。
        'environment': environment,
        // 平台 Python 库目录（`.greenix/scripts/`）：原生侧据此把 evg_lib
        // 落盘目录加入 sys.path，使 `import evg_lib` 在安卓进程内可用。
        'pythonPath': _greenixScriptsDirProvider(),
      });
      final out = (resp?['stdout'] as String?) ?? '';
      final err = (resp?['stderr'] as String?) ?? '';
      final code = (resp?['exitCode'] as int?) ?? -1;
      return RunResult(out, err, code);
    }();

    if (timeout == null) return invoke;

    // 安卓进程内解释器无独立子进程可 kill——超时经 `Future.timeout` 放弃等待
    // 并抛 [TimeoutException]（原生侧由自身超时/取消策略兜底）。
    return invoke.timeout(timeout, onTimeout: () {
      throw TimeoutException(
        'runOnce 超时（>${timeout.inSeconds}s）: $entry',
        timeout,
      );
    });
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
    final proc = ChaquopyLongProcess(entry);
    await _ch.invokeMethod<void>('startLongServer', {
      'entry': entry,
      'args': args,
      'workingDirectory': workingDirectory,
      'preferredPort': preferredPort,
      'runtime': runtime,
      'pythonPath': _greenixScriptsDirProvider(),
    });
    return proc;
  }
}

/// 安卓长驻数据源在 app 进程内（Chaquopy 后台线程）起的 HTTP server，
/// 包装成 [Process] 接口，使 [DataSourceLoader] 的 stdout 端口探测 / kill
/// 逻辑与桌面完全一致（方案 A，规划 §5.3）。
///
/// stdout/stderr 来自原生 [EventChannel]('evergreen/python_stream') 的行事件。
/// ⚠️ 该 EventChannel 为单监听：所有常驻进程共享一个 Dart 侧订阅
/// （[_ChaquopyStreamHub]），事件按 `entry`（入口脚本路径）路由到对应实例，
/// 修复多实例时「后订阅顶掉先订阅者、输出/退出事件静默丢失（exitCode future
/// 永不完成、会话泄漏）」的问题。旧 Kotlin 侧（事件不带 `entry`）向前兼容：
/// 单实例时无条件投递，多实例时丢弃无路由事件。
/// [DataSourceLoader] 仅用到 [stdout] / [stderr] / [exitCode] / [kill]，其余
/// 接口为占位（安卓进程内 server 无真实 pid / stdin）。
class ChaquopyLongProcess implements Process {
  static const MethodChannel _ctrlCh = MethodChannel('evergreen/python');

  final StreamController<List<int>> _stdoutCtl = StreamController<List<int>>();
  final StreamController<List<int>> _stderrCtl = StreamController<List<int>>();
  final Completer<int> _exitCtl = Completer<int>();
  bool _killed = false;

  /// 入口脚本路径：既是 stdin 写入（`writeStdin`）的透传键，也是共享
  /// 分发器 [_ChaquopyStreamHub] 的事件路由键。
  final String entry;

  /// stdin 写入 sink：把命令经 MethodChannel('evergreen/python') 的
  /// `writeStdin` 转发到 Kotlin 侧，注入到 Python 常驻进程的 stdin 队列。
  /// 惰性创建，避免无 stdin 需求的场景浪费。
  IOSink? _stdin;

  ChaquopyLongProcess(this.entry) {
    _ChaquopyStreamHub().register(this);
  }

  /// 完成退出：注销分发器注册、完成 exitCode future、关闭流。幂等
  /// （Kotlin `exit` 事件 / [kill] / 流 onError/onDone 均可触发），
  /// 先到者胜——真实退出码不被 kill 的 0 覆盖。
  void _completeExit(int code) {
    if (_exitCtl.isCompleted) return;
    _ChaquopyStreamHub().unregister(this);
    _exitCtl.complete(code);
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
  IOSink get stdin => _stdin ??= _ChaquopyStdinSink(_ctrlCh, entry);

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    if (_killed) return false;
    _killed = true;
    _ctrlCh.invokeMethod<void>('stopLongServer');
    _completeExit(0);
    return true;
  }

  /// 仅测试用：重置全局流分发器（[_ChaquopyStreamHub]）的订阅与注册表。
  ///
  /// flutter_test 中每个测试会重新 `setMockStreamHandler`，而 hub 是跨测试
  /// 存活的全局单例——若残留旧订阅，后续测试注册的新 mock handler 收不到
  /// `onListen`，事件全部滞留缓存而丢失（stdout/stderr 为空、exitCode 永不
  /// 完成）。测试 setUp 应调用本方法后再安装 mock。
  @visibleForTesting
  static void resetStreamHubForTesting() {
    _ChaquopyStreamHub().resetForTesting();
  }
}

/// 安卓长驻进程 EventChannel 共享分发器（全局单监听）。
///
/// 修复：EventChannel 同一时刻只允许一个监听者——若每个 [ChaquopyLongProcess]
/// 各自 subscribe，第二个实例会把第一个实例的 sink 顶掉（Kotlin `onListen`
/// 覆盖 `streamSink`），前者输出/退出事件全部丢失、`exitCode` 永不完成。
/// 本分发器全局唯一订阅一次，按事件的 `entry` 字段路由到对应实例；
/// `entry` 缺失（旧 Kotlin）时：注册表仅一个实例 → 无条件投递（向后兼容），
/// 多实例 → 丢弃（旧端本就不支持多实例）。
class _ChaquopyStreamHub {
  static final _ChaquopyStreamHub _instance = _ChaquopyStreamHub._();
  factory _ChaquopyStreamHub() => _instance;
  _ChaquopyStreamHub._();

  static const EventChannel _streamCh = EventChannel('evergreen/python_stream');

  final Map<String, ChaquopyLongProcess> _registry = {};
  StreamSubscription? _sub;

  void register(ChaquopyLongProcess proc) {
    _ensureListening();
    _registry[proc.entry] = proc;
  }

  void unregister(ChaquopyLongProcess proc) {
    _registry.remove(proc.entry);
    // 注册表清空时取消全局订阅，避免空闲监听泄漏。
    if (_registry.isEmpty && _sub != null) {
      _sub?.cancel();
      _sub = null;
    }
  }

  /// 仅测试用：取消全局订阅并清空注册表（见 [ChaquopyLongProcess.resetStreamHubForTesting]）。
  @visibleForTesting
  void resetForTesting() {
    _sub?.cancel();
    _sub = null;
    _registry.clear();
  }

  void _ensureListening() {
    if (_sub != null) return;
    _sub = _streamCh.receiveBroadcastStream().listen(
      _dispatch,
      onError: (_) {
        for (final proc in List.of(_registry.values)) {
          proc._completeExit(1);
        }
      },
      onDone: () {
        for (final proc in List.of(_registry.values)) {
          proc._completeExit(0);
        }
      },
    );
  }

  void _dispatch(dynamic event) {
    final map = event as Map<dynamic, dynamic>;
    final entry = map['entry'] as String?;
    final type = map['type'] as String?;
    final line = (map['line'] as String?) ?? '';
    final target = (entry != null && entry.isNotEmpty)
        ? _registry[entry]
        : (_registry.length == 1 ? _registry.values.first : null);
    if (target == null) return;
    if (type == 'stdout') {
      if (!target._stdoutCtl.isClosed) {
        target._stdoutCtl.add(utf8.encode('$line\n'));
      }
    } else if (type == 'stderr') {
      if (!target._stderrCtl.isClosed) {
        target._stderrCtl.add(utf8.encode('$line\n'));
      }
    } else if (type == 'exit') {
      target._completeExit((map['code'] as int?) ?? 0);
    }
  }
}

/// 安卓常驻进程的 stdin 写入 sink（stdin 双向流规划 §4.2）。
///
/// 把 [write] / [writeln] 等调用经 MethodChannel('evergreen/python') 的
/// `writeStdin` 转发到 Kotlin 侧，再由其注入到 Python 常驻进程的 stdin 队列。
/// 其余 `IOSink` 接口方法按需实现（多为 no-op，仅 write 系列有实际语义）。
class _ChaquopyStdinSink implements IOSink {
  final MethodChannel _ch;
  final String entry;

  _ChaquopyStdinSink(this._ch, this.entry);

  @override
  Encoding encoding = utf8;

  @override
  void add(List<int> data) {
    write(utf8.decode(data));
  }

  @override
  void write(Object? object) {
    final s = object?.toString() ?? '';
    if (s.isEmpty) return;
    // fire-and-forget：命令发出即可，Python 侧异步读。
    _ch.invokeMethod<void>('writeStdin', {'entry': entry, 'data': s});
  }

  @override
  void writeAll(Iterable<dynamic> objects, [String separator = ""]) {
    write(objects.join(separator));
  }

  @override
  void writeln([Object? object = ""]) {
    write('${object ?? ''}\n');
  }

  @override
  void writeCharCode(int charCode) {
    write(String.fromCharCode(charCode));
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<dynamic> addStream(Stream<List<int>> stream) async {}

  @override
  Future<dynamic> flush() async {}

  @override
  Future<dynamic> close() async {}

  @override
  Future<dynamic> get done async {}
}
