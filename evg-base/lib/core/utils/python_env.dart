/// Python 环境管理——检查依赖、自动安装、OCR 子进程执行。
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:evergreen_base/core/log.dart';

/// 按优先级自动发现 Python 可执行文件路径。
///
/// 1. [configuredPath] 用户/项目指定的路径（如 `.greenix/python/python.exe`）
/// 2. `.greenix/python/python.exe`（嵌入式 Python，应用数据目录）
/// 3. 系统 PATH：`python3` → `python` → `py -3`
/// 4. 安卓：Chaquopy 进程内解释器
Future<String?> resolvePythonExe({String? configuredPath}) async {
  // ① 优先使用调用方指定的路径（嵌入式 Python 统一走 `.greenix/python/python.exe`）
  if (configuredPath != null && configuredPath.isNotEmpty) {
    final configuredFile = File(configuredPath);
    if (await configuredFile.exists()) {
      Log().info('PythonEnv: using configured Python', data: {'path': configuredPath});
      return configuredPath;
    }
  }

  // ② 应用数据目录下的嵌入式 Python（`.greenix/python/python.exe`）
  // 用内联 cwd 路径（子包测试隔离，无法 import greenix_path；桌面 cwd 通常即安装目录）。
  final greenixPy = p.join(Directory.current.path, '.greenix', 'python', 'python.exe');
  try {
    if (await File(greenixPy).exists()) {
      Log().info('PythonEnv: using greenix embedded Python', data: {'path': greenixPy});
      return greenixPy;
    }
  } catch (_) {}

  // ③ 系统 PATH 回退
  for (final candidate in ['python3', 'python', 'py']) {
    try {
      final checkArgs = candidate == 'py' ? ['-3', '--version'] : ['--version'];
      final result = await Process.run(candidate, checkArgs).timeout(const Duration(seconds: 10));
      if (result.exitCode == 0) {
        Log().info('PythonEnv: using system Python', data: {'path': candidate});
        return candidate;
      }
    } catch (_) {}
  }

  // ④ 安卓：进程内 Chaquopy 解释器（不走 Process）。
  // 返回哨兵字符串 'chaquopy' 仅作标识；实际执行由 [ChaquopyRunner]
  // 经 MethodChannel 完成。桌面不应触达此分支。
  if (Platform.isAndroid) {
    Log().info('PythonEnv: using chaquopy (in-process interpreter)');
    return 'chaquopy';
  }

  Log().warn('PythonEnv: no Python found');
  return null;
}

/// 运行 OCR 相关 Python 子进程。
Future<ProcessResult> runOcrProcess(
  String executable, List<String> arguments, {String? workingDirectory}) {
  return Process.run(executable, arguments,
    workingDirectory: workingDirectory, includeParentEnvironment: true);
}

/// 用已解析的 Python 解释器安装一组第三方包（M6 · 方案 A）。
///
/// [packages] 为 pip 可识别的包名/约束（如 `aiohttp`、`selenium>=4.0`）。
/// 返回成功与否；失败原因经 [Log] 记录，不抛异常（调用方据此给出可读提示）。
///
/// 用于插件安装阶段：manifest 声明 `requirements`，安装器据此补齐嵌入式
/// Python 缺的第三方依赖（如 zjucrawler 的 aiohttp/selenium 等）。
Future<bool> pipInstallPackages(
  List<String> packages, {
  String? pythonExe,
  Duration timeout = const Duration(seconds: 300),
}) async {
  if (packages.isEmpty) return true;
  final exe = pythonExe ?? await resolvePythonExe();
  if (exe == null) {
    Log().warn('PythonEnv: pip install 跳过（未找到 Python）',
        data: {'packages': packages});
    return false;
  }
  try {
    final result = await Process.run(
      exe,
      ['-m', 'pip', 'install', ...packages],
      includeParentEnvironment: true,
    ).timeout(timeout);
    final ok = result.exitCode == 0;
    Log().info(
      ok ? 'PythonEnv: pip install 成功' : 'PythonEnv: pip install 失败',
      data: {
        'packages': packages,
        'exitCode': result.exitCode,
        if (!ok) 'stderr': (result.stderr as String).toString(),
      },
    );
    return ok;
  } catch (e) {
    Log().warn('PythonEnv: pip install 异常', data: {'error': e.toString()});
    return false;
  }
}

/// Python 依赖管理。
class PythonEnv {
  final String? _configuredPython;
  final String requirementsPath;

  PythonEnv({String? python, String? requirements})
    : _configuredPython = python,
      requirementsPath = requirements ??
          p.join(Directory.current.path, '.greenix', 'scripts', 'requirements.txt');

  Future<String?> get pythonExe async =>
      await resolvePythonExe(configuredPath: _configuredPython);

  Future<bool> checkPython() async {
    try {
      final exe = await pythonExe;
      if (exe == null) return false;
      final result = await Process.run(exe, ['--version']).timeout(const Duration(seconds: 10));
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// 检查 OCR 依赖是否已安装。返回缺失的包名。
  Future<String?> checkDeps() async {
    final exe = await pythonExe;
    if (exe == null) return 'python (未找到 Python)';

    const packages = <String, String>{
      'pytesseract': 'import pytesseract',
      'Pillow': 'from PIL import Image',
      'requests': 'import requests',
      'pdf2image': 'from pdf2image import convert_from_path',
    };

    for (final entry in packages.entries) {
      try {
        final result = await Process.run(exe, ['-c', entry.value]).timeout(const Duration(seconds: 10));
        if (result.exitCode != 0) return entry.key;
      } catch (_) {
        return entry.key;
      }
    }
    return null;
  }

  /// 自动安装 OCR 依赖。
  Future<bool> installDeps({void Function(String pkg, bool success)? onProgress}) async {
    final exe = await pythonExe;
    if (exe == null) return false;
    if (!await File(requirementsPath).exists()) return false;

    try {
      final result = await Process.run(exe, ['-m', 'pip', 'install', '-r', requirementsPath])
          .timeout(const Duration(seconds: 120));
      final success = result.exitCode == 0;
      onProgress?.call('requirements.txt', success);
      return success;
    } catch (_) {
      onProgress?.call('pip', false);
      return false;
    }
  }

  /// 一步检查并安装 OCR 环境。
  Future<String?> ensureReady({void Function(String msg)? onProgress}) async {
    onProgress?.call('检查 Python 环境...');

    if (_configuredPython != null && _configuredPython!.isNotEmpty) {
      if (!await File(_configuredPython!).exists()) {
        return '未找到 Python ($_configuredPython)，请确认路径正确';
      }
    }

    final hasPython = await checkPython();
    if (!hasPython) {
      final exe = await pythonExe;
      return '未找到 Python (${exe ?? 'python'})，请安装 Python 3.8+';
    }

    onProgress?.call('检查 OCR 依赖...');
    final missing = await checkDeps();
    if (missing == null) return null;

    onProgress?.call('正在安装 $missing...');
    final installed = await installDeps();
    if (!installed) {
      return 'OCR 依赖安装失败，请手动执行: pip install -r "$requirementsPath"';
    }

    final stillMissing = await checkDeps();
    if (stillMissing != null) return '依赖 $stillMissing 安装后仍不可用，请手动安装';

    return null;
  }
}
