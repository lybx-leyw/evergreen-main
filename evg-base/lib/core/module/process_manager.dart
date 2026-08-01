/// 进程作用域管理器 —— 按 PLAN_NOW 第3.3节管理四种进程生命周期。
///
/// 对应 manifest 中声明的四种 ProcessDescriptor：
/// - **模块级** (`module.process`): 页面激活时运行 → 切走时停止
/// - **页面级** (`page.globalProcess`): 页面激活时运行 → 切走时停止
/// - **栏级** (`slot.process`): 栏可见时运行 → 隐藏时停止
/// - **动作级** (`action.process`): 触发时启动 → 完成即退出
///
/// # 公开类
///
/// | 类 | 说明 |
/// |---|------|
/// | [ProcessManager] | 统一管理一个模块下所有作用域的进程 |
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:evergreen_base/core/plugin/plugin_runner.dart';
import 'module_descriptor.dart';

/// 进程管理器 —— 管理一个模块下所有作用域的后端进程。
///
/// 使用方式：
/// ```dart
/// final pm = ProcessManager(moduleId: 'vocab-tutor', workingDir: pluginDir);
/// await pm.startModule(descriptor.process);
/// await pm.startPage('learn', pages[0].globalProcess);
/// await pm.startSlot('learn', 'left', slots['left']!.process);
/// final result = await pm.runAction(action.process);
/// pm.dispose();
/// ```
class ProcessManager {
  final String moduleId;
  final String workingDirectory;

  /// 模块级进程（全局唯一，module.process）。
  _ManagedProcess? _moduleProcess;

  /// 页面级进程（pageId → process）。
  final Map<String, _ManagedProcess> _pageProcesses = {};

  /// 栏级进程（pageId:slotKey → process）。
  final Map<String, _ManagedProcess> _slotProcesses = {};

  ProcessManager({
    required this.moduleId,
    required this.workingDirectory,
  });

  // ═══════ 模块级 ═══════

  /// 模块是否有运行中的进程。
  bool get hasModuleProcess => _moduleProcess != null && _moduleProcess!.isAlive;

  /// 启动模块级后端进程。
  ///
  /// [desc] 来自 [ModuleDescriptor.process]。
  Future<void> startModule(ProcessDescriptor? desc) async {
    if (desc == null) {
      debugPrint('[PM:$moduleId] 无模块级 process，跳过');
      return;
    }
    if (hasModuleProcess) {
      debugPrint('[PM:$moduleId] 模块级进程已在运行');
      return;
    }

    debugPrint('[PM:$moduleId] 🚀 启动模块级进程: ${desc.exe}');
    final mp = _ManagedProcess(
      scope: 'module',
      key: moduleId,
      desc: desc,
      workingDir: workingDirectory,
    );
    await mp.start();
    _moduleProcess = mp;
  }

  /// 停止模块级后端进程。
  Future<void> stopModule() async {
    if (_moduleProcess == null) return;
    debugPrint('[PM:$moduleId] ⏹ 停止模块级进程');
    await _moduleProcess!.stop();
    _moduleProcess = null;
  }

  // ═══════ 页面级 ═══════

  /// 启动页面级后端进程（globalProcess）。
  ///
  /// [pageId] 来自 [PageDescriptor.id]。
  /// [desc] 来自 [PageDescriptor.globalProcess]。
  Future<void> startPage(String pageId, ProcessDescriptor? desc) async {
    if (desc == null) return;

    final key = '$pageId:page';
    if (_pageProcesses.containsKey(key)) {
      debugPrint('[PM:$moduleId] 页面 "$pageId" 进程已在运行');
      return;
    }

    debugPrint('[PM:$moduleId] 🚀 启动页面级进程: $pageId → ${desc.exe}');
    final mp = _ManagedProcess(
      scope: 'page',
      key: key,
      desc: desc,
      workingDir: workingDirectory,
    );
    await mp.start();
    _pageProcesses[key] = mp;
  }

  /// 停止指定页面的后端进程（切走页面时调用）。
  Future<void> stopPage(String pageId) async {
    final key = '$pageId:page';
    final mp = _pageProcesses.remove(key);
    if (mp == null) return;

    debugPrint('[PM:$moduleId] ⏹ 停止页面 "$pageId" 进程');
    await mp.stop();
  }

  // ═══════ 栏级 ═══════

  /// 启动栏级后端进程（slot.component.process）。
  ///
  /// [pageId] 栏位所在页面。
  /// [slotKey] 栏位键名（如 `"left"`、`"right"`）。
  /// [desc] 来自 [ComponentConfig.process]。
  Future<void> startSlot(
      String pageId, String slotKey, ProcessDescriptor? desc) async {
    if (desc == null) return;

    final key = '$pageId:$slotKey';
    if (_slotProcesses.containsKey(key)) {
      debugPrint('[PM:$moduleId] 栏 "$key" 进程已在运行');
      return;
    }

    debugPrint('[PM:$moduleId] 🚀 启动栏级进程: $key → ${desc.exe}');
    final mp = _ManagedProcess(
      scope: 'slot',
      key: key,
      desc: desc,
      workingDir: workingDirectory,
    );
    await mp.start();
    _slotProcesses[key] = mp;
  }

  /// 停止指定栏的后端进程（栏隐藏时调用）。
  Future<void> stopSlot(String pageId, String slotKey) async {
    final key = '$pageId:$slotKey';
    final mp = _slotProcesses.remove(key);
    if (mp == null) return;

    debugPrint('[PM:$moduleId] ⏹ 停止栏 "$key" 进程');
    await mp.stop();
  }

  /// 停止指定页面的所有栏级进程。
  Future<void> stopAllSlotsOfPage(String pageId) async {
    final toRemove = <String>[];
    for (final entry in _slotProcesses.entries) {
      if (entry.key.startsWith('$pageId:')) {
        toRemove.add(entry.key);
        await entry.value.stop();
      }
    }
    for (final key in toRemove) {
      _slotProcesses.remove(key);
    }
    if (toRemove.isNotEmpty) {
      debugPrint('[PM:$moduleId] 已停止页面 "$pageId" 的 ${toRemove.length} 个栏级进程');
    }
  }

  // ═══════ 动作级 ═══════

  /// 运行动作级后端进程（一次性，执行完即退出）。
  ///
  /// [desc] 来自 [ActionButtonDescriptor.process]。
  /// 返回进程的 stdout 输出。
  Future<String> runAction(ProcessDescriptor? desc, {String? input}) async {
    if (desc == null) return '';

    debugPrint('[PM:$moduleId] ⚡ 运行动作进程: ${desc.exe}');
    try {
      final exePath = p.join(workingDirectory, desc.exe);
      final exeFile = File(exePath);
      if (!exeFile.existsSync()) {
        debugPrint('[PM:$moduleId] ⚠️ 动作 exe 不存在: $exePath');
        return '[error: exe not found: $exePath]';
      }

      final runner = await sharedPluginRunner;
      final process = await runner.startLong(
        exePath,
        [],
        workingDirectory: workingDirectory,
        runtime: desc.runtime,
      );

      // 如果有输入，写入 stdin（stdio 协议）
      if (input != null && desc.protocol == 'stdio') {
        process.stdin.write(input);
        await process.stdin.close();
      }

      final stdoutStr = await process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .join('\n');

      final exitCode = await process.exitCode;
      debugPrint('[PM:$moduleId] 动作进程退出: code=$exitCode');

      return stdoutStr;
    } catch (e) {
      debugPrint('[PM:$moduleId] ⚠️ 动作进程失败: $e');
      return '[error: $e]';
    }
  }

  // ═══════ 生命周期 ═══════

  /// 当前运行中的进程总数。
  int get runningCount {
    int count = 0;
    if (_moduleProcess?.isAlive == true) count++;
    count += _pageProcesses.values.where((p) => p.isAlive).length;
    count += _slotProcesses.values.where((p) => p.isAlive).length;
    return count;
  }

  /// 停止所有进程并释放资源。
  Future<void> dispose() async {
    debugPrint('[PM:$moduleId] 释放所有进程 (running=$runningCount)...');

    await stopModule();

    for (final mp in [..._pageProcesses.values]) {
      await mp.stop();
    }
    _pageProcesses.clear();

    for (final mp in [..._slotProcesses.values]) {
      await mp.stop();
    }
    _slotProcesses.clear();

    debugPrint('[PM:$moduleId] 所有进程已停止');
  }
}

// ═══════ _ManagedProcess ═══════

/// 内部托管的单个进程。
class _ManagedProcess {
  final String scope; // "module" | "page" | "slot"
  final String key;
  final ProcessDescriptor desc;
  final String workingDir;

  Process? _process;
  int? _port;
  bool _healthy = false;
  StreamSubscription? _stdoutSub;
  StreamSubscription? _stderrSub;

  _ManagedProcess({
    required this.scope,
    required this.key,
    required this.desc,
    required this.workingDir,
  });

  bool get isAlive => _healthy;
  int? get port => _port;

  /// 启动进程 → 端口检测 → health check。
  Future<void> start() async {
    try {
      final exePath = p.join(workingDir, desc.exe);
      final exeFile = File(exePath);
      if (!exeFile.existsSync()) {
        debugPrint('[PM] ⚠️ exe 不存在: $exePath');
        return;
      }

      // 构建启动参数
      final args = <String>[];
      if (desc.preferredPort > 0) {
        args.addAll(['--port', desc.preferredPort.toString()]);
      }

      final runner = await sharedPluginRunner;
      _process = await runner.startLong(
        exePath,
        args,
        workingDirectory: workingDir,
        runtime: desc.runtime,
      );
      debugPrint('[PM] 进程已启动: ${desc.exe} pid=${_process!.pid}');

      // stderr 转发
      _stderrSub = _process!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        debugPrint('[PM] ${desc.exe} stderr: $line');
      });

      if (desc.protocol == 'http') {
        await _waitForHttpReady();
      } else {
        // stdio: 无需端口检测，直接标记健康
        _healthy = true;
        debugPrint('[PM] ${desc.exe} stdio 模式就绪');
      }
    } catch (e) {
      debugPrint('[PM] ⚠️ 启动失败: ${desc.exe} — $e');
      _kill();
    }
  }

  /// HTTP 协议：等待 PORT: 输出 → health check。
  Future<void> _waitForHttpReady() async {
    final portCompleter = Completer<int>();

    _stdoutSub = _process!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      if (!portCompleter.isCompleted) {
        final match = RegExp(r'^PORT:(\d+)').firstMatch(line);
        if (match != null) {
          final p = int.parse(match.group(1)!);
          portCompleter.complete(p);
        }
      }
      // 非 PORT 行 — 普通 stdout 日志
      if (!line.startsWith('PORT:')) {
        debugPrint('[PM] ${desc.exe} stdout: $line');
      }
    });

    // 等待端口行（超时 10 秒）
    try {
      _port = await portCompleter.future.timeout(
        const Duration(seconds: 10),
      );
    } on TimeoutException {
      debugPrint('[PM] ⚠️ ${desc.exe} 端口检测超时');
      _kill();
      return;
    }

    // 等 500ms 让 PyInstaller onefile 解压后就绪
    await Future.delayed(const Duration(milliseconds: 500));

    // health check（最多重试 3 次）
    for (var i = 0; i < 3; i++) {
      try {
        final client = HttpClient();
        final request = await client.get('localhost', _port!, '/health');
        final response =
            await request.close().timeout(const Duration(seconds: 10));
        if (response.statusCode == 200) {
          _healthy = true;
          debugPrint('[PM] ${desc.exe} health check 通过 port=$_port');
          client.close();
          return;
        }
        debugPrint(
            '[PM] ${desc.exe} health check 返回 ${response.statusCode}'
            ' (第 ${i + 1} 次)');
        client.close();
      } catch (e) {
        debugPrint(
            '[PM] ${desc.exe} health check 失败 (第 ${i + 1} 次): $e');
      }
      if (i < 2) await Future.delayed(const Duration(seconds: 1));
    }

    // 3 次失败 → 杀进程
    _kill();
  }

  /// 停止进程（先 SIGTERM，2s 超时后 SIGKILL）。
  Future<void> stop() async {
    _stdoutSub?.cancel();
    _stdoutSub = null;
    _stderrSub?.cancel();
    _stderrSub = null;
    _healthy = false;
    _port = null;

    if (_process == null) return;

    try {
      _process!.kill(ProcessSignal.sigterm);
      // 等待 2 秒优雅退出
      final exited = await _process!.exitCode
          .timeout(const Duration(seconds: 2))
          .then((_) => true)
          .catchError((_) => false);
      if (!exited) {
        _process!.kill(ProcessSignal.sigkill);
        debugPrint('[PM] ${desc.exe} 强制终止 (SIGKILL)');
      }
    } catch (_) {
      // 进程已退出
    }
    _process = null;
  }

  void _kill() {
    _stdoutSub?.cancel();
    _stdoutSub = null;
    _stderrSub?.cancel();
    _stderrSub = null;
    _healthy = false;
    _port = null;
    if (_process == null) return;
    try {
      _process!.kill(ProcessSignal.sigterm);
    } catch (_) {}
    _process = null;
  }
}
