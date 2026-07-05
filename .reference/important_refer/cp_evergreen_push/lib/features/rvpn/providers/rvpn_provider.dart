import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/config/app_config.dart';
import '../../../core/log.dart';

// ═══════════════════════════════════════════════════════════
// RvpnState — immutable state
// ═══════════════════════════════════════════════════════════

/// RVPN proxy state.
class RvpnState {
  final bool isRunning;
  final bool isChecking;
  final bool hasBinary;
  final bool hasCredentials;
  final String statusMessage;
  final String? binaryPath;
  final int? exitCode;

  /// Captured log lines from the zju-connect process (stdout + stderr).
  final List<String> logLines;

  /// Whether the last health check against 127.0.0.1:1080 succeeded.
  final bool healthOk;
  final bool healthChecking;

  const RvpnState({
    this.isRunning = false,
    this.isChecking = true,
    this.hasBinary = false,
    this.hasCredentials = false,
    this.statusMessage = '检查中...',
    this.binaryPath,
    this.exitCode,
    this.logLines = const [],
    this.healthOk = false,
    this.healthChecking = false,
  });

  RvpnState copyWith({
    bool? isRunning,
    bool? isChecking,
    bool? hasBinary,
    bool? hasCredentials,
    String? statusMessage,
    String? binaryPath,
    int? exitCode,
    List<String>? logLines,
    bool? healthOk,
    bool? healthChecking,
  }) {
    return RvpnState(
      isRunning: isRunning ?? this.isRunning,
      isChecking: isChecking ?? this.isChecking,
      hasBinary: hasBinary ?? this.hasBinary,
      hasCredentials: hasCredentials ?? this.hasCredentials,
      statusMessage: statusMessage ?? this.statusMessage,
      binaryPath: binaryPath ?? this.binaryPath,
      exitCode: exitCode ?? this.exitCode,
      logLines: logLines ?? this.logLines,
      healthOk: healthOk ?? this.healthOk,
      healthChecking: healthChecking ?? this.healthChecking,
    );
  }
}

// ═══════════════════════════════════════════════════════════
// RvpnNotifier — lifecycle manager
// ═══════════════════════════════════════════════════════════

class RvpnNotifier extends StateNotifier<RvpnState> {
  Process? _process;
  Timer? _monitorTimer;
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;

  /// Keep at most this many log lines in state.
  static const int _maxLogLines = 200;

  RvpnNotifier() : super(const RvpnState()) {
    _init();
  }

  Future<void> _init() async {
    checkBinary();
    _checkCredentials();
  }

  // ── Credentials ──────────────────────────────────────────

  void _checkCredentials() {
    final hasCreds = AppConfig.hasZjuCredentials;
    if (hasCreds != state.hasCredentials) {
      state = state.copyWith(hasCredentials: hasCreds);
    }
  }

  /// Refresh credential status from [AppConfig].
  void refreshCredentials() {
    _checkCredentials();
    if (state.hasCredentials && !state.isChecking) {
      state = state.copyWith(
        statusMessage: '就绪 — 代理端口 127.0.0.1:1080',
      );
    } else if (!state.hasCredentials && !state.isChecking && state.hasBinary) {
      state = state.copyWith(
        statusMessage: '未配置学号密码，请在设置中配置 ZJU 凭证',
      );
    }
  }

  // ── Binary detection ──────────────────────────────────────

  /// Search for the zju-connect binary in common locations.
  static String? _findBinary() {
    final binName = Platform.isWindows ? 'zju-connect.exe' : 'zju-connect';

    // 1. App config custom path
    final envPath = Platform.environment['ZJU_CONNECT_PATH'];
    if (envPath != null && envPath.isNotEmpty) {
      final f = File(envPath);
      if (f.existsSync()) return f.absolute.path;
      final candidate = p.join(envPath, binName);
      if (File(candidate).existsSync()) return candidate;
    }

    // 2. vendor/zju-connect/ relative to working directory
    final vendorDirs = [
      p.current,
      p.join(p.current, 'vendor'),
      p.join(p.current, 'vendor', 'zju-connect'),
    ];
    for (final dir in vendorDirs) {
      final candidate = p.join(dir, binName);
      if (File(candidate).existsSync()) return candidate;
    }

    // 3. vendor/zju-connect/ relative to executable directory (installed app)
    try {
      final exeDir = p.dirname(Platform.resolvedExecutable);
      final exeVendorDirs = [
        p.join(exeDir, 'vendor'),
        p.join(exeDir, 'vendor', 'zju-connect'),
      ];
      for (final dir in exeVendorDirs) {
        final candidate = p.join(dir, binName);
        if (File(candidate).existsSync()) return candidate;
      }
    } catch (_) {}

    // 4. PATH lookup
    try {
      final pathSep = Platform.isWindows ? ';' : ':';
      final paths = (Platform.environment['PATH'] ?? '').split(pathSep);
      for (final pDir in paths) {
        if (pDir.trim().isEmpty) continue;
        final candidate = p.join(pDir.trim(), binName);
        if (File(candidate).existsSync()) return candidate;
      }
    } catch (_) {}

    return null;
  }

  /// Check whether the zju-connect binary is available.
  Future<void> checkBinary() async {
    state = state.copyWith(isChecking: true);
    await Future.delayed(const Duration(milliseconds: 400));
    final path = _findBinary();
    if (path != null) {
      state = state.copyWith(
        isChecking: false,
        hasBinary: true,
        binaryPath: path,
        statusMessage: state.hasCredentials
            ? '就绪 — 代理端口 127.0.0.1:1080'
            : '未配置学号密码，请在设置中配置 ZJU 凭证',
      );
    } else {
      state = state.copyWith(
        isChecking: false,
        hasBinary: false,
        binaryPath: null,
        statusMessage: '未找到 zju-connect 二进制文件',
      );
    }
  }

  // ── Log capture ─────────────────────────────────────────

  /// Append a line to the in-memory log buffer.
  void _addLogLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return;
    final lines = [...state.logLines, trimmed];
    if (lines.length > _maxLogLines) {
      lines.removeRange(0, lines.length - _maxLogLines);
    }
    state = state.copyWith(logLines: lines);
  }

  /// Start piping stdout/stderr from the child process.
  void _pipeOutput(Process process) {
    _stdoutSub = process.stdout
        .transform(const SystemEncoding().decoder)
        .transform(const LineSplitter())
        .listen(_addLogLine, onError: (e) => _addLogLine('[stderr] $e'));

    _stderrSub = process.stderr
        .transform(const SystemEncoding().decoder)
        .transform(const LineSplitter())
        .listen(_addLogLine, onError: (e) => _addLogLine('[stderr] $e'));
  }

  // ── Health check ────────────────────────────────────────

  /// Try to establish a TCP connection to the SOCKS5 proxy port.
  Future<void> _checkHealth() async {
    if (_process == null) {
      _monitorTimer?.cancel();
      _monitorTimer = null;
      return;
    }

    state = state.copyWith(healthChecking: true);

    try {
      final socket = await Socket.connect(
        '127.0.0.1',
        1080,
        timeout: const Duration(seconds: 3),
      );
      socket.destroy();

      if (_process != null) {
        state = state.copyWith(healthOk: true, healthChecking: false);
        if (state.statusMessage.startsWith('代理运行中')) {
          state = state.copyWith(
            statusMessage: '代理运行中 — 127.0.0.1:1080 ✓',
          );
        }
      }
    } catch (_) {
      if (_process != null) {
        state = state.copyWith(healthOk: false, healthChecking: false);
        if (state.isRunning) {
          state = state.copyWith(
            statusMessage: '代理运行中 — 端口 1080 无响应',
          );
        }
      }
    }
  }

  // ── Process control ─────────────────────────────────────

  /// Start the zju-connect proxy process with credentials from [AppConfig].
  Future<void> start() async {
    if (state.isRunning || _process != null) return;

    // 1. Ensure binary is found
    final binaryPath = state.binaryPath;
    if (binaryPath == null) {
      await checkBinary();
      if (state.binaryPath == null) {
        state = state.copyWith(
          statusMessage: '错误：未找到 zju-connect，请先安装',
        );
        return;
      }
    }

    // 2. Read credentials from AppConfig
    final username = AppConfig.zjuUsername;
    final password = AppConfig.zjuPassword;
    if (username == null || username.isEmpty) {
      state = state.copyWith(
        hasCredentials: false,
        statusMessage: '错误：未配置 ZJU 学号，请在设置中填写',
      );
      return;
    }
    if (password == null || password.isEmpty) {
      state = state.copyWith(
        hasCredentials: false,
        statusMessage: '错误：未配置 ZJU 密码，请在设置中填写',
      );
      return;
    }
    // Mark credentials as present (they might have been missing before)
    if (!state.hasCredentials) {
      state = state.copyWith(hasCredentials: true);
    }

    _addLogLine('────────────────────────────────────────────');
    _addLogLine('[rvpn] 正在启动 zju-connect ...');
    _addLogLine('[rvpn] 服务器: rvpn.zju.edu.cn:443');
    _addLogLine('[rvpn] 用户名: $username');

    try {
      // Build CLI arguments matching zju-connect semantics:
      //   zju-connect -server rvpn.zju.edu.cn -port 443 \
      //               -username <学号> -password <密码>
      final args = [
        '-server', 'rvpn.zju.edu.cn',
        '-port', '443',
        '-username', username,
        '-password', password,
      ];

      _process = await Process.start(
        state.binaryPath!,
        args,
        runInShell: false,
        mode: ProcessStartMode.normal,
      );

      // Start capturing stdout / stderr
      _pipeOutput(_process!);

      state = state.copyWith(
        isRunning: true,
        statusMessage: '代理运行中 — 127.0.0.1:1080',
        exitCode: null,
        healthOk: false,
        healthChecking: false,
      );

      _addLogLine('[rvpn] 进程已启动, PID: ${_process!.pid}');

      // ── Monitor process exit ───────────────────────────
      _process!.exitCode.then((code) {
        // Only react if this is still the current process
        if (_process == null) return;
        _addLogLine('[rvpn] 进程已退出 (exit code: $code)');
        _process = null;
        _stdoutSub?.cancel();
        _stdoutSub = null;
        _stderrSub?.cancel();
        _stderrSub = null;
        _monitorTimer?.cancel();
        _monitorTimer = null;
        state = state.copyWith(
          isRunning: false,
          statusMessage: '代理已退出 (exit code: $code)',
          exitCode: code,
          healthOk: false,
          healthChecking: false,
        );
      });

      // ── Periodic health monitor ────────────────────────
      _monitorTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        _checkHealth();
      });
    } catch (e) {
      _addLogLine('[rvpn] 启动失败: $e');
      Log().error('[rvpn] Failed to start zju-connect', error: e);
      state = state.copyWith(
        isRunning: false,
        statusMessage: '启动失败: $e',
      );
    }
  }

  /// Stop the zju-connect proxy process gracefully.
  Future<void> stop() async {
    if (_process == null) return;

    _addLogLine('[rvpn] 正在停止代理 ...');

    try {
      _process!.kill(ProcessSignal.sigterm);
      // Give it up to 1.5 s to shut down gracefully
      await Future.delayed(const Duration(milliseconds: 1500));
      if (_process != null) {
        _process!.kill(ProcessSignal.sigkill);
        _addLogLine('[rvpn] 进程已被强制终止');
      }
    } catch (_) {
      // Process may already be dead
    }

    _process = null;
    _stdoutSub?.cancel();
    _stdoutSub = null;
    _stderrSub?.cancel();
    _stderrSub = null;
    _monitorTimer?.cancel();
    _monitorTimer = null;

    state = state.copyWith(
      isRunning: false,
      statusMessage: '代理已停止',
      healthOk: false,
      healthChecking: false,
    );
    _addLogLine('[rvpn] 代理已停止');
  }

  /// Clear the in-memory log buffer.
  void clearLog() {
    state = state.copyWith(logLines: []);
  }

  @override
  void dispose() {
    _stdoutSub?.cancel();
    _stderrSub?.cancel();
    _monitorTimer?.cancel();
    _process?.kill(ProcessSignal.sigkill);
    _process = null;
    super.dispose();
  }
}

// ═══════════════════════════════════════════════════════════
// Provider
// ═══════════════════════════════════════════════════════════

final rvpnProvider = StateNotifierProvider<RvpnNotifier, RvpnState>((ref) {
  return RvpnNotifier();
});
