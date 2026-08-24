/// 插件发现页（M6 自动发现 + 下载安装）。
///
/// 消费远程 registry 文件（默认打包在 assets 的 docs/plugin-registry/plugins.json，
/// 对应 dsh-market 的 awesome-dsh-plugin registry），实时解析并展示可被发现的插件；
/// 第三方作者向 registry 仓库提 PR → 市场自动拾取（飞轮）。
///
/// 下载安装：点「安装」→ 解析插件 install URL 为 [GithubSource] → 调 [cloneGithub]
/// 把仓库克隆到副本 plugins/<id> 目录；成功后标记「已安装」。底层 git clone 来自
/// `core/services/github_clone.dart`，与现有 [scanSources] 设计一致。
///
/// 后续可把 registry 源换成网络 URL（REGISTRY_URL 环境变量 / 设置项覆盖），
/// 本页加载器抽成 [buildRegistryLoader]，切换源只改这一处。
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
import 'package:evergreen_base/core/utils/python_env.dart'
    show pipInstallPackages;
import 'package:evergreen_base/renderer/components/shared/widgets/models.dart';
import 'package:evergreen_base/renderer/page/market_view.dart';
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

/// 发现页主体：标题 + [MarketView]（带 registry 加载器 + 真实下载安装）。
class DiscoveredPluginsView extends ConsumerStatefulWidget {
  /// 下载实现（可注入，便于测试用 fake）。默认 [cloneGithub]（真实 git clone）。
  final PluginDownloader cloner;

  /// 注册表加载器（可注入，便于测试用内存源）。默认读内置 asset。
  final Future<List<RegistryPlugin>> Function()? registryLoader;

  /// star 批量拉取器（可注入，便于测试用 fake）。默认走数据中枢（见
  /// [_DiscoveredPluginsViewState._fetchStarsViaHub]）。
  final StarFetcher? starFetcher;

  /// release 下载器（可注入，便于测试用 fake）。默认 [downloadRelease]。
  final ReleaseDownloader releaseDownloader;

  DiscoveredPluginsView({
    super.key,
    PluginDownloader? cloner,
    this.registryLoader,
    this.starFetcher,
    ReleaseDownloader? releaseDownloader,
  })  : cloner = cloner ?? cloneGithub,
        releaseDownloader = releaseDownloader ?? _defaultReleaseDownloader;

  @override
  ConsumerState<DiscoveredPluginsView> createState() =>
      _DiscoveredPluginsViewState();
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

class _DiscoveredPluginsViewState extends ConsumerState<DiscoveredPluginsView> {
  List<RegistryPlugin>? _plugins;
  Object? _loadError;
  bool _loading = false;

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
        final body =
            await rootBundle.loadString('docs/plugin-registry/plugins.json');
        list = parsePluginRegistry(body);
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
  ///
  /// 对每个能解析出来源 URL 的插件收集 URL，批量拉取；成功后写入 [_liveStars]。
  /// 默认走数据中枢（[registerGithubStars] + orchestrator.get，享受缓存/TTL/状态）；
  /// 注入 [DiscoveredPluginsView.starFetcher] 时用注入实现（测试用）。
  /// 任何失败静默忽略（保持 registry 静态 stars），不阻断市场展示。
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
  ///
  /// 网络失败时 orchestrator 返回 null（fetcher 抛异常被捕获），此处返回空 map，
  /// 上层回退静态 stars。满足「网络失败返回空」的约定。
  Future<Map<String, int>> _fetchStarsViaHub(List<String> urls) async {
    final orch = ref.read(dataOrchestratorProvider);
    if (!orch.isRegistered(githubStarsType())) {
      registerGithubStars(orch, repoUrls: urls);
    }
    final stars = await orch.get(githubStarsType());
    return stars ?? const {};
  }

  /// 下载安装一个 registry 插件（M6）。
  Future<void> _install(RegistryPlugin p) async {
    final url = p.installUrl;
    if (url == null || url.isEmpty) {
      setState(() => _errors[p.id] = '该插件缺少安装来源（install.url）');
      return;
    }
    final pluginsDir = ref.read(pluginsDirProvider);
    final targetDir = '$pluginsDir/${p.id}';

    setState(() {
      _installingIds.add(p.id);
      _errors.remove(p.id);
    });
    try {
      final src = parseGithubSource(url);
      // M6 · 补 5：按 install.strategy 分派下载办法。
      final bool ok;
      if (p.installStrategy == PluginInstallStrategy.release) {
        final r = await widget.releaseDownloader(src, targetDir,
            assetPattern: p.releaseAssetPattern,
            platforms: p.releasePlatforms);
        ok = r.success;
        if (!ok) {
          setState(() {
            _installingIds.remove(p.id);
            _errors[p.id] = r.error ?? 'release 下载失败';
          });
          return;
        }
      } else {
        final result = await widget.cloner(src, targetDir);
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
        ok = true;
      }
      if (!mounted) return;
      // M6 · 补 4：下载成功后，按 manifest 声明落盘 manifest.json。
      // inline → 直接写内嵌 json；remote → 下载后写。失败仅记录，不阻断「已安装」。
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
  ///
  /// - [PluginManifestSource.inline]：直接写内嵌 json 到 `<type>/manifest.json`。
  /// - [PluginManifestSource.local]：把 `docs/plugin-registry/<path>` 下的资源
  ///   （manifest + 适配壳等）整体复制到 `plugins/<id>/`（AssetManifest 枚举）。
  /// - [PluginManifestSource.github]：从 GitHub 仓库下载 `<path>` 下的资源。
  /// - 未声明 manifest（null）：返回 null（走旧 clone 逻辑，不落 manifest）。
  ///
  /// 返回错误信息；成功返回 null。任何失败都不抛异常（不阻断「已安装」）。
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
          // 仓库已 clone 到 targetDir（install.strategy=source 时），
          // path 指向仓库内的资源目录，把其内容复制（上移）到 targetDir 根。
          final err = _copyGithubAssets(m.path!, targetDir);
          if (err != null) return err;
      }
      // M6 · 方案 A：资源落盘后，若 manifest 声明了 requirements，自动补齐依赖。
      final reqErr = await _installRequirements(p, targetDir);
      if (reqErr != null) return reqErr;
      return null;
    } catch (e) {
      return 'manifest 落盘失败: $e';
    }
  }

  /// 安装 manifest 声明的 Python 依赖（M6 · 方案 A）。
  ///
  /// 读取落盘的 `<type>/manifest.json` 顶层 `requirements` 数组，用嵌入式 Python
  /// 执行 `pip install`。无声明/安装失败返回错误信息（成功返回 null）；失败不抛。
  Future<String?> _installRequirements(RegistryPlugin p, String targetDir) async {
    // 定位落盘的 manifest：local/github 来源按 [p.lattice]（data-source→data/
    // module→module/）；inline 来源按内嵌 manifest 的 type。与 _writeManifest 落盘
    // 位置对齐。
    final rel = manifestRelativePath(
        p.manifest?.type ?? p.lattice);
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
      return null; // manifest 非法不影响「已安装」。
    }

    final ok = await pipInstallPackages(reqs);
    if (ok) return null;
    return '依赖安装失败：${reqs.join(', ')}（可稍后在「发现插件」页重装重试）';
  }

  /// 把 `docs/plugin-registry/<assetPath>` 下的本地静态资源复制到 [targetDir]。
  ///
  /// 用 [AssetManifest] 枚举该前缀下的所有 asset，逐个 [rootBundle.load] 后写入
  /// 磁盘（与 plugin_asset_releaser 的范式一致）。返回错误信息；成功返回 null。
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
  ///
  /// [srcRelPath] 为仓库内资源目录的相对路径（如 `plugins/zju_autosign`），
  /// 即 clone 后位于 `targetDir/<srcRelPath>`。复制时去掉该前缀，使
  /// `module/`、`data/`、`config/` 等子目录直接落在 `targetDir/` 根下
  /// （与 `local` 源落盘结果一致）。
  ///
  /// 用同步 I/O（对齐 widget 测试 fake 的 `createSync` 约定，避免 async 文件
  /// 操作被 pump 事件循环饿死）。返回错误信息；成功返回 null。
  String? _copyGithubAssets(String srcRelPath, String targetDir) {
    try {
      final norm = srcRelPath.replaceAll('\\', '/').replaceAll(RegExp(r'^/+'), '');
      final srcDir = Directory('$targetDir/$norm');
      if (!srcDir.existsSync()) {
        return '仓库内资源目录不存在: $norm';
      }

      // 递归枚举源目录下所有文件，复制到 targetDir 根（去掉前缀）。
      final files = <File>[];
      _collectFiles(srcDir, files);
      if (files.isEmpty) {
        return '仓库内资源目录为空: $norm';
      }
      for (final f in files) {
        // f.path = targetDir/norm/<rel> → 目标 = targetDir/<rel>
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

  /// 删除已安装插件（M6 · 补 5）：删除 `plugins/<id>` 目录并移除已安装标记。
  ///
  /// 删除前弹确认框（fail-closed）。成功后从 [_installedIds] 移除，卡片回到「安装」态。
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 把 registry 插件映射为 PluginDescriptor（含已安装标记 + 实时 star 覆盖）。
    final descriptors = (_plugins ?? const <RegistryPlugin>[])
        .map((p) => registryPluginToDescriptor(p,
            installed: _installedIds.contains(p.id),
            liveStars: _liveStars))
        .toList();


    return Scaffold(
      appBar: AppBar(
        title: const Text('发现插件'),
        elevation: 0,
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(
            height: 1,
            color: theme.colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _load,
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh, size: 20),
          ),
        ],
      ),
      body: _plugins == null && _loadError == null
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
                      const SizedBox(height: 12),
                      Text('发现源加载失败：$_loadError'),
                      const SizedBox(height: 8),
                      FilledButton(onPressed: _load, child: const Text('重试')),
                    ],
                  ),
                )
              : Stack(
                  children: [
                    MarketView(
                      plugins: descriptors,
                      installedIds: _installedIds,
                      installingIds: _installingIds,
                      onInstallTap: (desc) {
                        final p = _plugins
                            ?.firstWhere((e) => e.id == desc.id);
                        if (p != null) _install(p);
                      },
                      onUninstall: _uninstall,
                    ),
                    // 下载错误浮层（角标提示）。
                    if (_errors.isNotEmpty)
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 16,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.errorContainer
                                .withValues(alpha: 0.95),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.error_outline,
                                  size: 16,
                                  color: theme.colorScheme.onErrorContainer),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errors.entries
                                      .map((e) => '${e.key}: ${e.value}')
                                      .join('；'),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: theme.colorScheme.onErrorContainer,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: () => setState(() => _errors.clear()),
                                style: TextButton.styleFrom(
                                  foregroundColor:
                                      theme.colorScheme.onErrorContainer,
                                ),
                                child: const Text('知道了',
                                    style: TextStyle(fontSize: 12)),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }
}
