/// 外部数据源生命周期管理——启动 .exe、探测端口、健康检查、自动注册。
///
/// # 公开 API
///
/// | 成员 | 说明 |
/// |------|------|
/// | `DataSourceLoader({manifest, workingDirectory})` | 构造 |
/// | `.start(orchestrator)` | 启动 → 探测端口 → 健康检查 → 注册 |
/// | `.stop()` | 终止进程，清理资源（不触发自动重启） |
/// | `.restart()` | 手动重启长驻进程（复用已注册 DataType，失败抛异常并标记状态） |
/// | `.unregisterAll(orchestrator)` | 批量注销已注册的所有类型 |
/// | `isRunning` | 进程是否已启动且健康 |
/// | `port` | 实际端口号 |
/// | `scanAndLoadDataSources({pluginsDir, orchestrator})` | 扫描 `plugins/*/data/manifest.json`，批量启动并注册 |

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:evergreen_base/core/log.dart';
import 'package:evergreen_base/core/plugin/plugin_runner.dart';

import '../orchestrator.dart';
import '../type.dart';
import '../../utils/greenix_path.dart';
import 'data_source_manifest.dart';

// ═══════════════════════════════════════════════════════════════════════════
// DataSourceLoader
// ═══════════════════════════════════════════════════════════════════════════

/// 外部数据源插件生命周期管理器。
class DataSourceLoader {
  final DataSourceManifest manifest;
  final String workingDirectory;
  final String projectRoot;

  Process? _process;
  HttpClient? _client;
  int? _port;
  bool _started = false;
  bool _healthy = false;

  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;
  Completer<int>? _portCompleter;
  final List<DataType<dynamic>> _registeredTypes = [];

  // 进程守护（崩溃自动重启）状态。
  DataOrchestrator? _orchestrator;
  Timer? _restartTimer;
  int _restartAttempts = 0;
  bool _stopRequested = false;

  /// 崩溃自动重启退避间隔（第 1/2/3 次），第 3 次失败后放弃（不无限重试）。
  final List<Duration> restartBackoff;

  /// 默认退避：1s / 3s / 9s，最多 3 次。
  static const List<Duration> kDefaultRestartBackoff = [
    Duration(seconds: 1),
    Duration(seconds: 3),
    Duration(seconds: 9),
  ];

  DataSourceLoader({
    required this.manifest,
    required this.workingDirectory,
    required this.projectRoot,
    List<Duration>? restartBackoff,
  }) : restartBackoff = restartBackoff ?? kDefaultRestartBackoff;

  bool get isRunning => _started && _healthy;
  int? get port => _port;

  // ═══════════════════════════════════════════════════════════════════════
  // 生命周期
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> start(DataOrchestrator orchestrator) async {
    if (_started) return;
    _orchestrator = orchestrator;
    _stopRequested = false;
    await _startInternal(orchestrator);
  }

  /// 启动长驻进程（启动 → 探测端口 → 健康检查 → 注册）。供 [start] 与崩溃重启复用。
  Future<void> _startInternal(DataOrchestrator orchestrator) async {
    final runner = await sharedPluginRunner;
    Log()
        .info('DataSourceLoader: 启动 ${manifest.processExe} (${manifest.name})');

    // preferredPort > 0 时作为 --port 参数传给插件进程。
    // 同时传入 --project-root（用于策略2 HTTP: 找 .config_port）和
    // --greenix-config（用于策略1 本地文件: 直接读 .greenix/config.json）。
    // Android 侧 MainActivity.kt 从 args 提取并注入为 Python os.environ。
    final args = <String>[
      '--project-root',
      projectRoot,
      '--greenix-config',
      greenixConfigPath,
    ];
    if (manifest.preferredPort > 0) {
      args.addAll(['--port', '${manifest.preferredPort}']);
    }
    _process = await runner.startLong(
      _resolveExePath(),
      args,
      workingDirectory: workingDirectory,
      runtime: manifest.runtime,
    );
    _listenStderr();
    _listenStdout();

    _port = await _awaitPort();

    _client = HttpClient();
    _client!.connectionTimeout = const Duration(seconds: 5);

    await _healthCheck();

    _registerAllTypes(orchestrator);

    _process!.exitCode.then(_onProcessExit);

    _started = true;
    // 成功启动（含重启成功）后复位退避计数。
    _restartAttempts = 0;
  }

  Future<void> stop() async {
    // 显式停止：置标志使后续进程退出不再触发自动重启。
    _stopRequested = true;
    _restartTimer?.cancel();
    _restartTimer = null;
    if (!_started && _process == null) return;
    Log().info('DataSourceLoader: 停止 ${manifest.id}');
    await _teardownProcess();
  }

  /// 手动重启长驻进程。要求已通过 [start] 启动过（否则抛 [StateError]）。
  /// 复用已注册的 DataType（重新注册以刷新端口 URL）；重启失败时抛异常并
  /// 标记 `connected=false` + `lastError`。
  Future<void> restart() async {
    final orch = _orchestrator;
    if (orch == null) {
      throw StateError('DataSourceLoader 尚未启动，无法重启 ${manifest.id}');
    }
    // 拆解期间的旧进程退出回调不应误触发自动重启。
    _stopRequested = true;
    _restartTimer?.cancel();
    _restartTimer = null;
    _restartAttempts = 0;
    await _teardownProcess();
    _stopRequested = false; // 新进程就绪后恢复崩溃自动重启能力
    try {
      await _startInternal(orch);
    } catch (e) {
      _markUnavailable('手动重启失败: $e');
      rethrow;
    }
  }

  /// 终止进程并清理进程 I/O 资源（不触发自动重启的公共拆解）。
  Future<void> _teardownProcess() async {
    await _stdoutSub?.cancel();
    _stdoutSub = null;
    await _stderrSub?.cancel();
    _stderrSub = null;
    await _killProcess();
    _client?.close(force: true);
    _client = null;
    _port = null;
    _healthy = false;
    _started = false;
  }

  void unregisterAll(DataOrchestrator orchestrator) {
    for (final type in _registeredTypes) {
      orchestrator.unregister(type);
    }
    _registeredTypes.clear();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 内部
  // ═══════════════════════════════════════════════════════════════════════

  String _resolveExePath() {
    final sep = Platform.pathSeparator;
    return '$workingDirectory$sep${manifest.processExe.replaceAll('/', sep)}';
  }

  void _listenStderr() {
    _stderrSub = _process!.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      Log().debug('DataSourceLoader [${manifest.id}] stderr: $line');
    });
  }

  void _listenStdout() {
    _portCompleter = Completer<int>();
    _stdoutSub = _process!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_tryDetectPort);
  }

  void _tryDetectPort(String line) {
    if (_portCompleter == null || _portCompleter!.isCompleted) return;
    final m = RegExp(r'PORT:(\d+)').firstMatch(line);
    if (m != null) _portCompleter!.complete(int.parse(m.group(1)!));
  }

  Future<int> _awaitPort() async {
    const timeout = Duration(seconds: 10);
    try {
      return await _portCompleter!.future.timeout(
        timeout,
        onTimeout: () => throw TimeoutException(
          '无法在 ${timeout.inSeconds}s 内探测到 ${manifest.id} 的端口',
        ),
      );
    } catch (e) {
      Log().error('DataSourceLoader: 端口探测失败 ${manifest.id}', error: e);
      await _killProcess();
      rethrow;
    }
  }

  Future<void> _healthCheck() async {
    try {
      final request = await _client!.getUrl(Uri(
          scheme: 'http', host: 'localhost', port: _port!, path: '/health'));
      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException('健康检查返回 ${response.statusCode}');
      }
      _healthy = true;
      Log().info('DataSourceLoader: 健康检查通过 ${manifest.id} (port: $_port)');
    } catch (e) {
      Log().error('DataSourceLoader: 健康检查失败 ${manifest.id}', error: e);
      await _killProcess();
      rethrow;
    }
  }

  void _onProcessExit(int code) {
    // 捕获退出前是否已成功启动——初始启动失败（端口/健康检查阶段）不自动重启，
    // 避免与 scanAndLoadDataSources 的 catch 形成重启风暴。
    final wasRunning = _started;
    Log().info('DataSourceLoader: 进程退出 ${manifest.id} (code: $code)');
    _healthy = false;
    _started = false;
    _port = null;
    _client?.close(force: true);
    _client = null;
    if (!wasRunning || _stopRequested) return;
    _scheduleRestart();
  }

  /// 崩溃后退避自动重启：1s/3s/9s 最多 3 次；成功恢复 `_healthy`，用尽则
  /// 标记 `connected=false` + `lastError`（不无限重试）。重启期间已注册 DataType
  /// 保留，`get` 返回旧缓存或「未就绪」明确错误。
  void _scheduleRestart() {
    if (_stopRequested) return;
    if (_restartAttempts >= restartBackoff.length) {
      Log().error('DataSourceLoader: 重启次数用尽，放弃 ${manifest.id}',
          data: {'attempts': _restartAttempts});
      _markUnavailable('进程崩溃且自动重启次数用尽');
      return;
    }
    final delay = restartBackoff[_restartAttempts];
    Log().warn('DataSourceLoader: 进程崩溃，${delay.inSeconds}s 后自动重启 '
        '${manifest.id}（第 ${_restartAttempts + 1}/${restartBackoff.length} 次）');
    _restartTimer?.cancel();
    _restartTimer = Timer(delay, () async {
      _restartAttempts++;
      final orch = _orchestrator;
      if (orch == null || _stopRequested) return;
      try {
        await _startInternal(orch);
        Log().info('DataSourceLoader: 自动重启成功 ${manifest.id}');
        _markAvailable();
      } catch (e) {
        Log().error('DataSourceLoader: 自动重启失败 ${manifest.id}', error: e);
        _scheduleRestart();
      }
    });
  }

  /// 标记所有已注册类型不可用（connected=false + lastError）。
  void _markUnavailable(String reason) {
    final orch = _orchestrator;
    if (orch == null) return;
    for (final type in _registeredTypes) {
      final s = orch.status(type.name);
      if (s != null) {
        s.connected = false;
        s.lastError = reason;
      }
    }
  }

  /// 重启成功后清除各已注册类型的 lastError（connected 由下次成功拉取置 true）。
  void _markAvailable() {
    final orch = _orchestrator;
    if (orch == null) return;
    for (final type in _registeredTypes) {
      final s = orch.status(type.name);
      if (s != null) s.lastError = null;
    }
  }

  Future<void> _killProcess() async {
    if (_process == null) return;
    try {
      _process!.kill(ProcessSignal.sigterm);
      await _process!.exitCode.timeout(const Duration(seconds: 2),
          onTimeout: () {
        _process?.kill(ProcessSignal.sigkill);
        return -1;
      });
    } catch (_) {}
    _process = null;
  }

  void _registerAllTypes(DataOrchestrator orchestrator) {
    // 重启时重建注册（端口可能变化，需用新端口刷新 URL），避免重复累积。
    _registeredTypes.clear();
    for (final decl in manifest.dataTypes) {
      final url = decl.buildUrl(_port!);
      final dataType = decl.toDataType();
      orchestrator.register(dataType, () => _fetch(decl.name, url));
      _registeredTypes.add(dataType);
      Log().info('DataSourceLoader: 已注册 $dataType → $url');
    }
  }

  Future<dynamic> _fetch(String name, String url) async {
    if (_client == null || !_healthy) {
      throw StateError('数据源 ${manifest.id} 未就绪，无法获取 $name');
    }
    final uri = Uri.parse('http://localhost:$_port$url');
    final request = await _client!.getUrl(uri);
    final response = await request.close();
    if (response.statusCode != 200) {
      throw HttpException('获取 $name 失败: ${response.statusCode}');
    }
    final body = await response.transform(utf8.decoder).join();
    return jsonDecode(body);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// scanAndLoadDataSources
// ═══════════════════════════════════════════════════════════════════════════

Future<List<DataSourceLoader>> scanAndLoadDataSources({
  required String pluginsDir,
  required DataOrchestrator orchestrator,
  required String projectRoot,
}) async {
  final loaders = <DataSourceLoader>[];
  final dir = Directory(pluginsDir);
  if (!await dir.exists()) {
    Log().info('DataSourceLoader: 插件目录不存在: $pluginsDir');
    return loaders;
  }

  await for (final entity in dir.list()) {
    if (entity is! Directory) continue;
    // 新路径：plugins/<name>/data/manifest.json，exe 也放在 data/ 下
    final dataDir = Directory('${entity.path}${Platform.pathSeparator}data');
    final mf = File('${dataDir.path}${Platform.pathSeparator}manifest.json');
    if (!await mf.exists()) continue;

    try {
      final json = jsonDecode(await mf.readAsString()) as Map<String, dynamic>;
      if (json['type'] != 'data-source') continue;

      final manifest = DataSourceManifest.fromJson(json);

      // 规划 §5.3 C 安全网：安卓不支持（androidSupport=false，如依赖 C 扩展
      // 的 OCR/翻译/PDF/ML 插件）的 http 数据源直接跳过，避免崩溃。
      if (!DataSourceManifest.isSupportedOn(manifest,
          isAndroid: Platform.isAndroid)) {
        Log().info('DataSourceLoader: 安卓不支持 ${manifest.id}，'
            '跳过（androidSupport=false）');
        continue;
      }

      final loader = DataSourceLoader(
        manifest: manifest,
        workingDirectory: dataDir.path,
        projectRoot: projectRoot,
      );
      await loader.start(orchestrator);
      loaders.add(loader);
      Log().info('DataSourceLoader: 加载成功 ${manifest.id}');
    } catch (e) {
      Log().error('DataSourceLoader: 加载失败 ${entity.path}', error: e);
    }
  }

  return loaders;
}
