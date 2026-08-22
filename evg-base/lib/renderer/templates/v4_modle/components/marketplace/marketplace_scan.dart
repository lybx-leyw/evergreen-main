/// 插件市场：扫描 plugins/ 目录，返回所有类型的插件信息及其真实磁盘目录映射（纯函数，便于单测）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/core/agent/skill/skill.dart';
import 'marketplace_plugin_info.dart';

/// 扫描 [pluginsDir] 下的所有插件目录与所有类型 manifest。
///
/// 与旧实现的关键差异：
/// 1. **不再只认 module**：曾经用 [ModuleDescriptor.fromJson]（强要求 `type==module`）
///    导致 `agent`/`data-source`/`config`/`theme` 等类型的插件被静默跳过，市场里
///    只显示 module。现在对每种 manifest 类型都构造 [PluginInfo]。
/// 2. **一个文件夹可贡献多个卡片**：依次检查 module/agent/data/config/theme/根 manifest，
///    每个存在的都作为独立卡片（例如某文件夹同时有 module 与 data-source）。
/// 3. **稳定 id**：manifest 无 `id` 时回退文件夹名；同文件夹多 manifest 回退碰撞时
///    追加子类型后缀，保证 state/uninstall 有唯一 key。
///
/// 返回：
/// - [List<PluginInfo>]：所有被发现并成功解析的插件信息。
/// - [Map<String, String>]：每个插件 `id` → 它所在文件夹的 [Directory.path]（插件根目录定位用）。
///   精确卸载路径请使用 [PluginInfo.deletePath]。
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
    // 子类型 key 同时用于推导卸载时的精确分支目录。
    final candidates = <String, String>{
      'module':
          '${entity.path}${Platform.pathSeparator}module${Platform.pathSeparator}manifest.json',
      'agent':
          '${entity.path}${Platform.pathSeparator}agent${Platform.pathSeparator}manifest.json',
      'data-source':
          '${entity.path}${Platform.pathSeparator}data${Platform.pathSeparator}manifest.json',
      'config':
          '${entity.path}${Platform.pathSeparator}config${Platform.pathSeparator}config.json',
      'theme':
          '${entity.path}${Platform.pathSeparator}theme${Platform.pathSeparator}theme.json',
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

    // Skill 能力目录（Skill 即插件）：plugins/<id>/skill/*.md ——
    // 无需 manifest，存在 .md 即生成一张 type='skill' 卡片。
    // 与 SkillLoader 的插件布局 B 一致；id 回退文件夹名（collision 时加 -skill 后缀）。
    final skillDirPath = '${entity.path}${Platform.pathSeparator}skill';
    final skillDir = Directory(skillDirPath);
    if (skillDir.existsSync()) {
      try {
        final skills = SkillLoader([skillDirPath]).loadAll();
        if (skills.isNotEmpty) {
          final info = _toSkillPluginInfo(entity.path, skills.first, usedIds);
          if (info != null) {
            infos.add(info);
            dirs[info.id] = entity.path;
            usedIds.add(info.id);
          }
        }
      } catch (_) {
        // skill 目录解析失败跳过（不影响其他卡片）
      }
    }
  }
  return (infos, dirs);
}

/// 返回子类型对应的卸载目标目录名；根 manifest 使用空串表示整个插件目录。
String _deleteBranchForSubType(String subType) {
  switch (subType) {
    case 'module':
      return 'module';
    case 'agent':
      return 'agent';
    case 'data-source':
      return 'data';
    case 'config':
      return 'config';
    case 'theme':
      return 'theme';
    case 'skill':
      return 'skill';
    default:
      return '';
  }
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

  // type：优先 manifest.type，否则按子目录推断（agent/data/module/config/theme）。
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
  var section = '未分组';
  var sectionOrder = 50;
  var order = 50;
  if (isModule) {
    try {
      final d = ModuleDescriptor.fromJson(json);
      final sidebar = d.nav.sidebar;
      hasSidebar = sidebar != null;
      pageCount = d.pages.length;
      iconCode = d.icon;
      if (sidebar != null) {
        section = sidebar.section;
        sectionOrder = sidebar.sectionOrder;
        order = sidebar.order;
      }
    } catch (_) {
      // module 解析异常则降级为非模块信息（仍展示，只是无侧栏/页面信息）。
      isModule = false;
    }
  }

  final branch = _deleteBranchForSubType(subType);
  return PluginInfo(
    id: id,
    name: name,
    description: description,
    type: type,
    version: version,
    iconCode: iconCode,
    dirPath: folderPath,
    deletePath: branch.isEmpty
        ? folderPath
        : p.join(folderPath, branch),
    isModule: isModule,
    hasSidebar: hasSidebar,
    pageCount: pageCount,
    section: section,
    sectionOrder: sectionOrder,
    order: order,
  );
}

/// 从插件目录的 `skill/` 能力生成市场卡片（type='skill'）。
///
/// 名称/描述取首个 Skill 的 frontmatter；id 回退文件夹名
/// （已占用时追加 `-skill` 后缀，保证状态/卸载有唯一 key）。
PluginInfo? _toSkillPluginInfo(
  String folderPath,
  Skill skill,
  Set<String> usedIds,
) {
  final folderName = p.basename(folderPath);
  var id = folderName;
  if (usedIds.contains(id)) {
    id = '$folderName-skill';
  }
  return PluginInfo(
    id: id,
    name: skill.name,
    description: skill.description,
    type: 'skill',
    dirPath: folderPath,
    deletePath: p.join(folderPath, 'skill'),
    isModule: false,
    isSkill: true,
    hasSidebar: false,
    pageCount: 0,
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
    case 'config':
      return 'config';
    case 'theme':
      return 'theme';
    default:
      return 'unknown';
  }
}

/// 内置模块（ModuleRegistry 注册的随应用分发模块，如 zju 9 个校园模块）
/// → 插件市场信息。
///
/// 与 [scanPluginManifests] 扫描出的磁盘插件不同：
/// - `isBuiltin: true` → 卡片显示「内置」徽标、隐藏「卸载」按钮；
/// - `dirPath: ''` → 无磁盘目录，卸载/定位操作应被 UI 拦截。
PluginInfo pluginInfoFromBuiltinModule(ModuleDescriptor d) {
  final sidebar = d.nav.sidebar;
  return PluginInfo(
    id: d.id,
    name: d.name,
    description: d.description,
    type: 'module',
    version: d.version,
    iconCode: d.icon,
    dirPath: '',
    deletePath: '',
    isModule: true,
    hasSidebar: d.hasSidebar,
    pageCount: d.pages.length,
    isBuiltin: true,
    section: sidebar?.section ?? '未分组',
    sectionOrder: sidebar?.sectionOrder ?? 50,
    order: sidebar?.order ?? 50,
  );
}
