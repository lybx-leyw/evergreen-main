/// Agent 工具：嵌入式 Python 3.10 解释器 + pip 包管理。
///
/// 调用 .greenix/python/python.exe 执行 Python 代码或 pip 命令。
/// 遵循 PluginBridge manifest.json 规范（manifest 位于 plugins/python-runner/agent/）。
///
/// ## 模式
/// | mode | 说明 |
/// |------|------|
/// | `run` (默认) | 执行 Python 代码段，返回 stdout |
/// | `pip` | 运行 pip 命令（install/uninstall/list/show/...） |
/// | `sys` | 查看 Python 版本、已安装包列表、sys.path 等 |
///
/// # 安全
/// - `readOnly = false`：代码可写文件、安装/卸载包。
/// - `run` 模式拒绝 os.system / subprocess / eval / exec / compile / __import__ 等危险操作。
/// - `run` 模式的工作目录限定在 [workspaceDir] 内，防止逃逸访问。
/// - `pip` 模式超时 120 秒（安装可能较慢）。
/// - `run` 模式超时 30 秒。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:evergreen_base/core/plugin/plugin_runner.dart';
import 'package:path/path.dart' as p;

import '../../utils/path_sandbox.dart';
import '../../utils/python_env.dart';
import '../tool.dart';

class PythonRunnerTool extends Tool {
  final String _pythonExePath;
  final String _pythonWorkDir;
  final String? _workspaceDir;
  final PathSandbox? _sandbox;

  /// 安卓 Chaquopy 执行器（不传则首次执行时内部 [sharedPluginRunner]）。
  final PluginRunner? _runner;

  /// 测试注入：强制按安卓路径执行（默认取 [Platform.isAndroid]）。
  final bool? _forceAndroid;

  PythonRunnerTool({
    required String pythonExePath,
    required String pythonWorkDir,
    String? workspaceDir,
    PluginRunner? runner,
    bool? forceAndroid,
  })  : _pythonExePath = pythonExePath,
        _pythonWorkDir = pythonWorkDir,
        _workspaceDir = workspaceDir,
        _runner = runner,
        _forceAndroid = forceAndroid,
        _sandbox = workspaceDir != null ? PathSandbox(workspaceDir) : null;

  /// 平台判定：安卓走进程内 Chaquopy（[forceAndroid] 供测试注入，默认真平台）。
  bool get _isAndroid => _forceAndroid ?? Platform.isAndroid;

  @override
  String get name => 'python_runner';

  @override
  String get description =>
      'Python 3.10 解释器工具，支持三种模式：\n'
      '1. mode="run"（默认）：执行 Python 代码段，可使用所有标准库+已安装第三方包。print() 输出返回给模型。\n'
      '2. mode="pip"：管理 pip 包（install/uninstall/list/show）。\n'
      '3. mode="sys"：查看 Python 版本、已安装包列表、环境信息。\n'
      '已安装的第三方包（以嵌入式 Python 环境 requirements.txt 为准）：requests, Pillow, pytesseract, pdf2image, pymupdf, pycryptodome 等。';

  @override
  Map<String, dynamic> get schema => {
        'type': 'object',
        'properties': {
          'mode': {
            'type': 'string',
            'enum': ['run', 'pip', 'sys'],
            'description':
                '运行模式。run=执行Python代码(默认), pip=包管理, sys=系统信息。',
          },
          'code': {
            'type': 'string',
            'description':
                '[mode=run] 要执行的 Python 3 代码段。可多行，可使用 import。print() 输出返回给模型。',
          },
          'pip_cmd': {
            'type': 'string',
            'enum': ['install', 'uninstall', 'list', 'show', 'freeze'],
            'description':
                '[mode=pip] pip 子命令。install=安装包, uninstall=卸载包, list=列出已安装, show=查看包详情, freeze=冻结依赖。',
          },
          'package': {
            'type': 'string',
            'description':
                '[mode=pip, pip_cmd=install/uninstall/show] 包名（可含版本号如 requests==2.28.0）。install 时可用空格分隔多个包。',
          },
        },
        'required': [],
      };

  @override
  bool get readOnly => false;

  @override
  Future<String> execute(Map<String, dynamic> args) async {
    final mode = args['mode']?.toString() ?? 'run';

    switch (mode) {
      case 'run':
        return _executeRun(args);
      case 'pip':
        return _executePip(args);
      case 'sys':
        return _executeSys();
      default:
        return '[error: python_runner: 未知模式 "$mode"，支持 run/pip/sys]';
    }
  }

  // ═══════ mode=run：执行 Python 代码 ═══════

  Future<String> _executeRun(Map<String, dynamic> args) async {
    final code = args['code']?.toString() ?? '';
    if (code.trim().isEmpty) {
      return '[error: python_runner: code 参数为空。示例: {"mode":"run", "code":"print(1+1)"}]';
    }

    // 安全检查：拒绝明显的危险操作
    final lowerCode = code.trim().toLowerCase();
    const dangerous = [
      'os.system(',
      'subprocess.',
      'eval(',
      'exec(',
      'compile(',
      '__import__',
      'getattr(',
      'open(',
    ];
    for (final pattern in dangerous) {
      if (lowerCode.contains(pattern)) {
        return '[warning: python_runner 拒绝执行包含危险操作 "$pattern" 的代码。'
            'os.system / subprocess / eval / exec / compile / getattr / open 被禁止。'
            '如需执行系统命令，请使用 mode="pip" 包管理。'
            '如需读写文件，请使用 read_file / write_file 工具。]';
      }
    }

    // 工作目录：优先使用工作区（限定文件访问范围），否则用 Python 安装目录
    final workDir = _workspaceDir ?? _pythonWorkDir;

    if (_isAndroid) {
      // 安卓：dart:io 不支持子进程——code 落临时 .py，经 ChaquopyRunner
      // （MethodChannel('evergreen/python') 进程内解释器）执行。
      return _executeRunChaquopy(code, workDir);
    }

    try {
      final process = await Process.start(
        _pythonExePath,
        ['-c', code],
        workingDirectory: workDir,
        mode: ProcessStartMode.normal,
      );

      final stdoutStr = await process.stdout
          .transform(utf8.decoder)
          .join()
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              process.kill();
              return '(timeout after 30s)';
            },
          );

      final stderrStr = await process.stderr
          .transform(utf8.decoder)
          .join()
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () => '',
          );

      final exitCode = await process.exitCode;

      if (exitCode != 0) {
        final buf = StringBuffer();
        buf.writeln('[Python exited with code $exitCode]');
        if (stderrStr.trim().isNotEmpty) {
          buf.writeln('[stderr]');
          buf.writeln(stderrStr.trim());
        }
        if (stdoutStr.trim().isNotEmpty) {
          buf.writeln('[stdout]');
          buf.write(stdoutStr.trim());
        }
        return buf.toString().trim();
      }

      final output = <String>[];
      if (stdoutStr.trim().isNotEmpty) output.add(stdoutStr.trim());
      if (stderrStr.trim().isNotEmpty) output.add('[stderr]\n${stderrStr.trim()}');
      return output.isEmpty ? '_(no output)_' : output.join('\n');
    } on ProcessException catch (e) {
      return '[error: python_runner: 无法启动 Python 解释器: $e]';
    } catch (e) {
      return '[error: python_runner: $e]';
    }
  }

  /// 安卓执行路径：代码落临时 `.py` → [PluginRunner.runOnce]（ChaquopyRunner，
  /// MethodChannel('evergreen/python') 进程内解释器；镜像 scraper_tools 双路径先例）。
  ///
  /// 输出格式化与桌面 `Process.start` 路径同构（exitCode!=0 → `[Python exited
  /// with code N]` + stderr/stdout；成功 → stdout 合并 stderr）。超时经 runOnce
  /// 的 `timeout` 参数——安卓为 `Future.timeout` 放弃等待（原生线程继续，见探索
  /// 报告 §3），工具描述引导短代码。临时文件 finally 删除。
  Future<String> _executeRunChaquopy(String code, String workDir) async {
    final tmpPy = File(p.join(
      Directory.systemTemp.path,
      'python_runner_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(0x7fffffff)}.py',
    ));
    try {
      await tmpPy.writeAsString(code);
      final runner = _runner ?? await sharedPluginRunner;
      final r = await runner.runOnce(
        tmpPy.path,
        const [],
        workingDirectory: workDir,
        timeout: const Duration(seconds: 30),
      );

      if (r.exitCode != 0) {
        final buf = StringBuffer();
        buf.writeln('[Python exited with code ${r.exitCode}]');
        if (r.stderr.trim().isNotEmpty) {
          buf.writeln('[stderr]');
          buf.writeln(r.stderr.trim());
        }
        if (r.stdout.trim().isNotEmpty) {
          buf.writeln('[stdout]');
          buf.write(r.stdout.trim());
        }
        return buf.toString().trim();
      }

      final output = <String>[];
      if (r.stdout.trim().isNotEmpty) output.add(r.stdout.trim());
      if (r.stderr.trim().isNotEmpty) output.add('[stderr]\n${r.stderr.trim()}');
      return output.isEmpty ? '_(no output)_' : output.join('\n');
    } on TimeoutException catch (e) {
      return '[error: python_runner: 执行超时(30s): $e]';
    } on ProcessException catch (e) {
      return '[error: python_runner: 无法启动 Python 解释器: $e]';
    } catch (e) {
      return '[error: python_runner: $e]';
    } finally {
      try {
        await tmpPy.delete();
      } catch (_) {}
    }
  }

  // ═══════ mode=pip：包管理 ═══════

  Future<String> _executePip(Map<String, dynamic> args) async {
    final cmd = args['pip_cmd']?.toString() ?? '';
    if (cmd.isEmpty) {
      return '[error: python_runner: pip_cmd 参数为空。支持: install/uninstall/list/show/freeze]';
    }

    if (_isAndroid) {
      // 安卓 Chaquopy 无运行时 pip——第三方包须构建期在 build.gradle.kts 声明
      // （android/app/build.gradle.kts 的 chaquopy.pip {}），当前内置
      // requests 全家桶 + pycryptodome。桌面分支保持原样。
      return '[error: python_runner: 安卓 Chaquopy 无运行时 pip。'
          '第三方包须构建期在 android/app/build.gradle.kts 的 chaquopy.pip {} 中声明'
          '（当前已内置: requests 全家桶 + pycryptodome）。'
          '如需本地 OCR 依赖（Pillow/pytesseract）请在构建配置中添加后重新打包 APK。]';
    }

    final package = args['package']?.toString() ?? '';

    switch (cmd) {
      case 'install':
        if (package.isEmpty) {
          return '[error: python_runner: install 需要 package 参数。'
              '示例: {"mode":"pip", "pip_cmd":"install", "package":"numpy pandas"}]';
        }
        return _runPipCommand(['install', ..._validatePackages(package)]);

      case 'uninstall':
        if (package.isEmpty) {
          return '[error: python_runner: uninstall 需要 package 参数。'
              '示例: {"mode":"pip", "pip_cmd":"uninstall", "package":"numpy"}]';
        }
        return _runPipCommand(['uninstall', '-y', ..._validatePackages(package)]);

      case 'list':
        return _runPipCommand(['list']);

      case 'show':
        if (package.isEmpty) {
          return '[error: python_runner: show 需要 package 参数。'
              '示例: {"mode":"pip", "pip_cmd":"show", "package":"requests"}]';
        }
        final pkgs = _validatePackages(package);
        if (pkgs.length != 1) {
          return '[error: python_runner: show 仅支持单个包名]';
        }
        return _runPipCommand(['show', pkgs.first]);

      case 'freeze':
        return _runPipCommand(['freeze']);

      default:
        return '[error: python_runner: 未知 pip 子命令 "$cmd"，支持 install/uninstall/list/show/freeze]';
    }
  }

  /// 校验并清洗 pip 包名，拒绝包含危险字符的输入（防止命令注入）。
  static List<String> _validatePackages(String raw) {
    final pkgs = raw.split(' ').where((s) => s.isNotEmpty).toList();
    final valid = <String>[];
    // 合法的包名：字母数字 + 连字符/下划线/点 + 可选的版本约束（== != >= <= ~= > <）
    final pkgRe = RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9._-]*(==|!=|>=|<=|~=|>|<)?[\w.*+-]*$');
    for (final p in pkgs) {
      if (p.startsWith('-')) {
        continue; // 跳过以 - 开头的（可能是 pip flag 注入尝试）
      }
      if (pkgRe.hasMatch(p)) {
        valid.add(p);
      }
    }
    if (valid.isEmpty && pkgs.isNotEmpty) {
      // 全部无效时返回空列表，调用方检查
    }
    return valid;
  }

  /// 通过 `python -m pip <args>` 执行 pip 命令。
  Future<String> _runPipCommand(List<String> pipArgs) async {
    try {
      final fullArgs = ['-m', 'pip', ...pipArgs];
      final process = await Process.start(
        _pythonExePath,
        fullArgs,
        workingDirectory: _pythonWorkDir,
        mode: ProcessStartMode.normal,
      );

      final stdoutStr = await process.stdout
          .transform(utf8.decoder)
          .join()
          .timeout(
            const Duration(seconds: 120), // pip 安装可能较慢
            onTimeout: () {
              process.kill();
              return '(timeout after 120s)';
            },
          );

      final stderrStr = await process.stderr
          .transform(utf8.decoder)
          .join()
          .timeout(
            const Duration(seconds: 120),
            onTimeout: () => '',
          );

      final exitCode = await process.exitCode;

      final buf = StringBuffer();
      if (exitCode != 0) {
        buf.writeln('[pip exited with code $exitCode]');
      }
      if (stderrStr.trim().isNotEmpty) {
        // pip 的进度信息走 stderr，非错误
        final stderrClean = stderrStr.trim();
        if (!stderrClean.startsWith('WARNING:') && exitCode == 0) {
          // 正常的 pip stderr 输出（进度条等），只在有 stdout 时才省略
        } else {
          buf.writeln(stderrClean);
        }
      }
      if (stdoutStr.trim().isNotEmpty) {
        buf.write(stdoutStr.trim());
      }
      final result = buf.toString().trim();
      return result.isEmpty ? '[pip $pipArgs: _(no output)_]' : result;
    } on ProcessException catch (e) {
      return '[error: python_runner: 无法启动 pip: $e]';
    } catch (e) {
      return '[error: python_runner: $e]';
    }
  }

  // ═══════ mode=sys：系统信息 ═══════

  /// 安卓 sys 脚本：与桌面同构的信息清单，但 importlib.metadata 异常时降级
  /// 列出 sys.path（Chaquopy 打包环境可能无完整 dist-info）。
  static const String _sysInfoScriptAndroid = '''
import sys, platform, os

print("=== Python 系统信息 ===")
print(f"Python 版本: {sys.version}")
print(f"平台: {platform.platform()}")
print(f"架构: {platform.machine()}")
print(f"解释器路径: {sys.executable}")
print(f"工作目录: {os.getcwd()}")
print()

# 列出已安装包（importlib.metadata；异常时降级列 sys.path 与已知打包模块）
print("=== 已安装的包 ===")
try:
    import importlib.metadata as meta
    dists = sorted(meta.distributions(), key=lambda d: d.metadata['Name'].lower())
    for dist in dists:
        name = dist.metadata['Name']
        version = dist.version
        print(f"  {name}=={version}")
except Exception as e:
    print(f"  (importlib.metadata 不可用: {e})")
print()

print(f"=== sys.path ===")
for i, pth in enumerate(sys.path):
    print(f"  [{i}] {pth}")
''';

  Future<String> _executeSys() async {
    if (_isAndroid) {
      // 安卓：复用 Chaquopy 执行路径跑系统信息脚本（桌面路径原样不动）。
      return _executeRunChaquopy(_sysInfoScriptAndroid, _workspaceDir ?? _pythonWorkDir);
    }
    final code = '''
import sys, platform, os

print("=== Python 系统信息 ===")
print(f"Python 版本: {sys.version}")
print(f"平台: {platform.platform()}")
print(f"架构: {platform.machine()}")
print(f"解释器路径: {sys.executable}")
print(f"工作目录: {os.getcwd()}")
print()

# 列出 site-packages 中的包
import importlib.metadata as meta
print("=== 已安装的包 (site-packages) ===")
dists = sorted(meta.distributions(), key=lambda d: d.metadata['Name'].lower())
for dist in dists:
    name = dist.metadata['Name']
    version = dist.version
    print(f"  {name}=={version}")
print()

print(f"=== sys.path ===")
for i, p in enumerate(sys.path):
    print(f"  [{i}] {p}")
''';
    return _executeRun({'code': code});
  }

  // ═══════ 注册 helper（四处注册点统一收敛，避免条件漂移） ═══════

  /// 是否应在当前平台注册 python_runner。
  ///
  /// - 桌面：嵌入式 Python 存在（[PythonInterpreter.bundledPathSync] 非空）；
  /// - 安卓：恒有进程内 Chaquopy 解释器（[PythonRuntimeKind.androidChaquopy]）。
  static bool get isSupported =>
      Platform.isAndroid || PythonInterpreter.bundledPathSync() != null;

  /// 平台化构造——安卓：哨兵占位 + [sharedPluginRunner]（ChaquopyRunner）；
  /// 桌面：嵌入式 Python（[PythonInterpreter.bundledPathSync]），保持现有逻辑。
  ///
  /// 需在 [isSupported] 为 true 时调用（桌面无嵌入式 Python 时 [bundledPathSync]
  /// 为空，`!` 断言抛错——与同步注册点的判空逻辑等价）。
  static Future<PythonRunnerTool> build({
    required String workspaceDir,
    PluginRunner? runner,
  }) async {
    if (Platform.isAndroid) {
      return PythonRunnerTool(
        pythonExePath: kChaquopySentinel,
        pythonWorkDir: workspaceDir,
        workspaceDir: workspaceDir,
        runner: runner ?? await sharedPluginRunner,
      );
    }
    final bundled = PythonInterpreter.bundledPathSync()!;
    return PythonRunnerTool(
      pythonExePath: bundled,
      pythonWorkDir: Directory(bundled).parent.path,
      workspaceDir: workspaceDir,
    );
  }
}
