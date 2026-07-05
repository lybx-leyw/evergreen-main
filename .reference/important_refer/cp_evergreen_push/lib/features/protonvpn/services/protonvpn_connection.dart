/// OpenVPN process manager — spawns and controls openvpn.exe.
///
/// Mirrors the rvpn module's approach with zju-connect.exe:
///   Process.start() → pipe stdout/stderr → monitor state → graceful shutdown.
///
/// The OpenVPN management interface (TCP) accepts commands for
/// connection control. Credentials are passed via the management
/// password stdin injection + management-query-passwords.
///
/// Reference:
///   .reference/win-app/src/ProtonVPN.Vpn/Connection/OpenVpnConnection.cs
///   .reference/win-app/src/ProtonVPN.Vpn/OpenVpn/OpenVpnProcess.cs

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import 'protonvpn_models.dart';

class ProtonVpnConnection {
  Process? _process;
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;
  Timer? _healthTimer;
  bool _stopRequested = false;

  final _stateController =
      StreamController<VpnConnectionState>.broadcast();
  Stream<VpnConnectionState> get stateStream => _stateController.stream;

  final _logController = StreamController<String>.broadcast();
  Stream<String> get logStream => _logController.stream;

  VpnConnectionState _state = const VpnConnectionState();
  VpnConnectionState get currentState => _state;

  /// Log buffer (last N lines).
  final List<String> logLines = [];
  static const int _maxLogLines = 200;

  /// Management interface password (random per session).
  String _mgmtPassword = '';

  // ═══════════════════════════════════════════════════════════
  // Binary detection
  // ═══════════════════════════════════════════════════════════

  static String? findBinary() {
    final binName =
        Platform.isWindows ? 'openvpn.exe' : 'openvpn';

    // 1. Environment variable override
    final envPath = Platform.environment['OPENVPN_PATH'];
    if (envPath != null && envPath.isNotEmpty) {
      final candidate = p.join(envPath, binName);
      if (File(candidate).existsSync()) return candidate;
    }

    // 2. vendor/openvpn/ relative to working directory
    final vendorPaths = [
      p.join(p.current, 'vendor', 'openvpn'),
      p.join(p.current, 'vendor'),
      p.current,
    ];
    for (final dir in vendorPaths) {
      final candidate = p.join(dir, binName);
      if (File(candidate).existsSync()) return candidate;
    }

    // 3. vendor/openvpn/ relative to executable directory
    try {
      final exeDir = p.dirname(Platform.resolvedExecutable);
      final exeCandidate = p.join(exeDir, 'vendor', 'openvpn', binName);
      if (File(exeCandidate).existsSync()) return exeCandidate;
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

  // ═══════════════════════════════════════════════════════════
  // Connect / Disconnect
  // ═══════════════════════════════════════════════════════════

  /// Start the OpenVPN process and connect to the specified server.
  ///
  /// [configPath]: path to the .ovpn config file (already written to disk).
  /// [serverIp], [port], [protocol]: override remote endpoint.
  /// [serverName]: display name for the connected server.
  Future<void> connect({
    required String configPath,
    required String serverIp,
    required int port,
    required String protocol,
    String? serverName,
  }) async {
    if (_process != null) return;

    final binaryPath = findBinary();
    if (binaryPath == null) {
      _emit(VpnConnectionState(
        status: VpnConnectionStatus.error,
        message: '未找到 openvpn.exe，请放入 vendor/openvpn/',
      ));
      return;
    }

    _stopRequested = false;
    _mgmtPassword = _generatePassword(16);
    final mgmtPort = await _findFreePort();

    _addLog('────────────────────────────────────────────');
    _addLog('[protonvpn] 正在启动 OpenVPN ...');
    _addLog('[protonvpn] 服务器: $serverIp:$port ($protocol)');
    _addLog('[protonvpn] 管理端口: 127.0.0.1:$mgmtPort');

    try {
      final args = <String>[
        '--config', configPath,
        '--management', '127.0.0.1', mgmtPort.toString(), 'stdin',
        '--management-query-passwords',
        '--management-hold',
        '--remote', serverIp, port.toString(), protocol,
        '--suppress-timestamps',
      ];

      _process = await Process.start(binaryPath, args, runInShell: false);

      // Send management password via stdin
      _process!.stdin.writeln(_mgmtPassword);

      _pipeOutput(_process!);

      _emit(VpnConnectionState(
        status: VpnConnectionStatus.connecting,
        serverName: serverName,
        remoteIp: serverIp,
      ));
      _addLog('[protonvpn] 进程已启动, PID: ${_process!.pid}');

      // Monitor process exit
      _process!.exitCode.then((code) {
        if (_process == null) return;
        _addLog('[protonvpn] 进程已退出 (exit code: $code)');
        _cleanup();
        _emit(VpnConnectionState(
          status: VpnConnectionStatus.disconnected,
          message: 'OpenVPN 已退出 (exit code: $code)',
          exitCode: code,
        ));
      });

      // Periodic health check via management TCP connection
      _healthTimer = Timer.periodic(const Duration(seconds: 4), (_) {
        _checkHealth(mgmtPort);
      });
    } catch (e) {
      _addLog('[protonvpn] 启动失败: $e');
      _emit(VpnConnectionState(
        status: VpnConnectionStatus.error,
        message: '启动失败: $e',
      ));
    }
  }

  /// Gracefully disconnect from the VPN.
  Future<void> disconnect() async {
    if (_process == null) return;

    _stopRequested = true;
    _addLog('[protonvpn] 正在断开连接 ...');
    _emit(VpnConnectionState(status: VpnConnectionStatus.disconnecting));

    try {
      _process!.kill(ProcessSignal.sigterm);
      await Future.delayed(const Duration(milliseconds: 1500));
      if (_process != null) {
        _process!.kill(ProcessSignal.sigkill);
        _addLog('[protonvpn] 进程已被强制终止');
      }
    } catch (_) {
      // Process already dead
    }

    _cleanup();
    _emit(VpnConnectionState(status: VpnConnectionStatus.disconnected));
    _addLog('[protonvpn] 连接已断开');
  }

  // ═══════════════════════════════════════════════════════════
  // Internals
  // ═══════════════════════════════════════════════════════════

  void _pipeOutput(Process process) {
    _stdoutSub = process.stdout
        .transform(const SystemEncoding().decoder)
        .transform(const LineSplitter())
        .listen(_onStdoutLine, onError: (e) => _addLog('[stderr] $e'));

    _stderrSub = process.stderr
        .transform(const SystemEncoding().decoder)
        .transform(const LineSplitter())
        .listen(_onStderrLine, onError: (e) => _addLog('[stderr] $e'));
  }

  void _onStdoutLine(String line) {
    _addLog(line);

    if (line.contains('CONNECTED,SUCCESS')) {
      _emit(VpnConnectionState(
        status: VpnConnectionStatus.connected,
        serverName: _state.serverName,
        remoteIp: _state.remoteIp,
      ));
    } else if (line.contains('AUTH_FAILED')) {
      _emit(VpnConnectionState(
        status: VpnConnectionStatus.error,
        message: '认证失败 — 请检查账号密码',
      ));
    } else if (line.contains('TCP connection established')) {
      _addLog('[protonvpn] TCP 连接已建立');
    }
  }

  void _onStderrLine(String line) {
    _addLog('[stderr] $line');

    if (line.contains('TLS Error') || line.contains('TLS handshake failed')) {
      _emit(VpnConnectionState(
        status: VpnConnectionStatus.error,
        message: 'TLS 握手失败 — 请尝试其他服务器',
      ));
    }
  }

  Future<void> _checkHealth(int mgmtPort) async {
    if (_process == null) {
      _healthTimer?.cancel();
      _healthTimer = null;
      return;
    }

    try {
      final socket = await Socket.connect(
        '127.0.0.1',
        mgmtPort,
        timeout: const Duration(seconds: 2),
      );
      socket.destroy();
    } catch (_) {
      // Management port not reachable — may be starting up
    }
  }

  void _emit(VpnConnectionState st) {
    _state = st;
    _stateController.add(st);
  }

  void _addLog(String line) {
    logLines.add(line);
    if (logLines.length > _maxLogLines) {
      logLines.removeAt(0);
    }
    _logController.add(line);
  }

  void _cleanup() {
    _stdoutSub?.cancel();
    _stdoutSub = null;
    _stderrSub?.cancel();
    _stderrSub = null;
    _healthTimer?.cancel();
    _healthTimer = null;
    _process = null;
  }

  /// Find a free TCP port on localhost.
  Future<int> _findFreePort() async {
    final rng = Random();
    for (int attempt = 0; attempt < 20; attempt++) {
      final port = 50000 + rng.nextInt(15000);
      try {
        final server =
            await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
        await server.close();
        return port;
      } catch (_) {
        continue;
      }
    }
    return 51000; // fallback
  }

  String _generatePassword(int length) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final rng = Random.secure();
    return List.generate(length, (_) => chars[rng.nextInt(chars.length)])
        .join();
  }

  /// Release all resources.
  void dispose() {
    _stopRequested = true;
    _stdoutSub?.cancel();
    _stderrSub?.cancel();
    _healthTimer?.cancel();
    _process?.kill(ProcessSignal.sigkill);
    _process = null;
    _stateController.close();
    _logController.close();
  }
}
