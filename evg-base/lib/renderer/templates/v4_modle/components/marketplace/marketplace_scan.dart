/// 插件市场：扫描 plugins/ 目录，返回所有类型的插件信息及其真实磁盘目录映射（纯函数，便于单测）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'marketplace_plugin_info.dart';

/// 扫描 [pluginsDir] 下的所有插件目录与所有类型 manifest。
///
/// 与旧实现的关键差异：
/// 1. **不再只认 module**：曾经用 [ModuleDescriptor.fromJson]（强要求 `type==module`）
///    导致 `agent`/`data-source`/`config`/`theme` 等类型的插件被静默跳过，市场里
///    只显示 module。现在对每种 manifest 类型都构造 [PluginInfo]。
/// 2. **一个文件夹可贡献多个卡片**：依次检查 module/agent/data/根 manifest，
///    每个存在的都作为独立卡片（例如某文件夹同时有 module 与 data-source）。
/// 3. **稳定 id**：manifest 无 `id` 时回退文件夹名；同文件夹多 manifest 回退碰撞时
///    追加子类型后缀，保证 state/uninstall 有唯一 key。
///
/// 返回：
/// - [List<PluginInfo>]：所有被发现并成功解析的插件信息。
/// - [Map<String, String>]：每个插件 `id` → 它所在文件夹的 [Directory.path]（卸载用）。
(List<PluginInfo>, Map<String, String>) scanPluginManifests(String pluginsDir) {
  final dir = Directory(pluginsDir);
  final infos = <PluginInfo>[];
  final dirs = <String, String>{};
  if (!dir.existsSync()) return (infos, dirs);

  // 已用 id 集合，防止回退到文件夹名时发生碰撞。
  final usedIds = <String>{};

  for (final entity in dir.listSync()) {
    if (entity is! Directory) continue;
    // 跳过隐藏目录（仅检测目录名是否以 . 开头）
    if (p.basename(entity.path).startsWith('.')) continue;

    // 一个文件夹可能含多个子类型 manifest，全部收集为独立卡片。
    final candidates = <String, String>{
      'module':
          '${entity.path}${Platform.pathSeparator}module${Platform.pathSeparator}manifest.json',
      'agent':
          '${entity.path}${Platform.pathSeparator}agent${Platform.pathSeparator}manifest.json',
      'data-source':
          '${entity.path}${Platform.pathSeparator}data${Platform.pathSeparator}manifest.json',
      'root': '${entity.path}${Platform.pathSeparator}manifest.json',
    };

    for (final entry in candidates.entries) {
      final subType = entry.key;
      final mp = entry.value;
      final mf = File(mp);
      if (!mf.existsSync()) continue;
      try {
        final json = jsonDecode(mf.readAsStringSync()) as Map<String, dynamic>;
        final info = _toPluginInfo(json, entity.path, subType, usedIds);
        if (info != null) {
          infos.add(info);
          dirs[info.id] = entity.path;
          usedIds.add(info.id);
        }
      } catch (_) {
        // 解析失败的 manifest 跳过
      }
    }
  }
  return (infos, dirs);
}

PluginInfo? _toPluginInfo(
  Map<String, dynamic> json,
  String folderPath,
  String subType,
  Set<String> usedIds,
) {
  final folderName = p.basename(folderPath);

  // id：优先 manifest.id，否则回退文件夹名。
  String id = (json['id'] as String?)?.isNotEmpty == true
      ? json['id'] as String
      : folderName;
  if (usedIds.contains(id)) {
    // 同文件夹多 manifest 回退碰撞：追加子类型区分（如 showcase-data → showcase-data-data-source 不会发生，
    // 因为 showcase-data 自身有 id；此分支仅针对无 id 的第二个 manifest）。
    id = '$id-$subType';
  }

  // type：优先 manifest.type，否则按子目录推断（agent/data/module）。
  final type = (json['type'] as String?)?.isNotEmpty == true
      ? json['type'] as String
      : _defaultTypeForSub(subType);

  final name = (json['name'] as String?)?.isNotEmpty == true
      ? json['name'] as String
      : id;
  final description = (json['description'] as String?) ?? '';
  final version = json['version'] as String?;

  var isModule = type == 'module';
  var hasSidebar = false;
  var pageCount = 0;
  int? iconCode;
  if (isModule) {
    try {
      final d = ModuleDescriptor.fromJson(json);
      hasSidebar = d.nav.sidebar != null;
      pageCount = d.pages.length;
      iconCode = d.icon;
    } catch (_) {
      // module 解析异常则降级为非模块信息（仍展示，只是无侧栏/页面信息）。
      isModule = false;
    }
  }

  return PluginInfo(
    id: id,
    name: name,
    description: description,
    type: type,
    version: version,
    iconCode: iconCode,
    dirPath: folderPath,
    isModule: isModule,
    hasSidebar: hasSidebar,
    pageCount: pageCount,
  );
}

String _defaultTypeForSub(String subType) {
  switch (subType) {
    case 'module':
      return 'module';
    case 'agent':
      return 'agent';
    case 'data-source':
      return 'data-source';
    default:
      return 'unknown';
  }
}
