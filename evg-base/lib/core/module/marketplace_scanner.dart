/// 市场源扫描器（M5-5，纯逻辑，core 子包可单测）。
///
/// 把 [MarketplaceSource] 列表（M5-1 解析结果）转换为可被市场 UI / 安装器
/// 消费的插件发现列表。设计要点：
/// - clone 动作抽成可注入的 [GithubCloner]，便于单测用 fake（写本地目录）
///   或主包用真实 `git clone` 实现，scanner 自身不依赖 git / 网络 / Flutter。
/// - fail-closed：单个源扫描失败不影响其它源（返回已成功的条目 + 记录错误），
///   但顶层非法输入（如空 sources）由调用方决定。
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'github_source.dart';
import 'marketplace_source.dart';

/// 克隆器签名：把 [GithubSource] 克隆到 [targetDir]。
///
/// 主包传真实 `git clone` 实现（见 `core/services/github_clone.dart`）；
/// 单测传 fake（直接把预置目录内容写入 [targetDir]）。
typedef GithubCloner = Future<void> Function(GithubSource src, String targetDir);

/// 市场发现的单个插件条目（与 UI 无关的最小数据）。
class MarketplaceEntry {
  /// 稳定标识（来自 manifest id 或文件夹名）。
  final String id;

  /// 人类可读名称（来自 manifest name 或 id）。
  final String name;

  /// 插件类型：module / agent / data-source / config / theme / skill / unknown。
  final String type;

  /// 插件在磁盘上的真实文件夹路径（克隆/本地源解析后的绝对路径）。
  final String dirPath;

  /// 来源源 id（[MarketplaceSource.id]），用于溯源与去重。
  final String sourceId;

  const MarketplaceEntry({
    required this.id,
    required this.name,
    required this.type,
    required this.dirPath,
    required this.sourceId,
  });

  @override
  String toString() =>
      'MarketplaceEntry($id, $type, src=$sourceId, dir=$dirPath)';
}

/// 单个源的扫描结果（成功条目 + 可选错误）。
class SourceScanResult {
  final MarketplaceSource source;
  final List<MarketplaceEntry> entries;
  final Object? error;

  const SourceScanResult(this.source, this.entries, [this.error]);

  bool get failed => error != null;
}

/// 扫描插件目录，返回所有被发现的能力分支条目（纯函数，无网络）。
///
/// 与 `lib/renderer/.../marketplace_scan.dart` 的 UI 版不同：本函数只产出
/// [MarketplaceEntry]（与 Flutter 模型无关），可在 core 子包直接单测。
///
/// 检测的子类型（与 marketplace_scan.dart 一致的契约）：
/// - `module/manifest.json` → module
/// - `agent/manifest.json` → agent
/// - `data/manifest.json` → data-source
/// - `config/config.json` → config
/// - `theme/theme.json` → theme
/// - `skill/*.md` → skill
/// - 根 `manifest.json` → 按 manifest.type 推断（未知→unknown）
(List<MarketplaceEntry>, Map<String, String>) scanPluginDir(
  String pluginsDir, {
  required String sourceId,
}) {
  final dir = Directory(pluginsDir);
  final infos = <MarketplaceEntry>[];
  final dirs = <String, String>{};
  if (!dir.existsSync()) return (infos, dirs);

  final usedIds = <String>{};

  for (final entity in dir.listSync()) {
    if (entity is! Directory) continue;
    if (p.basename(entity.path).startsWith('.')) continue;
    final folder = entity.path;

    final candidates = <String, String>{
      'module': 'module/manifest.json',
      'agent': 'agent/manifest.json',
      'data-source': 'data/manifest.json',
      'config': 'config/config.json',
      'theme': 'theme/theme.json',
      'root': 'manifest.json',
    };

    for (final entry in candidates.entries) {
      final mp = '${folder}/${entry.value}';
      final mf = File(mp);
      if (!mf.existsSync()) continue;
      try {
        final json =
            jsonDecode(mf.readAsStringSync()) as Map<String, dynamic>;
        final id = (json['id'] as String?)?.isNotEmpty == true
            ? json['id'] as String
            : p.basename(folder);
        final uniqueId = usedIds.contains(id) ? '$id-${entry.key}' : id;
        final type = (json['type'] as String?)?.isNotEmpty == true
            ? json['type'] as String
            : entry.key == 'root'
                ? 'unknown'
                : entry.key;
        infos.add(MarketplaceEntry(
          id: uniqueId,
          name: (json['name'] as String?)?.isNotEmpty == true
              ? json['name'] as String
              : uniqueId,
          type: type,
          dirPath: folder,
          sourceId: sourceId,
        ));
        dirs[uniqueId] = folder;
        usedIds.add(uniqueId);
      } catch (_) {
        // 解析失败的 manifest 跳过
      }
      break; // 一个文件夹只取首个匹配的子类型（与 UI 版多卡策略不同：scanner 取主类型）
    }

    // skill 分支
    final skillDir = Directory('$folder/skill');
    if (skillDir.existsSync()) {
      try {
        final md = skillDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.md'))
            .toList();
        if (md.isNotEmpty) {
          final id = p.basename(folder);
          infos.add(MarketplaceEntry(
            id: usedIds.contains(id) ? '$id-skill' : id,
            name: id,
            type: 'skill',
            dirPath: folder,
            sourceId: sourceId,
          ));
          dirs[id] = folder;
          usedIds.add(id);
        }
      } catch (_) {
        // skill 解析失败跳过
      }
    }
  }
  return (infos, dirs);
}

/// 扫描所有启用的市场源，发现插件列表。
///
/// [clone] 仅对 github 源调用；localDir 源直接扫 [MarketplaceSource.src] 目录。
/// [cacheDir] 为 github 克隆的基目录（每个源克隆到 `cacheDir/<owner>/<repo>`）。
///
/// 返回每个源的结果（含失败错误），调用方可据此展示「部分源不可用」。
Future<List<SourceScanResult>> scanSources(
  List<MarketplaceSource> sources, {
  required GithubCloner clone,
  String? cacheDir,
}) async {
  final results = <SourceScanResult>[];
  for (final src in sources) {
    if (!src.enabled) {
      results.add(SourceScanResult(src, const []));
      continue;
    }
    try {
      if (src.kind == MarketplaceSourceKind.localDir) {
        final (entries, _) = scanPluginDir(src.src, sourceId: src.id);
        results.add(SourceScanResult(src, entries));
      } else {
        // github 源：克隆到缓存目录后扫描。
        final gh = src.github;
        final base = cacheDir ??
            Directory.systemTemp
                .createTempSync('mkt_cache_')
                .path;
        final target = '$base/${gh.owner}/${gh.repo}';
        // 已克隆过则复用（幂等），避免重复网络。
        if (!Directory(target).existsSync()) {
          await clone(gh, target);
        }
        final (entries, _) = scanPluginDir(target, sourceId: src.id);
        results.add(SourceScanResult(src, entries));
      }
    } catch (e) {
      results.add(SourceScanResult(src, const [], e));
    }
  }
  return results;
}

/// 从源扫描结果汇总去重后的插件条目（按 id 去重，保留首次出现）。
List<MarketplaceEntry> collectEntries(List<SourceScanResult> results) {
  final out = <MarketplaceEntry>[];
  final seen = <String>{};
  for (final r in results) {
    for (final e in r.entries) {
      if (seen.add(e.id)) out.add(e);
    }
  }
  return out;
}
