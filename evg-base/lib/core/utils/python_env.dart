/// Python 环境管理——统一解释器路径发现（单例收敛）、依赖安装。
///
/// # 统一解释器路径（唯一事实源）
///
/// 全仓 Python 解释器发现统一收敛到 [PythonInterpreter.resolve]，解析顺序：
///
/// 1. [configuredPath]——调用方显式指定（用户配置 / 嵌入式候选，文件存在才采纳）
/// 2. Greenix 嵌入式目录——[bindGreenixPythonDir] 绑定为
///    `greenix_path.greenixPythonDir`（**单一真理来源**；未绑定时按历史行为
///    回退 `cwd/.greenix/python`，见 [_defaultGreenixPythonDir]）
/// 3. 系统 PATH——`python3` → `python` → `py -3`
/// 4. 安卓——进程内 Chaquopy 解释器（[PythonRuntimeKind.androidChaquopy]，
///    哨兵常量 [kChaquopySentinel]，实际执行经 `ChaquopyRunner`/MethodChannel）
///
/// 兼容层：[resolvePythonExe] 保留旧签名（返回可执行路径 / 哨兵 / null），
/// 已收敛为对 [PythonInterpreter.resolveExePath] 的薄包装。
///
/// ⚠️ 本文件为子包（agent/data 等）的同步副本源——修改后须同步
/// `lib/core/agent/lib/core/utils/python_env.dart` 与
/// `lib/core/data/lib/core/utils/python_env.dart`。
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:evergreen_base/core/log.dart';

/// Android Chaquopy 哨兵——[PythonRuntime.legacyExePath] 在安卓返回此值，
/// 标识「进程内解释器」（**不可**作为可执行命令）。调用方应优先检查
/// [PythonRuntime.isAndroidChaquopy]，而不是比较字符串。
const String kChaquopySentinel = 'chaquopy';

/// Python 运行时种类（统一解释器路径的第一事实源）。
enum PythonRuntimeKind {
  /// 嵌入式/用户配置的 Python（`.greenix/python/python.exe` 或 configuredPath）。
  bundled,

  /// 系统 PATH 上的 `python3` / `python` / `py -3`。
  system,

  /// 安卓进程内 Chaquopy 解释器（非子进程，经 MethodChannel 执行）。
  androidChaquopy,

  /// 未找到任何可用 Python。
  none,
}

/// 一次解释器解析的结构化结果。
class PythonRuntime {
  final PythonRuntimeKind kind;

  /// 解释器可执行文件路径；[kind] 为 [PythonRuntimeKind.system] 时是命令名
  /// （`python`/`python3`/`py`）；[PythonRuntimeKind.androidChaquopy]/[none]
  /// 时为 null。
  final String? exePath;

  const PythonRuntime({required this.kind, this.exePath});

  const PythonRuntime.none()
      : kind = PythonRuntimeKind.none,
        exePath = null;

  bool get isAvailable => kind != PythonRuntimeKind.none;

  bool get isAndroidChaquopy => kind == PythonRuntimeKind.androidChaquopy;

  bool get isBundled => kind == PythonRuntimeKind.bundled;

  /// 兼容旧契约：安卓返回哨兵常量 [kChaquopySentinel]（若直接当命令执行会
  /// 失败——应检查 [isAndroidChaquopy] 并走执行抽象），其余返回解释器路径。
  String? get legacyExePath => isAndroidChaquopy ? kChaquopySentinel : exePath;

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        if (exePath != null) 'exePath': exePath,
      };

  @override
  String toString() =>
      'PythonRuntime(${kind.name}${exePath != null ? ', $exePath' : ''})';
}

/// Greenix 嵌入式 Python 目录提供者（无 Flutter 依赖的注入点）。
typedef GreenixPythonDirProvider = String Function();

GreenixPythonDirProvider _greenixPythonDirProvider = _defaultGreenixPythonDir;

/// 未绑定时按历史行为：`cwd/.greenix/python`（开发模式 cwd = 项目根）。
String _defaultGreenixPythonDir() =>
    p.join(Directory.current.path, '.greenix', 'python');

/// 绑定 Greenix Python 目录——**消除双真理来源**。
///
/// app 启动（`app_bootstrap` 的 `initGreenixPaths()` 之后）绑定为
/// `greenix_path.greenixPythonDir`（已安装场景指向可执行文件目录下的
/// `.greenix/python`，开发场景退回项目根 `.greenix/python`）。
/// 子包测试未绑定时保持 [Directory.current] 历史行为。绑定会清空解析缓存。
void bindGreenixPythonDir(GreenixPythonDirProvider provider) {
  _greenixPythonDirProvider = provider;
  PythonInterpreter.resetForTest();
}

/// 统一 Python 解释器发现（单例收敛）。
///
/// 全仓解释器路径的唯一事实源：`resolvePythonExe` 兼容包装、
/// [PythonRuntime.bundledPathSync] 同步探测均收敛到此。
class PythonInterpreter {
  PythonInterpreter._();

  static PythonInterpreter? _instance;

  /// 无参解析的成功结果缓存（失败不缓存，允许重试；[resetForTest] 清空）。
  static PythonRuntime? _cachedNoConfig;

  /// 单例——全仓唯一解释器解析入口。
  static PythonInterpreter get instance => _instance ??= PythonInterpreter._();

  /// 按统一顺序解析 Python 运行时。
  ///
  /// [configuredPath] 非空时跳过缓存并优先使用（文件存在才采纳）。
  /// 无参解析成功结果缓存，失败不缓存——成功路径免重复子进程探测，
  /// 失败路径保持旧 `resolvePythonExe` 每次重探的可恢复行为。
  Future<PythonRuntime> resolve({String? configuredPath}) async {
    if (configuredPath == null || configuredPath.isEmpty) {
      final cached = _cachedNoConfig;
      if (cached != null) return cached;
    }
    final rt = await _doResolve(configuredPath);
    if ((configuredPath == null || configuredPath.isEmpty) && rt.isAvailable) {
      _cachedNoConfig = rt;
    }
    return rt;
  }

  /// 兼容旧签名：返回可执行路径；安卓返回 [kChaquopySentinel]；无可用返回 null。
  Future<String?> resolveExePath({String? configuredPath}) async =>
      (await resolve(configuredPath: configuredPath)).legacyExePath;

  /// 同步探测嵌入式 Python（Greenix 目录内 `python.exe`）。
  ///
  /// 供无法 await 的同步组装点（如 Riverpod provider 构造）使用；
  /// 等价于 `await resolve()` 且 `kind == bundled` 的同步版本。
  static String? bundledPathSync() {
    final candidate = _greenixPyCandidate();
    return File(candidate).existsSync() ? candidate : null;
  }

  /// 仅供测试：清空单例与成功缓存（[bindGreenixPythonDir] 后也会触发）。
  static void resetForTest() {
    _instance = null;
    _cachedNoConfig = null;
  }

  static String _greenixPyCandidate() =>
      p.normalize(p.absolute(p.join(_greenixPythonDirProvider(), 'python.exe')));

  static Future<PythonRuntime> _doResolve(String? configuredPath) async {
    // ① 调用方显式指定路径（嵌入式 Python 统一走 .greenix/python/python.exe）
    if (configuredPath != null && configuredPath.isNotEmpty) {
      final configuredFile = File(configuredPath);
      if (await configuredFile.exists()) {
        Log().info('PythonEnv: using configured Python',
            data: {'path': configuredPath});
        return PythonRuntime(
            kind: PythonRuntimeKind.bundled, exePath: configuredPath);
      }
    }

    // ② Greenix 嵌入式目录（单一真理来源：绑定的 greenixPythonDir）
    final greenixPy = _greenixPyCandidate();
    try {
      if (await File(greenixPy).exists()) {
        Log().info('PythonEnv: using greenix embedded Python',
            data: {'path': greenixPy});
        return PythonRuntime(kind: PythonRuntimeKind.bundled, exePath: greenixPy);
      }
    } catch (_) {}

    // ③ 系统 PATH 回退
    for (final candidate in ['python3', 'python', 'py']) {
      try {
        final checkArgs =
            candidate == 'py' ? ['-3', '--version'] : ['--version'];
        final result = await Process.run(candidate, checkArgs)
            .timeout(const Duration(seconds: 10));
        if (result.exitCode == 0) {
          Log().info('PythonEnv: using system Python', data: {'path': candidate});
          return PythonRuntime(kind: PythonRuntimeKind.system, exePath: candidate);
        }
      } catch (_) {}
    }

    // ④ 安卓：进程内 Chaquopy 解释器（哨兵收敛为枚举 + 常量，实际执行
    //    经 ChaquopyRunner/MethodChannel 完成，桌面不应触达此分支）。
    if (Platform.isAndroid) {
      Log().info('PythonEnv: using chaquopy (in-process interpreter)');
      return const PythonRuntime(kind: PythonRuntimeKind.androidChaquopy);
    }

    Log().warn('PythonEnv: no Python found');
    return const PythonRuntime.none();
  }
}

/// 按优先级自动发现 Python 可执行文件路径（兼容层，行为不变）。
///
/// 1. [configuredPath] 用户/项目指定的路径（如 `.greenix/python/python.exe`）
/// 2. Greenix 嵌入式目录（[bindGreenixPythonDir] 绑定为 `greenixPythonDir`）
/// 3. 系统 PATH：`python3` → `python` → `py -3`
/// 4. 安卓：返回哨兵 [kChaquopySentinel]（进程内解释器标识）
///
/// 新代码请优先使用 [PythonInterpreter.instance.resolve]（结构化结果）。
Future<String?> resolvePythonExe({String? configuredPath}) =>
    PythonInterpreter.instance.resolveExePath(configuredPath: configuredPath);

/// 用已解析的 Python 解释器安装一组第三方包（M6 · 方案 A）。
///
/// [packages] 为 pip 可识别的包名/约束（如 `aiohttp`、`selenium>=4.0`）。
/// 返回成功与否；失败原因经 [Log] 记录，不抛异常（调用方据此给出可读提示）。
///
/// 用于插件安装阶段：manifest 声明 `requirements`，安装器据此补齐嵌入式
/// Python 缺的第三方依赖（如 zjucrawler 的 aiohttp/selenium 等）。
///
/// ⚠️ 仅桌面可用：安卓 Chaquopy 无 pip/Process，第三方依赖须构建期打进 APK。
Future<bool> pipInstallPackages(
  List<String> packages, {
  String? pythonExe,
  Duration timeout = const Duration(seconds: 300),
}) async {
  if (packages.isEmpty) return true;
  final exe = pythonExe ?? await PythonInterpreter.instance.resolveExePath();
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
