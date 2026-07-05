/// Agent 工具：嵌入式 Python 3.10 解释器 + pip 包管理。
///
/// 调用 scripts/python/python.exe 执行 Python 代码或 pip 命令。
/// 遵循 PluginBridge manifest.json 规范（manifest 位于 plugins/python-runner/agent/）。
///
/// ## 模式
/// | mode | 说明 |
/// |------|------|
/// | `run` (默认) | 执行 Python 代码段，返回 stdout |
/// | `pip` | 运行 pip 命令（install/uninstall/list/show/...） |
/// | `sys` | 查看 Python 版本、已安装包列表、sys.path 等 |
///
/// ## 安全
/// - `readOnly = false`：代码可写文件、安装/卸载包。
/// - `run` 模式拒绝 os.system / subprocess / eval 危险操作。
/// - `pip` 模式超时 120 秒（安装可能较慢）。
/// - `run` 模式超时 30 秒。
library;

import 'dart:convert';
import 'dart:io';

import '../tool.dart';

class PythonRunnerTool extends Tool {
  final String _pythonExePath;
  final String _pythonWorkDir;

  PythonRunnerTool({
    required String pythonExePath,
    required String pythonWorkDir,
  })  : _pythonExePath = pythonExePath,
        _pythonWorkDir = pythonWorkDir;

  @override
  String get name => 'python_runner';

  @override
  String get description =>
      'Python 3.10 解释器工具，支持三种模式：\n'
      '1. mode="run"（默认）：执行 Python 代码段，可使用所有标准库+已安装第三方包。print() 输出返回给模型。\n'
      '2. mode="pip"：管理 pip 包（install/uninstall/list/show）。\n'
      '3. mode="sys"：查看 Python 版本、已安装包列表、环境信息。\n'
      '已安装的第三方包：requests, Pillow, PyInstaller, pytesseract, pdf2image, packaging 等。';

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
      '__import__("os")',
      'eval(',
    ];
    for (final pattern in dangerous) {
      if (lowerCode.contains(pattern)) {
        return '[warning: python_runner 拒绝执行包含危险操作 "$pattern" 的代码。'
            'os.system / subprocess / eval 被禁止。'
            '如需执行系统命令，请使用 mode="pip" 进行包管理操作。]';
      }
    }

    try {
      final process = await Process.start(
        _pythonExePath,
        ['-c', code],
        workingDirectory: _pythonWorkDir,
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

  // ═══════ mode=pip：包管理 ═══════

  Future<String> _executePip(Map<String, dynamic> args) async {
    final cmd = args['pip_cmd']?.toString() ?? '';
    if (cmd.isEmpty) {
      return '[error: python_runner: pip_cmd 参数为空。支持: install/uninstall/list/show/freeze]';
    }

    final package = args['package']?.toString() ?? '';

    switch (cmd) {
      case 'install':
        if (package.isEmpty) {
          return '[error: python_runner: install 需要 package 参数。'
              '示例: {"mode":"pip", "pip_cmd":"install", "package":"numpy pandas"}]';
        }
        return _runPipCommand(['install', ...package.split(' ').where((s) => s.isNotEmpty)]);

      case 'uninstall':
        if (package.isEmpty) {
          return '[error: python_runner: uninstall 需要 package 参数。'
              '示例: {"mode":"pip", "pip_cmd":"uninstall", "package":"numpy"}]';
        }
        return _runPipCommand(['uninstall', '-y', ...package.split(' ').where((s) => s.isNotEmpty)]);

      case 'list':
        return _runPipCommand(['list']);

      case 'show':
        if (package.isEmpty) {
          return '[error: python_runner: show 需要 package 参数。'
              '示例: {"mode":"pip", "pip_cmd":"show", "package":"requests"}]';
        }
        return _runPipCommand(['show', package]);

      case 'freeze':
        return _runPipCommand(['freeze']);

      default:
        return '[error: python_runner: 未知 pip 子命令 "$cmd"，支持 install/uninstall/list/show/freeze]';
    }
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

  Future<String> _executeSys() async {
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
}
