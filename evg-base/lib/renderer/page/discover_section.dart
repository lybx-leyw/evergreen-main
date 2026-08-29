/// 发现外部插件列表（无 Scaffold/AppBar，由独立视图 [DiscoveredPluginsView] 承载）。
///
/// 这是「发现插件」能力的核心逻辑宿主：消费远程 registry 文件，自动列出
/// 可发现的外部插件并以与插件中心 [LocalPluginCard] 对齐的列表卡片
/// （[DiscoverPluginCard]）展示；点「安装」先弹权限确认闸，确认后触发
/// clone/release 下载 + manifest 落盘，点「删除」移除已安装插件。
///
/// 设计意图（2026-08-26 修订）：发现插件是**与「插件中心」并列的独立视图**
/// （路由 `/discover`，mode_rail 独立入口），而非插件中心的子区域。两者管理
/// 层次不同——插件中心管本地已装插件（启用/侧栏/卸载/排序），发现插件管外部
/// 可装插件的浏览与安装——故作为两个并列视图而非合并为单一页面。展示卡片风格
/// 刻意与插件中心一致（同款 Card / 图标容器 / 类型徽标 / 操作按钮布局）。
///
/// 加载器 [registryLoader] 默认读内置 asset `docs/plugin-registry/plugins.json`
/// （对应 dsh-market 的 awesome-dsh-plugin registry）。切换源只改这一处。
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:evergreen_base/core/services/github_stars.dart';
import 'package:evergreen_base/core/module/plugin_registry.dart';
import 'package:evergreen_base/core/module/github_source.dart';
import 'package:evergreen_base/core/services/github_clone.dart'
    show cloneGithub, CloneResult, CloneErrorType;
import 'package:evergreen_base/core/services/release_downloader.dart'
    show downloadRelease, ReleaseResult;
import 'package:evergreen_base/core/utils/python_env.dart' show pipInstallPackages;
import 'package:evergreen_base/renderer/components/shared/widgets/models.dart';
import 'package:evergreen_base/renderer/components/shared/widgets/permission_dialog.dart';
import 'package:evergreen_base/renderer/components/shared/widgets/ability_capability_bridge.dart';
import 'package:evergreen_base/renderer/page/market_view.dart'
    show registryPluginToDescriptor;
import 'package:evergreen_base/providers.dart';

/// 下载器签名：把 [GithubSource] 克隆到 [targetDir]，返回 [CloneResult]。
/// 默认实现 [cloneGithub]（真实 git clone，见 core/services/github_clone.dart）。
typedef PluginDownloader = Future<CloneResult> Function(
  GithubSource src,
  String targetDir,
);

/// star 批量拉取器签名（可注入，便于测试用 fake）。
/// 输入为插件来源 URL 列表，返回 `owner/repo -> stars`；失败返回空 map。
/// 默认实现走数据中枢（[registerGithubStars] + orchestrator.get）。
typedef StarFetcher = Future<Map<String, int>> Function(List<String> urls);

/// release 下载器签名（可注入，便于测试用 fake）。默认 [downloadRelease]。
typedef ReleaseDownloader = Future<ReleaseResult> Function(
  GithubSource src,
  String targetDir, {
  String? assetPattern,
  List<String>? platforms,
});

/// 默认 registry 加载器：读内置 asset 的 plugins.json。
Future<List<RegistryPlugin>> _defaultRegistryLoader() async {
  final body = await rootBundle.loadString('docs/plugin-registry/plugins.json');
  return parsePluginRegistry(body);
}

/// 发现插件子区域（无壳）。负责外部插件的浏览 + 安装/卸载。
class DiscoverSection extends ConsumerStatefulWidget {
  /// 下载实现（可注入，便于测试用 fake）。默认 [cloneGithub]。
  final PluginDownloader? cloner;

  /// 注册表加载器（可注入，便于测试用内存源）。默认读内置 asset。
  final Future<List<RegistryPlugin>> Function()? registryLoader;

  /// star 批量拉取器（可注入，便于测试用 fake）。默认走数据中枢。
  final StarFetcher? starFetcher;

  /// release 下载器（可注入，便于测试用 fake）。默认 [downloadRelease]。
  final ReleaseDownloader? releaseDownloader;

  /// 外部搜索词（可选）。提供后在列表内过滤（名称/描述/作者/id）。
  final String? searchQuery;

  const DiscoverSection({
    super.key,
    this.cloner,
    this.registryLoader,
    this.starFetcher,
    this.releaseDownloader,
    this.searchQuery,
  });

  @override
  ConsumerState<DiscoverSection> createState() => _DiscoverSectionState();
}

/// 默认 release 下载实现：调 [downloadRelease]。
Future<ReleaseResult> _defaultReleaseDownloader(
  GithubSource src,
  String targetDir, {
  String? assetPattern,
  List<String>? platforms,
}) {
  return downloadRelease(src, targetDir,
      assetPattern: assetPattern, platforms: platforms);
}

class _DiscoverSectionState extends ConsumerState<DiscoverSection> {
  List<RegistryPlugin>? _plugins;
  Object? _loadError;
  bool _loading = false;

  /// 当前类型筛选，'all' 表示全部（与插件中心 [MarketplaceSlot] 同款标签筛选）。
  String _typeFilter = 'all';

  /// 实时 star 数（`owner/repo -> stars`），覆盖 registry 静态 stars。
  final Map<String, int> _liveStars = {};

  /// 已克隆到本地 plugins/<id> 的插件 id。
  final Set<String> _installedIds = {};

  /// 正在下载的插件 id。
  final Set<String> _installingIds = {};

  /// 单个插件下载错误（id → 错误信息）。
  final Map<String, String> _errors = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final List<RegistryPlugin> list;
      if (widget.registryLoader != null) {
        list = await widget.registryLoader!();
      } else {
        list = await _defaultRegistryLoader();
      }
      if (!mounted) return;
      setState(() {
        _plugins = list;
        _loading = false;
      });
      // 首次加载后探测本地已存在的克隆目录。
      _reconcileInstalled();
      // 后台拉取实时 GitHub star 数（不阻塞展示，失败回退静态 stars）。
      _fetchStars(list);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _loading = false;
      });
    }
  }

  /// 计算某插件展示用的 star 数：优先实时拉取的 `owner/repo` 覆盖，回退静态值。
  int _liveStarsFor(RegistryPlugin p) {
    final url = p.installUrl;
    if (url != null && url.isNotEmpty) {
      try {
        final full = parseGithubSource(url).fullName;
        final v = _liveStars[full];
        if (v != null) return v;
      } catch (_) {
        // 非 GitHub URL：回退静态 stars。
      }
    }
    return p.stars ?? 0;
  }

  /// 把本地 plugins/<id> 已存在的仓库标记为「已安装」（刷新后保留状态）。
  void _reconcileInstalled() {
    final pluginsDir = ref.read(pluginsDirProvider);
    final dir = Directory(pluginsDir);
    if (!dir.existsSync()) return;
    final present = dir
        .listSync()
        .whereType<Directory>()
        .map((e) => e.uri.pathSegments.where((s) => s.isNotEmpty).last)
        .toSet();
    for (final p in _plugins ?? const <RegistryPlugin>[]) {
      if (present.contains(p.id)) {
        _installedIds.add(p.id);
      }
    }
    if (mounted) setState(() {});
  }

  /// 后台拉取各插件的实时 GitHub star 数（M6）。
  Future<void> _fetchStars(List<RegistryPlugin> plugins) async {
    final urls = <String>[];
    for (final p in plugins) {
      final url = p.installUrl;
      if (url != null && url.isNotEmpty) {
        urls.add(url);
      }
    }
    if (urls.isEmpty) return;
    try {
      final Map<String, int> result;
      if (widget.starFetcher != null) {
        result = await widget.starFetcher!(urls);
      } else {
        result = await _fetchStarsViaHub(urls);
      }
      if (!mounted || result.isEmpty) return;
      setState(() {
        _liveStars.addAll(result);
      });
    } catch (_) {
      // 静默：star 拉取失败不影响市场展示。
    }
  }

  /// 走数据中枢取 star：注册（若未注册）→ get（缓存优先）。
  Future<Map<String, int>> _fetchStarsViaHub(List<String> urls) async {
    final orch = ref.read(dataOrchestratorProvider);
    if (!orch.isRegistered(githubStarsType())) {
      registerGithubStars(orch, repoUrls: urls);
    }
    final stars = await orch.get(githubStarsType());
    return stars ?? const {};
  }

  /// 请求安装：先弹 fail-closed 权限确认闸，确认后才 [_install]。
  ///
  /// 与插件中心启用闸同源（[showPermissionConfirmDialog]），保证外部插件安装
  /// 前用户明确知晓其能力维度（Agent/数据/文件等）。取消/ESC/遮罩 → 不安装。
  Future<void> _requestInstall(RegistryPlugin p) async {
    if (!mounted) return;
    final desc = registryPluginToDescriptor(
      p,
      installed: _installedIds.contains(p.id),
      liveStars: _liveStars,
    );
    final dims = toCoreDims(desc.dimensions);
    final confirmed = await showPermissionConfirmDialog(
      context: context,
      pluginName: p.name,
      dims: dims,
      onConfirm: () => _install(p),
    );
    if (!confirmed) {
      debugPrint('[Discover] 用户取消安装 ${p.id}（权限闸未过）');
    }
  }

  /// 下载安装一个 registry 插件（M6）。
  ///
  /// **下载与否的唯一判据是 [RegistryPlugin.install] 是否为空**：
  /// - `install` 为空 → 文件随包分发，跳过下载，仅建目录后直走 [_writeManifest]。
  /// - `install` 非空 → 按 `install.strategy` 分派 clone / release 下载，再落盘 manifest。
  Future<void> _install(RegistryPlugin p) async {
    final pluginsDir = ref.read(pluginsDirProvider);
    final targetDir = '$pluginsDir/${p.id}';

    final needDownload = p.install != null && p.install!.isNotEmpty;

    if (!needDownload && p.manifest == null) {
      setState(() => _errors[p.id] = '该插件既无安装来源（install）也无本地资源（manifest）');
      return;
    }

    setState(() {
      _installingIds.add(p.id);
      _errors.remove(p.id);
    });
    try {
      if (needDownload) {
        final url = p.installUrl;
        if (url == null || url.isEmpty) {
          setState(() {
            _installingIds.remove(p.id);
            _errors[p.id] = '该插件缺少安装来源 URL（install.url）';
          });
          return;
        }
        final src = parseGithubSource(url);
        final downloader = widget.releaseDownloader ?? _defaultReleaseDownloader;
        if (p.installStrategy == PluginInstallStrategy.release) {
          final r = await downloader(src, targetDir,
              assetPattern: p.releaseAssetPattern, platforms: p.releasePlatforms);
          if (!r.success) {
            setState(() {
              _installingIds.remove(p.id);
              _errors[p.id] = r.error ?? 'release 下载失败';
            });
            return;
          }
        } else {
          final cloner = widget.cloner ?? cloneGithub;
          final result = await cloner(src, targetDir);
          if (!mounted) return;
          if (!result.success) {
            final msg = switch (result.errorType) {
              CloneErrorType.notFound => '仓库不存在（404）',
              CloneErrorType.authRequired => '需要认证（私有仓库）',
              CloneErrorType.timeout => '下载超时，请检查网络',
              _ => result.error ?? '下载失败',
            };
            setState(() {
              _installingIds.remove(p.id);
              _errors[p.id] = msg;
            });
            return;
          }
        }
      } else {
        Directory(targetDir).createSync(recursive: true);
      }

      if (!mounted) return;
      final manifestErr = await _writeManifest(p, targetDir);
      setState(() {
        _installedIds.add(p.id);
        _installingIds.remove(p.id);
        if (manifestErr != null) _errors[p.id] = manifestErr;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _installingIds.remove(p.id);
        _errors[p.id] = '安装失败: $e';
      });
    }
  }

  /// 按插件声明的 manifest 获取办法，把静态资源落盘到 `plugins/<id>/`。
  Future<String?> _writeManifest(RegistryPlugin p, String targetDir) async {
    final m = p.manifest;
    if (m == null) return null;

    try {
      switch (m.source) {
        case PluginManifestSource.inline:
          final content = m.inline!;
          final rel = manifestRelativePath(content['type'] as String?);
          if (rel == null) {
            return 'manifest 缺少 type，无法确定落盘位置';
          }
          final dest = File('$targetDir/$rel');
          dest.parent.createSync(recursive: true);
          dest.writeAsStringSync(jsonEncode(content));
        case PluginManifestSource.local:
          final err = await _copyLocalAssets(m.path!, targetDir);
          if (err != null) return err;
        case PluginManifestSource.github:
          final err = _copyGithubAssets(m.path!, targetDir);
          if (err != null) return err;
      }
      final reqErr = await _installRequirements(p, targetDir);
      if (reqErr != null) return reqErr;
      return null;
    } catch (e) {
      return 'manifest 落盘失败: $e';
    }
  }

  /// 安装 manifest 声明的 Python 依赖（M6 · 方案 A）。
  Future<String?> _installRequirements(RegistryPlugin p, String targetDir) async {
    final rel = manifestRelativePath(p.manifest?.type ?? p.lattice);
    if (rel == null) return null;
    final manifestFile = File('$targetDir/$rel');
    if (!manifestFile.existsSync()) return null;

    List<String> reqs;
    try {
      final json =
          jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
      final raw = json['requirements'];
      if (raw is! List || raw.isEmpty) return null;
      reqs = raw.whereType<String>().toList();
      if (reqs.isEmpty) return null;
    } catch (_) {
      return null;
    }

    final ok = await pipInstallPackages(reqs);
    if (ok) return null;
    return '依赖安装失败：${reqs.join(', ')}（可稍后在「发现插件」页重装重试）';
  }

  /// 把 `docs/plugin-registry/<assetPath>` 下的本地静态资源复制到 [targetDir]。
  Future<String?> _copyLocalAssets(String assetPath, String targetDir) async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final prefix = 'docs/plugin-registry/$assetPath/';
      final keys = manifest
          .listAssets()
          .where((k) => k.startsWith(prefix))
          .where((k) => k.substring(prefix.length).isNotEmpty)
          .toList();
      if (keys.isEmpty) {
        return '本地资源目录为空: $prefix';
      }
      for (final key in keys) {
        final rel = key.substring(prefix.length);
        final out = File('$targetDir/$rel');
        out.parent.createSync(recursive: true);
        final data = await rootBundle.load(key);
        out.writeAsBytesSync(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      }
      return null;
    } catch (e) {
      return '复制本地资源失败: $e';
    }
  }

  /// 把已 clone 仓库内的资源目录内容复制到 [targetDir] 根（`github` 源）。
  String? _copyGithubAssets(String srcRelPath, String targetDir) {
    try {
      final norm = srcRelPath.replaceAll('\\', '/').replaceAll(RegExp(r'^/+'), '');
      final srcDir = Directory('$targetDir/$norm');
      if (!srcDir.existsSync()) {
        return '仓库内资源目录不存在: $norm';
      }

      final files = <File>[];
      _collectFiles(srcDir, files);
      if (files.isEmpty) {
        return '仓库内资源目录为空: $norm';
      }
      for (final f in files) {
        final rel = f.path.substring(srcDir.path.length).replaceAll('\\', '/');
        final dest = File('$targetDir${rel.startsWith('/') ? rel : '/$rel'}');
        dest.parent.createSync(recursive: true);
        f.copySync(dest.path);
      }
      return null;
    } catch (e) {
      return '复制 GitHub 资源失败: $e';
    }
  }

  /// 递归收集目录下所有文件（用于目录复制）。
  void _collectFiles(Directory dir, List<File> out) {
    for (final e in dir.listSync(followLinks: false)) {
      if (e is File) {
        out.add(e);
      } else if (e is Directory) {
        _collectFiles(e, out);
      }
    }
  }

  /// 删除已安装插件（M6 · 补 5）。
  Future<void> _uninstall(PluginDescriptor desc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除「${desc.name}」？'),
        content: const Text('将删除插件目录中的所有文件，此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final pluginsDir = ref.read(pluginsDirProvider);
    final dir = Directory('$pluginsDir/${desc.id}');
    try {
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
      setState(() {
        _installedIds.remove(desc.id);
        _errors.remove(desc.id);
      });
    } catch (e) {
      setState(() => _errors[desc.id] = '删除失败: $e');
    }
  }

  /// 按类型标签 + 搜索词过滤（名称 / 描述 / 作者 / id）。
  ///
  /// 类型判定复用 [_pluginTypeKey]（lattice 权威声明，与卡片徽标同口径），
  /// 'all' 不筛类型；搜索词为空时仅做类型过滤。
  List<RegistryPlugin> _filteredPlugins() {
    var all = _plugins ?? const <RegistryPlugin>[];
    if (_typeFilter != 'all') {
      all = all.where((p) => _pluginTypeKey(p.lattice) == _typeFilter).toList();
    }
    final q = widget.searchQuery?.trim().toLowerCase();
    if (q == null || q.isEmpty) return all;
    return all.where((p) {
      return p.name.toLowerCase().contains(q) ||
          p.description.toLowerCase().contains(q) ||
          (p.author ?? '').toLowerCase().contains(q) ||
          p.id.toLowerCase().contains(q);
    }).toList();
  }

  /// 类型标签筛选条（与插件中心 [MarketplaceSlot._buildTypeFilterChips] 同款）：
  /// 全部 / 模块 / 皮肤 / 数据源 / Agent / 技能 / 主题 / 配置。
  Widget _buildTypeFilterChips() {
    const filters = <(String, String)>[
      ('all', '全部'),
      ('module', '模块'),
      ('skin', '皮肤'),
      ('data-source', '数据源'),
      ('agent', 'Agent'),
      ('skill', '技能'),
      ('theme', '主题'),
      ('config', '配置'),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          for (final (value, label) in filters)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(label),
                selected: _typeFilter == value,
                onSelected: (_) => setState(() => _typeFilter = value),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 加载中且无错误：用静态占位（避免持续动画导致 pumpAndSettle 超时）。
    if (_plugins == null && _loadError == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('正在加载发现源…', style: TextStyle(fontSize: 13)),
        ),
      );
    }

    final plugins = _filteredPlugins();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 类型标签筛选条（与插件中心同款：全部/模块/皮肤/数据源/Agent/技能/主题/配置）
        _buildTypeFilterChips(),
        Expanded(
          child: Stack(
            children: [
              plugins.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.explore_off_outlined,
                              size: 48, color: Theme.of(context).disabledColor),
                          const SizedBox(height: 12),
                          Text(
                            _loadError != null
                                ? '发现源加载失败'
                                : _typeFilter != 'all' ||
                                        (widget.searchQuery?.isNotEmpty ??
                                            false)
                                    ? '没有匹配该筛选条件的插件'
                                    : '暂无可发现的外部插件',
                            style: TextStyle(
                                color: Theme.of(context).disabledColor),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: plugins.length,
                      itemBuilder: (context, index) {
                        final p = plugins[index];
                        final installed = _installedIds.contains(p.id);
                        final installing = _installingIds.contains(p.id);
                        final error = _errors[p.id];
                        return DiscoverPluginCard(
                          plugin: p,
                          stars: _liveStarsFor(p),
                          installed: installed,
                          installing: installing,
                          error: error,
                          onInstall: installed ? null : () => _requestInstall(p),
                          onUninstall: () => _uninstall(
                            PluginDescriptor(
                              id: p.id,
                              name: p.name,
                              description: p.description,
                              version: p.version,
                            ),
                          ),
                        );
                      },
                    ),
          // 下载错误浮层（角标提示）。
          if (_errors.isNotEmpty)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: _ErrorBanner(
                errors: _errors,
                onDismiss: () => setState(() => _errors.clear()),
              ),
            ),
        ],
        ),
        ),
      ],
    );
  }
}

/// 发现插件的单个展示卡片 —— 视觉风格与插件中心 [LocalPluginCard] 对齐
/// （同一套 Card / 图标容器 / 类型徽标 / 描述 / 操作按钮布局），
/// 区别在于动作是「安装 / 已安装 / 删除」而非「启用 / 侧栏 / 卸载」。
class DiscoverPluginCard extends StatelessWidget {
  final RegistryPlugin plugin;
  final int stars;
  final bool installed;
  final bool installing;
  final String? error;
  final VoidCallback? onInstall;
  final VoidCallback? onUninstall;

  const DiscoverPluginCard({
    super.key,
    required this.plugin,
    this.stars = 0,
    this.installed = false,
    this.installing = false,
    this.error,
    this.onInstall,
    this.onUninstall,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meta = _pluginTypeMeta(plugin.lattice);
    final stars = this.stars;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: theme.dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 顶部：图标 + 名称 + 类型标签 + 安装/已安装按钮
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    meta.icon,
                    size: 22,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plugin.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'v${plugin.version} · ${plugin.id}',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                // 安装 / 已安装 / 删除
                _buildAction(theme),
              ],
            ),
            if (plugin.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                plugin.description,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 8),
            // 底部信息标签 + 作者 + star（窄屏水平滚动兜底，同 LocalPluginCard）。
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _InfoBadge(label: meta.label, icon: meta.icon),
                  const SizedBox(width: 8),
                  if (plugin.author != null && plugin.author!.isNotEmpty) ...[
                    _InfoBadge(
                      label: plugin.author!,
                      icon: Icons.person_outline,
                    ),
                    const SizedBox(width: 8),
                  ],
                  _InfoBadge(
                    label: '$stars',
                    icon: Icons.star_border,
                  ),
                  if (error != null) ...[
                    const SizedBox(width: 8),
                    _InfoBadge(
                      label: '安装失败',
                      icon: Icons.error_outline,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAction(ThemeData theme) {
    if (installed) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_outline,
                    size: 14, color: theme.colorScheme.primary),
                const SizedBox(width: 4),
                Text(
                  '已安装',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (onUninstall != null) ...[
            const SizedBox(width: 6),
            IconButton(
              tooltip: '删除插件',
              icon: Icon(Icons.delete_outline,
                  size: 16, color: theme.colorScheme.error),
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              padding: EdgeInsets.zero,
              onPressed: onUninstall,
            ),
          ],
        ],
      );
    }
    if (installing) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (onInstall != null) {
      return FilledButton(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        onPressed: onInstall,
        child: const Text('安装', style: TextStyle(fontSize: 12)),
      );
    }
    return const SizedBox.shrink();
  }
}

/// registry `lattice`（插件类型）→ 筛选 key（与 [MarketplaceSlot] 类型筛选口径一致）。
///
/// 与 [_pluginTypeMeta] 共享同一判定集合：theme/module(static-web/web-bridged)/
/// skin/data-source/agent(agent-tool)/skill/config；未知 lattice 归入 `other`
/// （筛选条无对应标签，仅「全部」可见，与既有卡片兜底「插件」一致）。
String _pluginTypeKey(String? lattice) => switch (lattice) {
      'theme' => 'theme',
      'module' || 'static-web' || 'web-bridged' => 'module',
      'skin' => 'skin',
      'data-source' => 'data-source',
      'agent' || 'agent-tool' => 'agent',
      'skill' => 'skill',
      'config' => 'config',
      _ => 'other',
    };

/// registry `lattice`（插件类型）→ （中文标签, 图标）。与插件中心类型口径近似。
({String label, IconData icon}) _pluginTypeMeta(String? lattice) =>
    switch (lattice) {
      'theme' => (label: '主题', icon: Icons.palette_outlined),
      'module' || 'static-web' || 'web-bridged' =>
        (label: '模块', icon: Icons.extension_outlined),
      'skin' => (label: '皮肤', icon: Icons.brush_outlined),
      'data-source' => (label: '数据源', icon: Icons.storage_outlined),
      'agent' || 'agent-tool' => (label: 'Agent', icon: Icons.smart_toy_outlined),
      'config' => (label: '配置', icon: Icons.settings_outlined),
      'skill' => (label: '技能', icon: Icons.auto_fix_high_outlined),
      _ => (label: '插件', icon: Icons.extension_outlined),
    };

/// 小型信息标签（与 LocalPluginCard._InfoBadge 同款样式）。
class _InfoBadge extends StatelessWidget {
  final String label;
  final IconData icon;

  const _InfoBadge({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Theme.of(context).disabledColor),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
                fontSize: 10, color: Theme.of(context).disabledColor),
          ),
        ],
      ),
    );
  }
}

/// 发现区下载错误浮层角标（与 [MarketView] 视觉一致）。
class _ErrorBanner extends StatelessWidget {
  final Map<String, String> errors;
  final VoidCallback onDismiss;

  const _ErrorBanner({required this.errors, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline,
              size: 16, color: theme.colorScheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              errors.entries.map((e) => '${e.key}: ${e.value}').join('；'),
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
          TextButton(
            onPressed: onDismiss,
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.onErrorContainer,
            ),
            child: const Text('知道了', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
