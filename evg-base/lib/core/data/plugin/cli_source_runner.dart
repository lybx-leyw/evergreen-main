/// 模型一（CLI 一次性脚本）**统一执行器**——`data-source` 与 `file-source` 共用。
///
/// 设计依据：仓库 A-P2「单真相源」经验——同一份 CLI 调用/解析/错误分类契约
/// **只能有一处实现**，否则两类插件必然漂移（错误文案、超时语义、exitCode
/// 优先级、error JSON 处理各自演化）。
///
/// # 契约（与 `data-plugin-protocol-v1.md` §6.2 一致）
/// | 项 | 行为 |
/// | --- | --- |
/// | 命令行 | `[python] <script> --type <typeArg> --project-root <> --greenix-config <>` |
/// | 工作目录 | `<pluginDir>/data` 或 `<pluginDir>/files`（由调用方传入） |
/// | stdin | 不写入 |
/// | stdout | 必须是单个 JSON 对象（顶层 Map） |
/// | `exitCode != 0` | 失败；文案取 stderr，**若 stdout 是含 `error` 的 JSON 则优先取其值** |
/// | `exitCode == 0` + `error` 键 | 失败（取其值） |
/// | stderr | **不是**错误信号（成功时仅作诊断日志） |
/// | 超时 | kill 子进程并抛 |
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:evergreen_base/core/log.dart';
import 'package:evergreen_base/core/plugin/plugin_runner.dart';
import 'package:evergreen_base/core/utils/greenix_path.dart';

/// 执行一次 CLI 数据源脚本，返回解析后的 stdout JSON。
///
/// 失败一律抛 [Exception]（调用方/中枢落到 `lastError`），与既有内联实现等价。
Future<Map<String, dynamic>> runCliSource({
  /// 脚本绝对路径。
  required String scriptPath,

  /// 传给 `--type` 的值（`typeArg ?? name`）。
  required String typeArg,

  /// 传给 `--project-root` 的值。
  required String projectRoot,

  /// 子进程工作目录（`<pluginDir>/data` 或 `<pluginDir>/files`）。
  required String workingDirectory,

  /// `native` / `python`。
  required String runtime,

  /// 生效超时（per-type 覆盖或全局默认）。
  required Duration timeout,

  /// 日志用：插件目录名。
  required String pluginId,

  /// 日志/文案用：数据源名称。
  required String name,

  /// 日志/文案用：脚本文件名（非绝对路径）。
  required String script,

  /// 插件类型标签（`data-source` / `file-source`），仅用于日志。
  String kind = 'data-source',
}) async {
  final sw = Stopwatch()..start();
  Log().info('数据源拉取开始', data: {
    'kind': kind,
    'plugin': pluginId,
    'name': name,
    'script': scriptPath,
    'args': [
      '--type',
      typeArg,
      '--project-root',
      projectRoot,
      '--greenix-config',
      greenixConfigPath
    ]
  });

  final runner = await sharedPluginRunner;
  RunResult res;
  try {
    res = await runner.runOnce(
      scriptPath,
      [
        '--type',
        typeArg,
        '--project-root',
        projectRoot,
        '--greenix-config',
        greenixConfigPath
      ],
      workingDirectory: workingDirectory,
      runtime: runtime,
      timeout: timeout,
    );
  } on TimeoutException {
    Log().error('数据源拉取超时', data: {
      'kind': kind,
      'plugin': pluginId,
      'name': name,
      'script': script,
      'timeoutSeconds': timeout.inSeconds,
    });
    throw Exception(
        '数据脚本 "$script" 执行超时（>${timeout.inSeconds}s），已终止子进程');
  } on ProcessException catch (e) {
    debugPrint('[DataSource] ❌ 无法启动脚本 $script: ${e.message}');
    Log().error('数据源拉取失败（无法启动脚本）', data: {
      'kind': kind,
      'plugin': pluginId,
      'name': name,
      'script': script,
      'error': e.message
    });
    throw Exception('无法启动数据脚本 "$script": ${e.message}');
  }

  final ProcessResult result =
      ProcessResult(0, res.exitCode, res.stdout, res.stderr);
  final elapsedMs = sw.elapsedMilliseconds;
  final stdoutRaw = result.stdout as String;
  final stderrRaw = (result.stderr as String).trim();
  debugPrint('[DataSource] $name exitCode=${result.exitCode}, '
      'elapsed=${elapsedMs}ms, '
      'stdoutLen=${stdoutRaw.length}, stderrLen=${stderrRaw.length}');

  if (result.exitCode != 0) {
    String errMsg =
        stderrRaw.isNotEmpty ? stderrRaw : '$script 异常退出 (code ${result.exitCode})';
    try {
      final stdoutJson = jsonDecode(stdoutRaw) as Map<String, dynamic>;
      if (stdoutJson.containsKey('error')) {
        errMsg = stdoutJson['error'] as String? ?? errMsg;
      }
    } catch (_) {}
    debugPrint('[DataSource] ❌ $name exitCode!=0: '
        'stderr=${stderrRaw.length > 200 ? stderrRaw.substring(0, 200) : stderrRaw}, '
        'stdout=${stdoutRaw.length > 200 ? stdoutRaw.substring(0, 200) : stdoutRaw}');
    Log().error('数据源拉取失败（exitCode != 0）', data: {
      'kind': kind,
      'plugin': pluginId,
      'name': name,
      'exitCode': result.exitCode,
      'elapsedMs': elapsedMs,
      'stderr': stderrRaw.length > 800 ? '${stderrRaw.substring(0, 800)}…' : stderrRaw,
      'stdoutTail':
          stdoutRaw.length > 300 ? stdoutRaw.substring(0, 300) : stdoutRaw,
    });
    throw Exception(errMsg);
  }

  final parsed = jsonDecode(stdoutRaw) as Map<String, dynamic>;
  if (parsed.containsKey('error')) {
    final err = parsed['error'] as String? ?? '$script 返回了错误';
    debugPrint('[DataSource] ❌ $name stdout含error: $err');
    Log().error('数据源拉取失败（脚本返回 error JSON）', data: {
      'kind': kind,
      'plugin': pluginId,
      'name': name,
      'elapsedMs': elapsedMs,
      'error': err
    });
    throw Exception(err);
  }

  debugPrint('[DataSource] ✅ $name 成功: keys=${parsed.keys.toList()}');
  final stderrDiag = stderrRaw.isNotEmpty ? stderrRaw : '';
  Log().info('数据源拉取成功', data: {
    'kind': kind,
    'plugin': pluginId,
    'name': name,
    'elapsedMs': elapsedMs,
    'stdoutBytes': stdoutRaw.length,
    'keys': parsed.keys.toList(),
    if (stderrDiag.isNotEmpty)
      'stderr':
          stderrDiag.length > 2000 ? '${stderrDiag.substring(0, 2000)}…' : stderrDiag,
  });
  return parsed;
}
