/// 文件型插件（`file-source`）注册与扫描——与 `data-source` **并列的独立类型**。
///
/// 方案：`docs/plugin-registry/file-source-plugin-plan-v1.md` §2/§6 P1。
///
/// 扫描 `plugins/<id>/files/manifest.json`（`type: "file-source"`），为每个
/// `files[]` 声明注册一个 `orch://<name>` 数据类型，fetcher 走 **CLI 统一执行器**
/// （`cli_source_runner.dart#runCliSource`，与 data-source 同一份实现）。
///
/// # 与 data-source 的差异（仅这三处）
/// 1. 清单位置 `files/` 且 `type == "file-source"`；
/// 2. 声明段是 `files[]`（`FileSourceDecl`）而非 `dataTypes[]`；
/// 3. 输出额外校验 **扩展名白名单** `files[].accept`（可选）。
///
/// 其余（TTL / 超时 / 会话 / 缓存 / 降级 / 越界校验 / F1 共享缓存）**完全一致**。
///
/// # 模型支持
/// 当前支持**模型一（CLI 一次性脚本）**；模型二（`process` 常驻）尚未接线，
/// 遇到时记 warn 跳过（不静默，便于排查）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:evergreen_base/core/log.dart';
import 'package:evergreen_base/core/data/type.dart';
import 'package:evergreen_base/core/data/orchestrator.dart';
import 'package:evergreen_base/core/data/file_cache.dart';
import 'package:evergreen_base/core/data/plugin/cli_source_runner.dart';
import 'package:evergreen_base/core/data/plugin/file_source_manifest.dart';
import 'package:evergreen_base/core/data/register_data_source.dart' show kCliDataSourceTimeout;

/// 从某个插件的 `files/manifest.json` 注册其声明的全部（或 [onlyType]）文件型类型。
///
/// [pluginDir] 插件根目录（内含 `files/manifest.json`）。
/// [onlyType] 非 null 时只注册该名称。
///
/// 返回成功注册的类型名列表（清单缺失/非法则空列表，**绝不抛**）。
List<String> registerFileSourcesFromManifest({
  required DataOrchestrator orch,
  required String pluginDir,
  required String projectRoot,
  String? onlyType,
}) {
  final manifestFile = File(p.join(pluginDir, 'files', 'manifest.json'));
  if (!manifestFile.existsSync()) return [];

  try {
    final json =
        jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
    if (json['type'] != 'file-source') return [];

    final manifest = FileSourceManifest.fromJson(json);

    // 安卓安全网：与 data-source 同一语义（fail-closed）。
    if (!FileSourceManifest.isSupportedOn(manifest,
        isAndroid: Platform.isAndroid)) {
      Log().info('FileSource 注册: 安卓不支持该插件，跳过',
          data: {'plugin': p.basename(pluginDir)});
      return [];
    }

    final script = manifest.script;
    final runtime = manifest.runtime;
    if (script == null || script.isEmpty) {
      if (manifest.process != null) {
        Log().warn('FileSource 注册: 模型二（process 常驻）尚未支持，跳过',
            data: {'plugin': p.basename(pluginDir)});
      }
      return [];
    }
    if (manifest.files.isEmpty) return [];

    final filesDir = p.join(pluginDir, 'files');
    final scriptPath = p.join(filesDir, script);
    if (!File(scriptPath).existsSync()) {
      Log().warn('FileSource 注册: 脚本不存在，仍注册（运行时将失败）',
          data: {'plugin': p.basename(pluginDir), 'script': scriptPath});
    }

    final pluginId = p.basename(pluginDir);
    final registered = <String>[];

    for (final decl in manifest.files) {
      final name = decl.name;
      if (name.isEmpty) continue;
      if (onlyType != null && name != onlyType) continue;

      final typeArg = decl.typeArg ?? name;
      final effectiveTimeout = decl.timeout ?? kCliDataSourceTimeout;

      final type = DataType<Map<String, dynamic>>(
        name: name,
        category: decl.category,
        displayName: decl.title ?? name,
        ttl: decl.ttl,
        persistentKey: decl.persistentKey,
        fallback: decl.fallbackJson,
        sessionProviderId: manifest.auth?.sessionProvider,
        sessionDomain: manifest.auth?.sessionDomain,
      );

      orch.register(type, () async {
        final parsed = await runCliSource(
          scriptPath: scriptPath,
          typeArg: typeArg,
          projectRoot: projectRoot,
          workingDirectory: filesDir,
          runtime: runtime,
          timeout: effectiveTimeout,
          pluginId: pluginId,
          name: name,
          script: script,
          kind: 'file-source',
        );

        // ── 校验 1：缓存路径越界（协议 §7，与 data-source 同一实现）──
        try {
          validateFileCachePaths(parsed);
        } on FormatException catch (e) {
          Log().error('文件型数据源拉取失败（路径越界）', data: {
            'kind': 'file-source',
            'plugin': pluginId,
            'name': name,
            'paths': fileCachePathsOf(parsed),
            'error': e.message,
          });
          throw Exception(e.message);
        }

        // ── 校验 2：扩展名白名单（`files[].accept`，可选）──
        if (decl.accept.isNotEmpty) {
          for (final path in fileCachePathsOf(parsed)) {
            if (!decl.acceptsPath(path)) {
              final msg =
                  '$kFileAcceptViolationPrefix：$path（声明接受 ${decl.accept.join('/')}）';
              Log().error('文件型数据源拉取失败（扩展名不匹配）', data: {
                'kind': 'file-source',
                'plugin': pluginId,
                'name': name,
                'path': path,
                'accept': decl.accept,
              });
              throw Exception(msg);
            }
          }
        }

        return parsed;
      });

      registered.add(name);
      Log().info('FileSource 注册', data: {
        'plugin': pluginId,
        'name': name,
        'script': scriptPath,
        'typeArg': typeArg,
        'ttl': decl.ttl.toString(),
        'timeoutSeconds': effectiveTimeout.inSeconds,
        'accept': decl.accept,
        'persistentKey': decl.persistentKey,
      });
    }
    return registered;
  } catch (e) {
    Log().error('FileSource 注册失败',
        data: {'plugin': p.basename(pluginDir), 'error': e.toString()});
    return [];
  }
}

/// 扫描 [pluginsDir] 下所有 `*/files/manifest.json` 并批量注册。
///
/// 与 data-source 的 `_scanAndRegisterDataSources` 对称；两者在启动期同一
/// 步骤内先后执行（见 `app_bootstrap._stepDataSources`）。
Future<List<String>> scanAndLoadFileSources({
  required String pluginsDir,
  required DataOrchestrator orchestrator,
  required String projectRoot,
}) async {
  final out = <String>[];
  final dir = Directory(pluginsDir);
  if (!dir.existsSync()) {
    Log().warn('[BOOT] ⚠ 插件目录不存在，跳过文件型数据源扫描');
    return out;
  }
  for (final entity in dir.listSync()) {
    if (entity is! Directory) continue;
    final names = registerFileSourcesFromManifest(
      orch: orchestrator,
      pluginDir: entity.path,
      projectRoot: projectRoot,
    );
    if (names.isNotEmpty) {
      out.addAll(names);
      debugPrint('[BOOT] FileSource 扫描完成: '
          'plugin=${p.basename(entity.path)}, count=${names.length}, types=$names');
    }
  }
  return out;
}
