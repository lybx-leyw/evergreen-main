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

import 'package:path/path.dart' as p;

import 'package:evergreen_base/core/log.dart';
import 'package:evergreen_base/core/data/type.dart';
import 'package:evergreen_base/core/data/orchestrator.dart';

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

  try {
    final json = jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
    if (json['type'] != 'data-source') return [];
    final script = json['script'] as String?;
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
              'args': ['--type', typeArg, '--project-root', projectRoot]
            });
        ProcessResult result;
        try {
          result = await Process.run(
            exePath,
            ['--type', typeArg, '--project-root', projectRoot],
            workingDirectory: dataDir,
          );
        } on ProcessException catch (e) {
          Log().error('数据源拉取失败（无法启动脚本）',
              data: {
                'plugin': pluginId,
                'name': name,
                'script': script,
                'error': e.message
              });
          throw Exception('无法启动数据脚本 "$script": ${e.message}');
        }
        final elapsedMs = sw.elapsedMilliseconds;
        final stdoutRaw = result.stdout as String;
        final stderrRaw = (result.stderr as String).trim();
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
          Log().error('数据源拉取失败（脚本返回 error JSON）',
              data: {'plugin': pluginId, 'name': name, 'elapsedMs': elapsedMs, 'error': err});
          throw Exception(err);
        }
        Log().info('数据源拉取成功',
            data: {
              'plugin': pluginId,
              'name': name,
              'elapsedMs': elapsedMs,
              'stdoutBytes': stdoutRaw.length,
              'keys': parsed.keys.toList(),
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
