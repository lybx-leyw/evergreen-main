/// 安卓插件资产释放器。
///
/// 安卓端无文件系统级的 `plugins/` 目录（桌面靠项目根平级目录），
/// 故把 `plugins/` 作为 flutter assets（`assets/plugins_bundle/`）打进 APK，
/// 本模块在启动期将其递归释放到应用可写目录：
///
///   getApplicationSupportDirectory()/.greenix/plugins
///
/// 释放后，`greenix_path.resolvePluginsRoot()` 与 `main._pluginsDir` 在安卓
/// 均指向该目录，所有插件消费者（module_loader / plugin_bridge / data
/// orchestrator / marketplace / skill loader …）自然受益。
///
/// 复用 [agent_runtime] 中 skill 资产释放的同一范式（rootBundle → File）。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// assets 中插件资产的前缀（与 pubspec.yaml 的 `- assets/plugins_bundle/` 对应）。
const String kPluginAssetPrefix = 'assets/plugins_bundle/';

/// 释放插件资产到设备可写目录（仅安卓执行；其他平台返回 null 且不触碰资产）。
///
/// ⚠️ 策略：始终覆盖写入（不作幂等缓存）。
///
/// 旧版用 `.released` 标记 + 文件数量做幂等判断，但该方案无法检测**存量文件内容变更**
///（如 scraper.py 改了代码但未增删文件 → 文件数不变 → 跳过重提取 → 旧代码残留）。
/// 按键集指纹也同理：内容变更（同键不同值）无法被键集捕获。
///
/// 资产总量小（~2MB），每次启动覆盖写入 <1s，远好于内容不一致的隐蔽 bug。
///
/// 返回释放后的插件根目录绝对路径。
Future<String?> releasePluginsAssetsIfNeeded() async {
  if (!Platform.isAndroid) return null;

  final support = await getApplicationSupportDirectory();
  final target = p.join(support.path, '.greenix', 'plugins');
  debugPrint('[PluginRelease] target=$target');

  // 读取 AssetManifest，筛选插件资产键。
  // 新版 Flutter 已用 AssetManifest.bin 取代 AssetManifest.json，手动
  // loadString('.json') 会抛异常导致插件资产释放失败（安卓空目录）。用
  // 官方 API 解析，自动兼容 .json / .bin 两种格式。
  final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
  final pluginKeys = manifest.listAssets()
      .where((k) => k.startsWith(kPluginAssetPrefix))
      .where((k) => k.substring(kPluginAssetPrefix.length).isNotEmpty)
      .toList();
  debugPrint('[PluginRelease] AssetManifest 总键: ${manifest.listAssets().length},'
      ' 插件资产键: ${pluginKeys.length}');

  // 本次清单（相对路径，用于差异清理）。
  final currentRels = pluginKeys
      .map((k) => k.substring(kPluginAssetPrefix.length))
      .toSet();

  // ── 差异清理：删除"上次由 bundle 释放、本次已下线"的文件 ──
  // 覆盖写入只增不减：旧 APK 打包过的插件（如已下线的 ai-planner）会
  // 残留在设备目录并被模块扫描加载。此处依据上次释放快照做减法，
  // 只删 bundle 曾经释放过的文件；marketplace 下载安装的插件不在快照内，
  // 不会被误删。
  final manifestFile = File(p.join(target, '.released_manifest.json'));
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
        final f = File(p.join(target, rel));
        if (f.existsSync()) {
          f.deleteSync();
          removed++;
        }
        // 清理因删文件而变空的父目录链（不越过插件根）。
        var dir = f.parent;
        while (dir.path != target &&
            dir.existsSync() &&
            dir.listSync().isEmpty) {
          dir.deleteSync();
          dir = dir.parent;
        }
      } catch (_) {}
    }
    debugPrint('[PluginRelease] 🧹 差异清理: 删除 ${removed} 个已下线资产'
        '（插件残留: ${stale.take(5).join(', ')}${stale.length > 5 ? ', ...' : ''}）');
  }

  var count = 0;
  var skipped = 0;
  for (final key in pluginKeys) {
    final rel = key.substring(kPluginAssetPrefix.length);
    final out = File(p.join(target, rel));
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
      debugPrint('[PluginRelease] 跳过资产 $key: $e');
    }
  }
  debugPrint('[PluginRelease] 释放完成: $count 个文件'
      '（跳过 $skipped）→ $target');

  // 写入本次释放快照（供下次启动做差异清理）。
  try {
    await manifestFile.writeAsString(jsonEncode(currentRels.toList()..sort()));
  } catch (e) {
    debugPrint('[PluginRelease] ⚠ 写入释放快照失败: $e');
  }
  return target;
}
