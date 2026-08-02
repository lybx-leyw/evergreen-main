/// 运行时资产释放器（插件 + 管线脚本）。
///
/// 把 flutter 资产 `assets/plugins_bundle/` 与 `assets/scripts_bundle/`
/// 递归释放到 `.greenix/plugins` 与 `.greenix/scripts`（全平台）：
///
///   - Android：app 私有可写目录下（`getApplicationSupportDirectory()/.greenix`）
///   - 桌面：`Directory.current/.greenix`（与 greenix_path 的 baseDir 一致）
///
/// 释放后 `greenix_path.resolvePluginsRoot()` 与 `greenixScriptsDir` 均指向
/// 对应目录，所有插件 / 脚本消费者自然受益。
///
/// 复用 [agent_runtime] 中 skill 资产释放的同一范式（rootBundle → File）。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:path/path.dart' as p;

import 'greenix_path.dart';

/// assets 中插件资产的前缀（与 pubspec.yaml 的 `- assets/plugins_bundle/` 对应）。
const String kPluginAssetPrefix = 'assets/plugins_bundle/';

/// assets 中管线脚本资产的前缀（与 pubspec.yaml 的 SCRIPTS 标记块对应）。
const String kScriptsAssetPrefix = 'assets/scripts_bundle/';

/// 释放插件 + 管线脚本资产到 `.greenix/`（全平台）。
///
/// ⚠️ 策略：始终覆盖写入（不作幂等缓存）。旧版用 `.released` 标记 + 文件数做
/// 幂等判断，但无法检测**存量文件内容变更**（同键不同值）。资产总量小
/// （~2MB），每次启动覆盖写入 <1s，远好于内容不一致的隐蔽 bug。
Future<void> releaseBundledAssets() async {
  await _releaseBundle(kPluginAssetPrefix, greenixPluginsDir);
  await _releaseBundle(kScriptsAssetPrefix, greenixScriptsDir);
}

/// 释放单个资产束（[assetPrefix] 前缀 → [targetDir]）。
Future<void> _releaseBundle(String assetPrefix, String targetDir) async {
  debugPrint('[AssetRelease] target=$targetDir (prefix=$assetPrefix)');

  // 读取 AssetManifest，筛选该束资产键。
  // 新版 Flutter 用 AssetManifest.bin，需用官方 API 解析（兼容 .json/.bin）。
  final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
  final keys = manifest.listAssets()
      .where((k) => k.startsWith(assetPrefix))
      .where((k) => k.substring(assetPrefix.length).isNotEmpty)
      .toList();
  debugPrint('[AssetRelease] AssetManifest 总键: ${manifest.listAssets().length},'
      ' 本束($assetPrefix)键: ${keys.length}');

  // 本次清单（相对路径，用于差异清理）。
  final currentRels = keys.map((k) => k.substring(assetPrefix.length)).toSet();

  // ── 差异清理：删除"上次由本束释放、本次已下线"的文件 ──
  // 覆盖写入只增不减：旧包打包过、现已下线的文件会残留并被模块扫描加载。
  // 依据上次释放快照做减法，只删本束释放过的文件；marketplace 下载的插件
  // 不在快照内，不会被误删。
  final manifestFile = File(p.join(targetDir, '.released_manifest.json'));
  Set<String> previousRels = {};
  if (manifestFile.existsSync()) {
    try {
      final prev = jsonDecode(manifestFile.readAsStringSync());
      if (prev is List) {
        previousRels = prev.cast<String>().toSet();
      }
    } catch (_) {}
  }
  final stale = previousRels.difference(currentRels);
  if (stale.isNotEmpty) {
    var removed = 0;
    for (final rel in stale) {
      try {
        final f = File(p.join(targetDir, rel));
        if (f.existsSync()) {
          f.deleteSync();
          removed++;
        }
        // 清理因删文件而变空的父目录链（不越过释放根）。
        var dir = f.parent;
        while (dir.path != targetDir &&
            dir.existsSync() &&
            dir.listSync().isEmpty) {
          dir.deleteSync();
          dir = dir.parent;
        }
      } catch (_) {}
    }
    debugPrint('[AssetRelease] 🧹 差异清理: 删除 ${removed} 个已下线资产'
        '（残留: ${stale.take(5).join(', ')}${stale.length > 5 ? ', ...' : ''}）');
  }

  var count = 0;
  var skipped = 0;
  for (final key in keys) {
    final rel = key.substring(assetPrefix.length);
    final out = File(p.join(targetDir, rel));
    try {
      await out.parent.create(recursive: true);
      final ByteData data = await rootBundle.load(key);
      await out.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      count++;
    } on Exception catch (e) {
      // 单个资产加载失败（如打包器未实际包含该文件）不应中断整体释放。
      skipped++;
      debugPrint('[AssetRelease] 跳过资产 $key: $e');
    }
  }
  debugPrint('[AssetRelease] 释放完成: $count 个文件'
      '（跳过 $skipped）→ $targetDir');

  // 写入本次释放快照（供下次启动做差异清理）。
  try {
    await manifestFile.writeAsString(jsonEncode(currentRels.toList()..sort()));
  } catch (e) {
    debugPrint('[AssetRelease] ⚠ 写入释放快照失败: $e');
  }
}
