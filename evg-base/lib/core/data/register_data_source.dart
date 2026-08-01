/// 数据源运行期热注册 —— 复用启动扫描（main._scanAndRegisterDataSources）同一份契约。
///
/// 设计器内"一键自动爬取生成数据源"后，需要把新生成的 `orch://<type>` 立即注册进
/// [DataOrchestrator]，否则组件渲染时 `resolveDataSource` 解析不到（静态启动扫描只跑一次）。
///
/// 本文件把"读取 data/manifest.json → 注册 DataType + CLI fetcher"抽成可复用函数：
/// - [registerDataSourcesFromManifest]：启动扫描逐插件调用；运行期定向热注册调用（传 [onlyType]）。
/// - 两者共用同一 [DataType] 构造 + 同一 CLI fetcher（`Process.run <exe> --type <typeArg> --project-root <projectRoot>`），
///   杜绝双实现漂移（A-P2 单真相源经验）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:evergreen_base/core/log.dart';
import 'package:evergreen_base/core/data/type.dart';
import 'package:evergreen_base/core/data/orchestrator.dart';
import 'package:evergreen_base/core/plugin/plugin_runner.dart';
import 'package:evergreen_base/core/utils/greenix_path.dart';

/// 安卓是否应加载该 CLI 数据源（规划 §5.3 C 安全网）。
///
/// 读取 manifest 顶层 `androidSupport`（默认 true）。[isAndroid]=true 且
/// `androidSupport`=false 时返回 false（隐藏）。设计为纯函数以便单测，
/// 调用方传入真实 [Platform.isAndroid]。
bool cliDataSourceSupportedOn(Map<String, dynamic> json,
    {required bool isAndroid}) {
  // 只有显式的 Dart bool false 才跳过；String/num/List 等非 bool 值一律视为 true
  final raw = json['androidSupport'];
  final support = raw is bool ? raw : true;
  return !(isAndroid && support == false);
}

/// 从某个插件的 `data/manifest.json` 注册其声明的全部（或 [onlyType] 指定的）DataType。
///
/// [pluginDir] 插件根目录（含 `data/manifest.json`）。
/// [projectRoot] 传给 CLI fetcher 的 `--project-root`（与启动扫描一致）。
/// [onlyType] 非 null 时只注册该名称的数据源（运行期定向热注册用）。
///
/// 返回成功注册的类型名列表（manifest 缺失/非法则空列表，绝不抛）。
List<String> registerDataSourcesFromManifest({
  required DataOrchestrator orch,
  required String pluginDir,
  required String projectRoot,
  String? onlyType,
}) {
  final manifestFile = File(p.join(pluginDir, 'data', 'manifest.json'));
  if (!manifestFile.existsSync()) return [];
  debugPrint('[DataSource] 发现 data/manifest.json: $pluginDir');

  try {
    final json = jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
    if (json['type'] != 'data-source') return [];

    // 规划 §5.3 C 安全网：安卓不支持（androidSupport=false，如依赖 C 扩展
    // 的 OCR/翻译/PDF/ML 插件）的 CLI 数据源直接跳过注册，避免运行时崩溃。
    if (!cliDataSourceSupportedOn(json, isAndroid: Platform.isAndroid)) {
      Log().info('DataSource 注册: 安卓不支持该数据源，跳过',
          data: {'plugin': p.basename(pluginDir)});
      return [];
    }

    final script = json['script'] as String?;
    final runtime = json['runtime'] as String? ?? 'native';
    final dataTypes = (json['dataTypes'] as List<dynamic>?) ?? [];
    if (script == null || dataTypes.isEmpty) return [];

    final dataDir = p.join(pluginDir, 'data');
    final exePath = p.join(dataDir, script);
    final exeExists = File(exePath).existsSync();
    if (!exeExists) {
      Log().warn('DataSource 注册: 数据脚本不存在，仍注册（运行时将失败）',
          data: {'plugin': p.basename(pluginDir), 'script': script, 'exe': exePath});
    }

    final pluginId = p.basename(pluginDir);
    final registered = <String>[];
    for (final dt in dataTypes) {
      if (dt is! Map<String, dynamic>) continue;
      final name = dt['name'] as String? ?? '';
      if (name.isEmpty) continue;
      if (onlyType != null && name != onlyType) continue;
      final typeArg = dt['typeArg'] as String? ?? name;
      final ttlStr = dt['ttl'] as String? ?? '5m';
      final persistentKey = dt['persistentKey'] as String?;

      var ttl = const Duration(minutes: 5);
      final ttlMatch = RegExp(r'^(\d+)(s|m|h)$').firstMatch(ttlStr);
      if (ttlMatch != null) {
        final v = int.tryParse(ttlMatch.group(1)!) ?? 5;
        switch (ttlMatch.group(2)) {
          case 's':
            ttl = Duration(seconds: v);
          case 'h':
            ttl = Duration(hours: v);
          default:
            ttl = Duration(minutes: v);
        }
      }

      final type = DataType<Map<String, dynamic>>(
        name: name,
        category: dt['category'] as String? ?? '',
        displayName: dt['displayName'] as String? ?? name,
        ttl: ttl,
        persistentKey: persistentKey,
      );

      // CLI fetcher：与启动扫描完全一致（Process.run → stdout JSON）。
      orch.register(type, () async {
        final sw = Stopwatch()..start();
        Log().info('数据源拉取开始',
            data: {
              'plugin': pluginId,
              'name': name,
              'exe': exePath,
              'args': ['--type', typeArg, '--project-root', projectRoot, '--greenix-config', greenixConfigPath]
            });
        final runner = await sharedPluginRunner;
        RunResult res;
        try {
          res = await runner.runOnce(
            exePath,
            ['--type', typeArg, '--project-root', projectRoot, '--greenix-config', greenixConfigPath],
            workingDirectory: dataDir,
            runtime: runtime,
          );
        } on ProcessException catch (e) {
          debugPrint('[DataSource] ❌ 无法启动脚本 $script: ${e.message}');
          Log().error('数据源拉取失败（无法启动脚本）',
              data: {
                'plugin': pluginId,
                'name': name,
                'script': script,
                'error': e.message
              });
          throw Exception('无法启动数据脚本 "$script": ${e.message}');
        }
        // 兼容后续 stdout/stderr/exitCode 读取
        final ProcessResult result =
            ProcessResult(0, res.exitCode, res.stdout, res.stderr);
        final elapsedMs = sw.elapsedMilliseconds;
        final stdoutRaw = result.stdout as String;
        final stderrRaw = (result.stderr as String).trim();
        debugPrint('[DataSource] $name exitCode=${result.exitCode}, '
            'elapsed=${elapsedMs}ms, '
            'stdoutLen=${stdoutRaw.length}, stderrLen=${stderrRaw.length}');
        if (result.exitCode != 0) {
          String errMsg = stderrRaw.isNotEmpty
              ? stderrRaw
              : '$script 异常退出 (code ${result.exitCode})';
          try {
            final stdoutJson = jsonDecode(stdoutRaw) as Map<String, dynamic>;
            if (stdoutJson.containsKey('error')) {
              errMsg = stdoutJson['error'] as String? ?? errMsg;
            }
          } catch (_) {}
          debugPrint('[DataSource] ❌ $name exitCode!=0: '
              'stderr=${stderrRaw.length > 200 ? stderrRaw.substring(0, 200) : stderrRaw}, '
              'stdout=${stdoutRaw.length > 200 ? stdoutRaw.substring(0, 200) : stdoutRaw}');
          Log().error('数据源拉取失败（exitCode != 0）',
              data: {
                'plugin': pluginId,
                'name': name,
                'exitCode': result.exitCode,
                'elapsedMs': elapsedMs,
                'stderr': stderrRaw.length > 800
                    ? '${stderrRaw.substring(0, 800)}…'
                    : stderrRaw,
                'stdoutTail': stdoutRaw.length > 300
                    ? stdoutRaw.substring(0, 300)
                    : stdoutRaw,
              });
          throw Exception(errMsg);
        }
        final parsed = jsonDecode(stdoutRaw) as Map<String, dynamic>;
        if (parsed.containsKey('error')) {
          final err = parsed['error'] as String? ?? '$script 返回了错误';
          debugPrint('[DataSource] ❌ $name stdout含error: $err');
          Log().error('数据源拉取失败（脚本返回 error JSON）',
              data: {'plugin': pluginId, 'name': name, 'elapsedMs': elapsedMs, 'error': err});
          throw Exception(err);
        }
        debugPrint('[DataSource] ✅ $name 成功: keys=${parsed.keys.toList()}');
        final stderrDiag = stderrRaw.isNotEmpty ? stderrRaw : '';
        Log().info('数据源拉取成功',
            data: {
              'plugin': pluginId,
              'name': name,
              'elapsedMs': elapsedMs,
              'stdoutBytes': stdoutRaw.length,
              'keys': parsed.keys.toList(),
              if (stderrDiag.isNotEmpty)
                'stderr': stderrDiag.length > 2000
                    ? '${stderrDiag.substring(0, 2000)}…'
                    : stderrDiag,
            });
        return parsed;
      });

      registered.add(name);
      Log().info('DataSource 注册',
          data: {
            'plugin': pluginId,
            'name': name,
            'script': script,
            'typeArg': typeArg,
            'exeExists': exeExists,
            'ttl': ttlStr,
            'persistentKey': persistentKey
          });
    }
    return registered;
  } catch (e) {
    Log().error('数据源注册失败',
        data: {'plugin': p.basename(pluginDir), 'error': e.toString()});
    return [];
  }
}
