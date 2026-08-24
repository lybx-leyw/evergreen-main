/// 插件市场 registry 数据源（M6-0，纯逻辑）。
///
/// 对应 dsh-market 的「远程 registry 文件自动发现」模式：市场每次打开时
/// 实时拉取一个 `plugins.json`，解析成插件清单并展示。第三方作者向 registry
/// 仓库提 PR → 市场自动拾取（飞轮：非组成员产出的插件被发现）。
///
/// 本文件只做可单测的 JSON 解析与列表规整，不含网络（在主包完成 fetch）。
///
/// 设计要点（plugin-ecosphere.md §3 生态三则）：
/// - fail-closed：非法条目抛 [FormatException]，不会静默变成「空列表」。
/// - 未知字段静默忽略；重复 id 按首次出现保留。
library;

import 'dart:convert';

/// manifest 获取来源（M6 · 补 4/6）。
///
/// 每个插件在 registry 里声明自己的 manifest「怎么来」：
/// - [inline]：manifest 直接内嵌在 registry 条目里（硬编码，无需网络）。
/// - [local]：manifest 指向本地静态资源路径（`docs/plugin-registry/` 下），
///   安装时从本地复制到 `plugins/<id>/`。
/// - [github]：manifest 指向 GitHub 仓库内的路径，安装时从仓库拉取。
enum PluginManifestSource { inline, local, github }

/// 插件下载办法（M6 · 补 5）。
///
/// 每个插件在 registry 的 `install` 里声明「怎么拿到它的文件」：
/// - [source]：`git clone` 源码仓库（默认，适合无 release 的库，如 Python 包）。
/// - [release]：下载 GitHub release 的二进制 asset（适合发布二进制的插件，如 Go 程序）。
enum PluginInstallStrategy { source, release }

/// 从 `install.strategy` 字符串解析下载办法（fail-closed）。
///
/// 缺省/空 → [PluginInstallStrategy.source]；未知值 → 抛 [FormatException]。
PluginInstallStrategy parseInstallStrategy(String? raw) {
  if (raw == null || raw.isEmpty) return PluginInstallStrategy.source;
  switch (raw) {
    case 'source':
      return PluginInstallStrategy.source;
    case 'release':
      return PluginInstallStrategy.release;
    default:
      throw FormatException('未知 install.strategy: $raw（应为 source 或 release）');
  }
}

/// 插件 manifest 的获取办法声明。
///
/// 解决「外部 GitHub 仓库没有 Evergreen manifest」的协议鸿沟：registry 条目
/// 通过本对象声明「该插件的 manifest 在哪、怎么拿」，安装器据此落盘。
///
/// 三种形态：
/// ```json
/// // 硬编码：manifest 直接内嵌
/// { "source": "inline", "json": { "type": "module", ... } }
///
/// // 本地静态资源：指向 docs/plugin-registry/ 下的相对路径
/// { "source": "local", "path": "assets/zjucrawler/data/manifest.json" }
///
/// // GitHub 仓库内路径
/// { "source": "github", "repo": "owner/repo", "path": "evergreen/manifest.json" }
/// ```
class PluginManifest {
  final PluginManifestSource source;

  /// [PluginManifestSource.inline]：内嵌的完整 manifest（module/data 等）。
  final Map<String, dynamic>? inline;

  /// [PluginManifestSource.local]：本地静态资源相对路径（相对 docs/plugin-registry/）。
  final String? path;

  /// [PluginManifestSource.github]：仓库全名（owner/repo）。
  final String? repo;

  const PluginManifest.inline(Map<String, dynamic> json)
      : source = PluginManifestSource.inline,
        inline = json,
        path = null,
        repo = null;

  const PluginManifest.local(String path)
      : source = PluginManifestSource.local,
        inline = null,
        path = path,
        repo = null;

  const PluginManifest.github(String repo, String path)
      : source = PluginManifestSource.github,
        inline = null,
        path = path,
        repo = repo;

  factory PluginManifest.fromJson(Map<String, dynamic> json) {
    final source = json['source'] as String?;
    switch (source) {
      case 'inline':
        final inline = json['json'];
        if (inline is! Map) {
          throw FormatException('manifest.source=inline 需要 json 对象');
        }
        return PluginManifest.inline(Map<String, dynamic>.from(inline));
      case 'local':
        final path = json['path'] as String?;
        if (path == null || path.isEmpty) {
          throw FormatException('manifest.source=local 需要 path');
        }
        return PluginManifest.local(path);
      case 'github':
        final repo = json['repo'] as String?;
        final path = json['path'] as String?;
        if (repo == null || repo.isEmpty || path == null || path.isEmpty) {
          throw FormatException('manifest.source=github 需要 repo 和 path');
        }
        return PluginManifest.github(repo, path);
      default:
        throw FormatException(
            '未知 manifest.source: $source（应为 inline / local / github）');
    }
  }

  Map<String, dynamic> toJson() => switch (source) {
        PluginManifestSource.inline => {'source': 'inline', 'json': inline},
        PluginManifestSource.local => {'source': 'local', 'path': path},
        PluginManifestSource.github =>
          {'source': 'github', 'repo': repo, 'path': path},
      };

  /// manifest 的插件类型（inline 时读 json['type']；local/github 时未知返回 null）。
  ///
  /// Evergreen 的 manifest 类型：`module` / `data-source` / `agent` 等。
  /// 决定落盘到 `plugins/<id>/<type>/manifest.json` 的哪一层。
  String? get type => inline?['type'] as String?;
}

/// 计算 manifest 落盘到插件目录内的相对路径（纯函数）。
///
/// [manifestType] 为 manifest 的 `type`（`module` / `data-source` / `agent`...）。
/// 返回形如 `module/manifest.json` 的相对路径；type 为空时返回 null（无法落盘）。
///
/// **特例**：`data-source` 落盘到 `data/manifest.json`（与 marketplace_scan.dart 的
/// `data-source` subType 映射到 `data/` 目录、register_data_source.dart 读
/// `data/manifest.json` 的约定一致），而非字面的 `data-source/`。
String? manifestRelativePath(String? manifestType) {
  if (manifestType == null || manifestType.isEmpty) return null;
  final dir = manifestType == 'data-source' ? 'data' : manifestType;
  return '$dir/manifest.json';
}

/// registry 中单个插件的轻量描述（core 层不依赖 renderer/flutter）。
///
/// 仅携带市场展示与后续上架所需的字段；渲染层再映射为 [PluginDescriptor]。
class RegistryPlugin {
  final String id;
  final String name;
  final String description;
  final String? longDescription;
  final String? author;
  final String version;
  final String? repo;
  final String? homepage;
  final String? license;
  final String? lattice;

  /// 能力维度标签（如 data / agent / ui），原始字符串，渲染层再映射。
  final List<String> dimensions;

  /// 安装来源：{ "type": "github", "url": "..." } 等。
  final Map<String, dynamic>? install;

  /// 下载办法（M6 · 补 5）：`source`（clone 源码，默认）或 `release`（下载 release asset）。
  final PluginInstallStrategy installStrategy;

  /// manifest 获取办法（M6 · 补 4）：声明该插件的 manifest 内嵌还是下载。
  /// 为 null 时回退旧逻辑（clone 源码，无 manifest 声明）。
  final PluginManifest? manifest;

  final int installCount;
  final double rating;
  final int? stars;

  const RegistryPlugin({
    required this.id,
    required this.name,
    this.description = '',
    this.longDescription,
    this.author,
    this.version = '1.0.0',
    this.repo,
    this.homepage,
    this.license,
    this.lattice,
    this.dimensions = const [],
    this.install,
    this.installStrategy = PluginInstallStrategy.source,
    this.manifest,
    this.installCount = 0,
    this.rating = 0.0,
    this.stars,
  });

  /// 安装 URL（github 类型取 install['url']）；无则回退 repo。
  String? get installUrl {
    final inst = install;
    if (inst != null && inst['type'] == 'github' && inst['url'] is String) {
      return inst['url'] as String;
    }
    return repo;
  }

  /// release 策略下的 asset 匹配片段（可选）。
  ///
  /// 用于在 GitHub release 的多个 asset 里筛选目标（如 `windows-amd64`）。
  /// 支持平台占位符 `{platform}`/`{arch}`。为空时由下载器按当前平台推断。
  String? get releaseAssetPattern => install?['assetPattern'] as String?;

  /// release 策略下支持的平台白名单（可选），如 `["windows","macos","linux"]`。
  ///
  /// 为空表示不限制平台。当前平台不在白名单内时，安装直接报错（如安卓遇
  /// 桌面专用 CLI 插件）。值规范化为小写。
  List<String>? get releasePlatforms {
    final raw = install?['platforms'];
    if (raw is! List) return null;
    final list = raw.whereType<String>().map((s) => s.toLowerCase()).toList();
    return list.isEmpty ? null : list;
  }

  factory RegistryPlugin.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    if (id == null || id.isEmpty) {
      throw FormatException('registry 插件条目缺少 id');
    }
    final name = json['name'] as String?;
    if (name == null || name.isEmpty) {
      throw FormatException('registry 插件 $id 缺少 name');
    }
    final dimsRaw = json['dimensions'];
    final dimensions = dimsRaw is List
        ? dimsRaw.whereType<String>().toList()
        : const <String>[];
    final install = json['install'];
    final installMap = install is Map ? Map<String, dynamic>.from(install) : null;
    final manifestRaw = json['manifest'];
    return RegistryPlugin(
      id: id,
      name: name,
      description: json['description'] as String? ?? '',
      longDescription: json['longDescription'] as String?,
      author: json['author'] as String?,
      version: json['version'] as String? ?? '1.0.0',
      repo: json['repo'] as String?,
      homepage: json['homepage'] as String?,
      license: json['license'] as String?,
      lattice: json['lattice'] as String?,
      dimensions: dimensions,
      install: installMap,
      // fail-closed：非法 strategy 在解析时即抛，而非访问时。
      installStrategy: parseInstallStrategy(installMap?['strategy'] as String?),
      manifest: manifestRaw is Map
          ? PluginManifest.fromJson(manifestRaw.cast<String, dynamic>())
          : null,
      installCount: json['installCount'] as int? ?? 0,
      rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
      stars: json['stars'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        if (longDescription != null) 'longDescription': longDescription,
        if (author != null) 'author': author,
        'version': version,
        if (repo != null) 'repo': repo,
        if (homepage != null) 'homepage': homepage,
        if (license != null) 'license': license,
        if (lattice != null) 'lattice': lattice,
        'dimensions': dimensions,
        if (install != null) 'install': install,
        if (manifest != null) 'manifest': manifest!.toJson(),
        'installCount': installCount,
        'rating': rating,
        if (stars != null) 'stars': stars,
      };
}

/// 解析 registry 文件内容（纯函数，fail-closed）。
///
/// [body] 预期结构：
/// ```json
/// { "plugins": [ {条目1}, {条目2}, ... ] }
/// ```
///
/// 规则：
/// - 顶层非对象 / 缺 `plugins` / `plugins` 非数组 → 抛 [FormatException]。
/// - 单条非法 → 透传其 [FormatException]（fail-closed，不全集跳过）。
/// - 按 `id` 去重，保留首次出现。
List<RegistryPlugin> parsePluginRegistry(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! Map<String, dynamic>) {
    throw FormatException('registry 顶层必须是对象');
  }
  final list = decoded['plugins'];
  if (list is! List) {
    throw FormatException('registry 缺少 plugins 数组');
  }
  final out = <RegistryPlugin>[];
  final seen = <String>{};
  for (final item in list) {
    if (item is! Map) {
      throw FormatException('registry 插件条目必须是对象');
    }
    final plugin = RegistryPlugin.fromJson(item.cast<String, dynamic>());
    if (seen.add(plugin.id)) {
      out.add(plugin);
    }
  }
  return out;
}
