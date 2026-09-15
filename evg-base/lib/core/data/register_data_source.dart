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
import 'package:evergreen_base/core/data/file_cache.dart';
import 'package:evergreen_base/core/data/plugin/cli_source_runner.dart';
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
      // per-type 超时（协议 file-data §10）：manifest `timeoutSeconds` 声明时生效，
      // 缺省回落全局 kCliDataSourceTimeout。文件型数据源冷启动大文件必需。
      final effectiveTimeout = decl.timeout ?? kCliDataSourceTimeout;

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
        // 未声明（null）零行为变化。auth.sessionDomain 为登录锁分组键：同一网站域
        // 的数据源共享一把登录锁（比按 sessionProvider 分组更细），未声明回退
        // sessionProviderId 分组。
        sessionProviderId: manifest.auth?.sessionProvider,
        sessionDomain: manifest.auth?.sessionDomain,
      );

      // CLI fetcher：与启动扫描完全一致（Process.run → stdout JSON）。
orch.register(type, () async {
        // 统一 CLI 执行器（与 file-source 共用同一份实现，杜绝双实现漂移）。
        final parsed = await runCliSource(
          scriptPath: scriptPath,
          typeArg: typeArg,
          projectRoot: projectRoot,
          workingDirectory: dataDir,
          runtime: runtime,
          timeout: effectiveTimeout,
          pluginId: pluginId,
          name: name,
          script: script,
          kind: 'data-source',
        );
        // 文件型数据源路径越界校验（协议 §7）：payload 含 path / files[].path
        // 时必须是 file_cache/ 内的绝对路径；无 path 声明的既有数据源零行为变化。
        // 越界抛 FormatException → 由 DataOrchestrator 落 lastError（协议 §12 T10）。
        try {
          validateFileCachePaths(parsed);
        } on FormatException catch (e) {
          debugPrint(
              '[DataSource] ❌ $name $kFileCacheViolationPrefix: ${e.message}');
          Log().error('数据源拉取失败（文件缓存路径越界）', data: {
            'kind': 'data-source',
            'plugin': pluginId,
            'name': name,
            'paths': fileCachePathsOf(parsed),
            'error': e.message,
          });
          throw Exception(e.message);
        }
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
        'timeoutSeconds': effectiveTimeout.inSeconds,
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
