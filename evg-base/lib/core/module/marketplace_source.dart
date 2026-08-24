/// 市场源接入（M5-1，纯逻辑）。
///
/// 市场层负责「分销」：从多个源（GitHub 仓库 / 本地目录）自动发现插件清单。
/// 本文件只做可单测的源解析与列表规整，不含网络克隆（在主包完成）。
///
/// 设计要点（来自 plugin-ecosphere.md §3 生态三则）：
/// - fail-closed：非法源描述抛 [FormatException]，不会静默变成「空列表」。
/// - 未知字段静默忽略；重复源按 `id` 去重，保留首次出现。
library;

import 'dart:convert';

import 'github_source.dart';

/// 市场源类型。
enum MarketplaceSourceKind {
  /// GitHub 仓库源（owner/repo@ref）。
  github,

  /// 本地目录源（已克隆 / 解压到磁盘的插件目录）。
  localDir,
}

/// 从字符串解析源类型（不区分大小写）。
MarketplaceSourceKind? parseMarketplaceSourceKind(String raw) {
  for (final k in MarketplaceSourceKind.values) {
    if (k.name.toLowerCase() == raw.toLowerCase()) return k;
  }
  return null;
}

/// 单个市场源（插件发现入口）。
///
/// 对应市场配置里的一条记录，例如：
/// ```json
/// { "id": "zju-official", "kind": "github", "src": "github:ZJU-Evergreen/plugins" }
/// { "id": "local-dev",    "kind": "localDir", "src": "/abs/path/to/plugins" }
/// ```
class MarketplaceSource {
  /// 稳定标识（用于去重与持久化）。
  final String id;

  final MarketplaceSourceKind kind;

  /// 原始源描述：
  /// - github → [parseGithubSource] 接受的形式
  /// - localDir → 绝对/相对目录路径
  final String src;

  /// 人类可读名称（可空，缺省用 [id]）。
  final String? name;

  /// 是否启用（缺省 true）。
  final bool enabled;

  const MarketplaceSource({
    required this.id,
    required this.kind,
    required this.src,
    this.name,
    this.enabled = true,
  });

  factory MarketplaceSource.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    if (id == null || id.isEmpty) {
      throw FormatException('marketplace 源缺少 id');
    }
    final kindRaw = json['kind'] as String?;
    if (kindRaw == null) {
      throw FormatException('marketplace 源 $id 缺少 kind');
    }
    final kind = parseMarketplaceSourceKind(kindRaw);
    if (kind == null) {
      throw FormatException('marketplace 源 $id 的 kind 非法: $kindRaw');
    }
    final src = json['src'] as String?;
    if (src == null || src.isEmpty) {
      throw FormatException('marketplace 源 $id 缺少 src');
    }
    return MarketplaceSource(
      id: id,
      kind: kind,
      src: src,
      name: json['name'] as String?,
      enabled: json['enabled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'src': src,
        if (name != null) 'name': name,
        'enabled': enabled,
      };

  /// 仅对 GitHub 源有意义；其它类型抛 [StateError]。
  GithubSource get github {
    if (kind != MarketplaceSourceKind.github) {
      throw StateError('源 $id 不是 github 源');
    }
    return parseGithubSource(src);
  }

  @override
  String toString() => 'MarketplaceSource($id, ${kind.name}, $src)';
}

/// 解析市场源清单（纯函数，fail-closed）。
///
/// [body] 是配置 JSON 字符串，预期结构：
/// ```json
/// { "sources": [ {源1}, {源2}, ... ] }
/// ```
///
/// 规则：
/// - 顶层非对象 / 缺 `sources` / `sources` 非数组 → 抛 [FormatException]。
/// - 单条源非法 → 透传其 [FormatException]（fail-closed，不全集跳过）。
/// - 按 `id` 去重，保留首次出现；`enabled` 为 false 的保留但标记未启用。
List<MarketplaceSource> parseMarketplaceSources(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! Map<String, dynamic>) {
    throw FormatException('marketplace 配置顶层必须是对象');
  }
  final list = decoded['sources'];
  if (list is! List) {
    throw FormatException('marketplace 配置缺少 sources 数组');
  }
  final out = <MarketplaceSource>[];
  final seen = <String>{};
  for (final item in list) {
    if (item is! Map) {
      throw FormatException('marketplace 源条目必须是对象');
    }
    final src = MarketplaceSource.fromJson(item.cast<String, dynamic>());
    if (seen.add(src.id)) {
      out.add(src);
    }
  }
  return out;
}

/// 仅返回启用中的源（UI / 扫描器直接用）。
List<MarketplaceSource> enabledSources(List<MarketplaceSource> all) =>
    all.where((s) => s.enabled).toList();
