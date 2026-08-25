/// 数据源运行期热注册 —— 复用启动扫描（main._scanAndRegisterDataSources）同一份契约。
///
/// 设计器内"一键自动爬取生成数据源"后，需要把新生成的 `orch://<type>` 立即注册进
/// [DataOrchestrator]，否则组件渲染时 `resolveDataSource` 解析不到（静态启动扫描只跑一次）。
///
/// 本文件把"读取 data/manifest.json → 注册 DataType + CLI fetcher"抽成可复用函数：
/// - [registerDataSourcesFromManifest]：启动扫描逐插件调用；运行期定向热注册调用（传 [onlyType]）。
/// - 两者共用同一 [DataType] 构造 + 同一 CLI fetcher（`Process.run <script> --type <typeArg> --project-root <projectRoot>`），
///   杜绝双实现漂移（A-P2 单真相源经验）。
///
/// manifest 解析统一复用 `plugin/data_source_manifest.dart` 的 typed model（[DataSourceManifest].fromJson），
/// 不再手写逐字段读、不再内联 TTL 正则——TTL/`category`/`androidSupport` 等语义单一实现。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:evergreen_base/core/log.dart';
import 'package:evergreen_base/core/data/type.dart';
import 'package:evergreen_base/core/data/orchestrator.dart';
import 'package:evergreen_base/core/data/plugin/data_source_manifest.dart';
import 'package:evergreen_base/core/plugin/plugin_runner.dart';
import 'package:evergreen_base/core/utils/greenix_path.dart';

/// CLI 数据源 fetcher 的 `runOnce` 超时。超时路径会 kill 子进程（见
/// [PluginRunner.runOnce] 的 `timeout` 语义），错误进入 `lastError`（「超时」类文案）。
const Duration kCliDataSourceTimeout = Duration(seconds: 60);

/// 安卓是否应加载该 CLI 数据源（规划 §5.3 C 安全网）。
///
/// 读取 manifest 顶层 `androidSupport`（严格 bool 解析：缺省 true、仅真实 bool
/// 有效、字符串/数字等非 bool 值一律视为 false 跳过）。[isAndroid]=true 且
/// `androidSupport`=false 时返回 false（隐藏）。设计为纯函数以便单测，
/// 调用方传入真实 [Platform.isAndroid]。
bool cliDataSourceSupportedOn(Map<String, dynamic> json,
    {required bool isAndroid}) {
  final support = parseDataSourceAndroidSupport(json['androidSupport']);
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
    final json =
        jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
    if (json['type'] != 'data-source') return [];

    // 统一 typed model 解析：script/process 互斥、typeArg、category 默认「未分类」、
    // TTL（s/m/h/ms/纯秒数）、androidSupport 严格 bool。未知字段静默忽略。
    final manifest = DataSourceManifest.fromJson(json);

    // 规划 §5.3 C 安全网：安卓不支持（androidSupport=false，如依赖 C 扩展
    // 的 OCR/翻译/PDF/ML 插件）的 CLI 数据源直接跳过注册，避免运行时崩溃。
    if (!DataSourceManifest.isSupportedOn(manifest,
        isAndroid: Platform.isAndroid)) {
      Log().info('DataSource 注册: 安卓不支持该数据源，跳过',
          data: {'plugin': p.basename(pluginDir)});
      return [];
    }

    final script = manifest.script;
    final runtime = manifest.runtime;
    if (script == null || script.isEmpty || manifest.dataTypes.isEmpty) {
      return [];
    }

    final dataDir = p.join(pluginDir, 'data');
    final scriptPath = p.join(dataDir, script);
    final scriptExists = File(scriptPath).existsSync();
    if (!scriptExists) {
      Log().warn('DataSource 注册: 数据脚本不存在，仍注册（运行时将失败）',
          data: {'plugin': p.basename(pluginDir), 'script': scriptPath});
    }

    final pluginId = p.basename(pluginDir);
    final registered = <String>[];
    for (final decl in manifest.dataTypes) {
      final name = decl.name;
      if (name.isEmpty) continue;
      if (onlyType != null && name != onlyType) continue;
      final typeArg = decl.typeArg ?? name;
      final persistentKey = decl.persistentKey;
      final ttl = decl.ttl;

      final type = DataType<Map<String, dynamic>>(
        name: name,
        category: decl.category,
        displayName: decl.displayName ?? name,
        ttl: ttl,
        persistentKey: persistentKey,
        // 静态兜底（第三级降级）：manifest 声明 fallbackJson 时，拉取失败且无
        // 旧缓存由 orchestrator 返回兜底并标记「使用静态兜底」；未声明则零行为变化。
        fallback: decl.fallbackJson,
        // 会话绑定（主题 A）：manifest 顶层 auth.sessionProvider 声明后，数据层
        // 拉取失败且错误被判为「会话失效」时经 SessionCoordinator 单点重登重拉；
        // 未声明（null）零行为变化。
        sessionProviderId: manifest.auth?.sessionProvider,
      );

      // CLI fetcher：与启动扫描完全一致（Process.run → stdout JSON）。
      orch.register(type, () async {
        final sw = Stopwatch()..start();
        Log().info('数据源拉取开始', data: {
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
            workingDirectory: dataDir,
            runtime: runtime,
            timeout: kCliDataSourceTimeout,
          );
        } on TimeoutException {
          Log().error('数据源拉取超时', data: {
            'plugin': pluginId,
            'name': name,
            'script': script,
            'timeoutSeconds': kCliDataSourceTimeout.inSeconds,
          });
          throw Exception(
              '数据脚本 "$script" 执行超时（>${kCliDataSourceTimeout.inSeconds}s），已终止子进程');
        } on ProcessException catch (e) {
          debugPrint('[DataSource] ❌ 无法启动脚本 $script: ${e.message}');
          Log().error('数据源拉取失败（无法启动脚本）', data: {
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
          Log().error('数据源拉取失败（exitCode != 0）', data: {
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
          Log().error('数据源拉取失败（脚本返回 error JSON）', data: {
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

      // 文件下载声明接线（T8a）：manifest `dataTypes[].file` 登记到中枢，
      // 供消费方 `orch.fileOf(type)` / `fileByName(name)` 查询；未声明（null）清除。
      orch.registerFile(name, decl.file);

      registered.add(name);
      Log().info('DataSource 注册', data: {
        'plugin': pluginId,
        'name': name,
        'script': scriptPath,
        'typeArg': typeArg,
        'scriptExists': scriptExists,
        'ttl': ttl.toString(),
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
