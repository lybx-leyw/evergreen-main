/// 自动编译服务 —— 检测 .py 文件变化，触发 PyInstaller 编译 → 重启子进程。
///
/// P3 实现：监听插件目录中 data/*.py 变化，自动编译为 .exe。
///
/// 状态机：idle → compiling → restarting → idle
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

/// 编译状态。
enum CompileStatus { idle, compiling, restarting, failed }

/// 编译事件。
class CompileEvent {
  final CompileStatus status;
  final String pluginId;
  final String? scriptPath;
  final String? error;
  final DateTime timestamp;

  const CompileEvent({
    required this.status,
    required this.pluginId,
    this.scriptPath,
    this.error,
    required this.timestamp,
  });

  @override
  String toString() => 'CompileEvent($status, $pluginId)';
}

/// 自动编译服务。
///
/// 监听 data/ 目录中的 .py 文件变化 → 调用 PyInstaller 编译 → 通知上游。
class AutoCompileService {
  final String _pluginsDir;
  Timer? _debounceTimer;

  final _eventController = StreamController<CompileEvent>.broadcast();
  Stream<CompileEvent> get onEvent => _eventController.stream;

  CompileStatus _status = CompileStatus.idle;
  CompileStatus get status => _status;

  /// Python 可执行文件路径（可配置）。
  String pythonPath;

  /// PyInstaller 路径（可配置）。
  String pyinstallerPath;

  AutoCompileService(
    this._pluginsDir, {
    this.pythonPath = 'python',
    this.pyinstallerPath = 'pyinstaller',
  });

  /// 监听特定插件的 .py 变化并编译。
  ///
  /// 返回是否成功启动编译（非 debounce 期间）。
  Future<bool> compileScript(String pluginId, String scriptPath) async {
    if (_status == CompileStatus.compiling) return false;

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () async {
      await _doCompile(pluginId, scriptPath);
    });
    return true;
  }

  /// 立即编译（跳过去抖）。
  Future<CompileEvent> compileNow(String pluginId, String scriptPath) async {
    _debounceTimer?.cancel();
    return _doCompile(pluginId, scriptPath);
  }

  Future<CompileEvent> _doCompile(String pluginId, String scriptPath) async {
    _setStatus(CompileStatus.compiling, pluginId, scriptPath);

    try {
      final file = File(scriptPath);
      if (!await file.exists()) {
        return _fail(pluginId, scriptPath, '脚本文件不存在: $scriptPath');
      }

      // 编译输出目录：plugins/<id>/data/
      final outputDir = p.dirname(scriptPath);
      final dir = Directory(outputDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      // 运行 PyInstaller
      final result = await Process.run(pythonPath, [
        '-m', 'PyInstaller',
        '--onefile',
        '--distpath', outputDir,
        '--workpath', p.join(outputDir, '_build'),
        '--specpath', outputDir,
        '--name', pluginId,
        scriptPath,
      ], runInShell: false);

      if (result.exitCode != 0) {
        final errOutput = (result.stderr as String?) ?? result.stdout.toString();
        return _fail(pluginId, scriptPath,
            'PyInstaller 失败 (exit=${result.exitCode}): $errOutput');
      }

      _setStatus(CompileStatus.restarting, pluginId, scriptPath);

      // 检查 .exe 是否生成
      final exePath = p.join(outputDir, '$pluginId.exe');
      if (await File(exePath).exists()) {
        _setStatus(CompileStatus.idle, pluginId, scriptPath);
        final event = CompileEvent(
          status: CompileStatus.idle,
          pluginId: pluginId,
          scriptPath: scriptPath,
          timestamp: DateTime.now(),
        );
        _eventController.add(event);
        return event;
      } else {
        return _fail(pluginId, scriptPath, '.exe 未生成: $exePath');
      }
    } catch (e) {
      return _fail(pluginId, scriptPath, e.toString());
    }
  }

  CompileEvent _fail(String pluginId, String scriptPath, String error) {
    _setStatus(CompileStatus.failed, pluginId, scriptPath, error);
    final event = CompileEvent(
      status: CompileStatus.failed,
      pluginId: pluginId,
      scriptPath: scriptPath,
      error: error,
      timestamp: DateTime.now(),
    );
    _eventController.add(event);
    return event;
  }

  void _setStatus(CompileStatus s, String pluginId, String? scriptPath,
      [String? error]) {
    _status = s;
    _eventController.add(CompileEvent(
      status: s,
      pluginId: pluginId,
      scriptPath: scriptPath,
      error: error,
      timestamp: DateTime.now(),
    ));
  }

  void dispose() {
    _debounceTimer?.cancel();
    _eventController.close();
  }
}
