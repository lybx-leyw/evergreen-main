/// 模块加载器——扫描 manifest.json 并管理 .exe 后端进程生命周期。
///
/// # [ModuleLoader] —— 单进程管理
///
/// | 方法 | 输入 | 输出 | 说明 |
/// |---|---|---|---|
/// | `ModuleLoader(manifest, workingDir)` | descriptor + 目录 | `ModuleLoader` | 构造 |
/// | `start()` | — | `Future<void>` | 启动 exe → 端口检测 → health check |
/// | `stop()` | — | `void` | 终止进程 |
/// | `isRunning` | — | `bool` | 进程是否健康运行 |
/// | `port` | — | `int?` | 监听端口 |
///
/// # 顶层函数
///
/// | 函数 | 输入 | 输出 | 说明 |
/// |---|---|---|---|
/// | `loadBuiltinModules(dir, registry)` | `String`, `ModuleRegistry` | `void` | 加载内置模块 |
/// | `scanModules(dir)` | `String` | `List<ModuleDescriptor>` | 纯扫描，不启动进程 |
/// | `scanAndLoadModules(dir, registry)` | `String`, `ModuleRegistry` | `List<ModuleLoader>` | 扫描 + 注册 + 启动进程 |
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:evergreen_base/core/log.dart';
import 'capability.dart';
import 'module_descriptor.dart';
import 'module_registry.dart';

// ═══════ ModuleLoader ═══════

/// 管理单个 process-backed 模块的后端进程生命周期。
class ModuleLoader {
  final ModuleDescriptor manifest;
  final String workingDirectory;
  final String projectRoot;

  Process? _process;
  int? _port;
  bool _healthy = false;
  StreamSubscription? _stdoutSub;
  StreamSubscription? _stderrSub;

  ModuleLoader(this.manifest, this.workingDirectory, {required this.projectRoot});

  /// 进程是否已启动且健康。
  bool get isRunning => _healthy;

  /// 后端进程监听端口。启动完成前返回 null。
  int? get port => _port;

  /// 启动后端 exe 进程，等待端口就绪并通过 health check。
  Future<void> start() async {
    final proc = manifest.process;
    if (proc == null) return;

    try {
      final exePath = p.join(workingDirectory, proc.exe);
      final exeFile = File(exePath);
      if (!exeFile.existsSync()) {
        Log().warn('ModuleLoader: ${manifest.id} 的 exe 不存在',
            data: {'path': exePath});
        return;
      }

    _process = await Process.start(exePath, ['--project-root', projectRoot], workingDirectory: workingDirectory);
    Log().info('ModuleLoader: ${manifest.id} 进程已启动', data: {'pid': _process!.pid, 'projectRoot': projectRoot});

    // 监听 stderr —— 转发到宿主日志系统
    _stderrSub = _process!.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      Log().info('ModuleLoader: ${manifest.id}.exe stderr: $line');
    });

    // 监听 stdout —— 等待 PORT: 行
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
    });

    // 等待端口行（超时 1 秒）
    try {
      _port = await portCompleter.future.timeout(const Duration(seconds: 10));
    } on TimeoutException {
      Log().warn('ModuleLoader: ${manifest.id} 端口检测超时');
      _kill();
      return;
    }

    // PORT 拿到后关闭 stdout 监听
    _stdoutSub?.cancel();
    _stdoutSub = null;

    // 等 500ms 让 PyInstaller onefile 解压后的服务就绪
    await Future.delayed(const Duration(milliseconds: 500));

    // Health check（最多重试 3 次，间隔 1 秒）
    var attempts = 0;
    while (attempts < 3) {
      attempts++;
      try {
        final client = HttpClient();
        final request = await client.get('localhost', _port!, '/health');
        final response =
            await request.close().timeout(const Duration(seconds: 10));
        if (response.statusCode == 200) {
          _healthy = true;
          Log().info('ModuleLoader: ${manifest.id} health check 通过',
              data: {'port': _port});
          client.close();
          return;
        }
        Log().warn(
            'ModuleLoader: ${manifest.id} health check 返回 ${response.statusCode}'
            ' (第 $attempts 次)');
        client.close();
      } catch (e) {
        Log().warn(
            'ModuleLoader: ${manifest.id} health check 失败 (第 $attempts 次)',
            error: e);
      }
      if (attempts < 3) await Future.delayed(const Duration(seconds: 1));
    }
      _kill();
    } catch (e, stack) {
      Log().error('ModuleLoader: ${manifest.id} start 异常', error: e, stack: stack);
      _kill();
    }
  }

  /// 终止后端进程。
  void stop() {
    _stdoutSub?.cancel();
    _stdoutSub = null;
    _stderrSub?.cancel();
    _stderrSub = null;
    _healthy = false;
    _port = null;
    _kill();
  }

  void _kill() {
    _stdoutSub?.cancel();
    _stdoutSub = null;
    _stderrSub?.cancel();
    _stderrSub = null;
    if (_process == null) return;
    try {
      _process!.kill(ProcessSignal.sigterm);
    } catch (_) {}
    _process = null;
  }
}

// ═══════ 扫描 ═══════

/// 扫描单个目录下的所有子目录中的 manifest.json，回调每个解析出的 [ModuleDescriptor]。
void _scanDir(String parentDir, void Function(ModuleDescriptor, String dirPath) onFound) {
  final dir = Directory(parentDir);
  if (!dir.existsSync()) return;

  for (final entity in dir.listSync()) {
    if (entity is! Directory) continue;
    final manifestFile = File(p.join(entity.path, 'module', 'manifest.json'));
    if (!manifestFile.existsSync()) continue;

    try {
      final map =
          jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
      if (map['type'] != 'module') continue;
      onFound(ModuleDescriptor.fromJson(map), entity.path);
    } catch (e) {
      Log().warn('ModuleLoader: 解析失败 ${manifestFile.path}', error: e);
    }
  }
}

/// 加载内置模块——扫描 [builtinsDir] 下各子目录的 manifest.json 并注册。
///
/// 内置模块优先注册，插件模块可覆盖（同 id 先注册者生效）。
/// 自动调用 [discoverCapabilities] 检测每个模块的能力维度。
void loadBuiltinModules(String builtinsDir, ModuleRegistry registry) {
  final ids = <String>[];
  _scanDir(builtinsDir, (d, dirPath) {
    registry.register(d);
    ids.add(d.id);
    // 自动发现能力维度并注册
    final dims = discoverCapabilities(dirPath, descriptor: d);
    if (dims.isNotEmpty) {
      registry.setCapabilities(d.id, dims);
    }
  });
  Log().info('ModuleLoader: 加载 ${ids.length} 个内置模块',
      data: {'ids': ids});
}

/// 扫描目录下的 manifest.json，返回 [ModuleDescriptor] 列表（不启动进程）。
List<ModuleDescriptor> scanModules(String pluginsDir) {
  final descriptors = <ModuleDescriptor>[];
  _scanDir(pluginsDir, (d, _) => descriptors.add(d));
  Log().info('ModuleLoader: 发现 ${descriptors.length} 个模块',
      data: {'modules': descriptors.map((d) => d.id).toList()});
  return descriptors;
}

/// 扫描 + 注册 + 并行启动进程。等待全部进程就绪后返回。
Future<List<ModuleLoader>> scanAndLoadModules(
  String pluginsDir,
  ModuleRegistry registry, {
  String projectRoot = '',
}) async {
  final root = projectRoot.isNotEmpty ? projectRoot : Directory.current.path;
  final pending = <Future<void>>[];
  final loaders = <ModuleLoader>[];
  _scanDir(pluginsDir, (d, dirPath) {
    registry.register(d);
    // 自动发现能力维度并注册
    final dims = discoverCapabilities(dirPath, descriptor: d);
    if (dims.isNotEmpty) {
      registry.setCapabilities(d.id, dims);
    }
    if (d.process != null) {
      final loader = ModuleLoader(d, dirPath, projectRoot: root);
      loaders.add(loader);
      pending.add(loader.start());
    }
  });
  try {
    await Future.wait(pending).timeout(const Duration(seconds: 60));
  } on TimeoutException {
    Log().warn('ModuleLoader: 部分插件启动超时 (60s)');
  }
  return loaders;
}
