/// Greenix 运行时路径——数据目录 + 插件目录管理。
///
/// 所有持久化数据统一放在 `.greenix/` 下，与 module/ 的 [WorkspaceDescriptor] 对应。
/// [resolvePluginsRoot] 提供跨所有模块的插件目录单一点位解析。
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Greenix 可写基础目录，默认为当前工作目录下的 `.greenix`。
String _greenixBaseDir = '.greenix';

/// 初始化 Greenix 路径——main() 启动时调用一次（须 await）。
///
/// - 桌面端：基于当前工作目录（通常为项目根）下的 `.greenix`，保持历史行为。
/// - 移动端（Android/iOS）：进程工作目录是只读的 `/`，直接拼 `.greenix` 会得到
///   `/.greenix` 并抛 `FileSystemException: Read-only file system (errno=30)`。
///   故改用 app 私有可写目录 [getApplicationSupportDirectory] 下的 `.greenix`。
Future<void> initGreenixPaths() async {
  if (Platform.isAndroid || Platform.isIOS) {
    final support = await getApplicationSupportDirectory();
    _greenixBaseDir = p.join(support.path, '.greenix');
  } else {
    // 桌面：优先可执行文件目录下的 .greenix（已安装 App，cwd 可能非安装目录）；
    // 否则退回当前工作目录（开发模式，cwd = 项目根）。
    final exeBase = p.join(p.dirname(Platform.resolvedExecutable), '.greenix');
    _greenixBaseDir =
        Directory(exeBase).existsSync() ? exeBase : p.join(Directory.current.path, '.greenix');
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 插件目录单一点位解析（节点 2 路径统一）
// ═══════════════════════════════════════════════════════════════════════════

/// 插件目录缓存——首次解析后复用，避免重复文件 I/O。
String? _cachedPluginsRoot;

/// 安卓端插件释放目录：应用可写目录下的 `.greenix/plugins`。
///
/// 与 [releasePluginsAssetsIfNeeded] 的释放目标一致（见
/// plugin_asset_releaser.dart），是安卓侧所有插件消费者的统一入口。
String get androidPluginsDir => greenixPluginsDir;

/// 解析插件根目录（plugins/）的绝对路径。
///
/// **解析优先级**：
/// 1. 安卓：插件资产已释放到应用可写目录（见 [androidPluginsDir]）
/// 2. 环境变量 `EVERGREEN_PLUGINS_DIR`（最高优先级）
/// 3. 从 [Platform.resolvedExecutable] 向上查找 `pubspec.yaml` → `$projectRoot/plugins`
/// 4. 从 [Directory.current] 向上查找 `pubspec.yaml` → `$projectRoot/plugins`
/// 5. 回退：`Directory.current/plugins`
///
/// 设计原因：节点 2（一次性产出三件套）及其他插件路径消费者需要绝对路径，
/// 避免硬编码 `'plugins/'` 相对路径在 CWD 变动时错落。
///
/// 结果已规范化（`p.normalize`），并确保目录存在。
String resolvePluginsRoot() {
  if (_cachedPluginsRoot != null) return _cachedPluginsRoot!;

  // 安卓：直接返回已释放的插件目录（避免回退到只读的 `/`）
  if (Platform.isAndroid) {
    final d = androidPluginsDir;
    _ensureDir(d);
    debugPrint('[GreenixPath] 🔌 pluginsRoot (android) ← $d');
    _cachedPluginsRoot = d;
    return d;
  }

  // 策略1：环境变量
  final envDir = Platform.environment['EVERGREEN_PLUGINS_DIR'];
  if (envDir != null && envDir.isNotEmpty) {
    final normalized = p.normalize(p.absolute(envDir));
    _ensureDir(normalized);
    debugPrint('[GreenixPath] 🔌 pluginsRoot ← EVERGREEN_PLUGINS_DIR: $normalized');
    _cachedPluginsRoot = normalized;
    return normalized;
  }

  // 策略2：从可执行文件目录 / 当前工作目录向上找项目根
  final root = resolveProjectRoot();
  if (root != null) {
    final plugins = p.normalize(p.absolute(root, 'plugins'));
    _ensureDir(plugins);
    debugPrint('[GreenixPath] 🔌 pluginsRoot ← projectRoot: $plugins');
    _cachedPluginsRoot = plugins;
    return plugins;
  }

  // 策略3：应用数据目录下的 .greenix/plugins
  // （分布式桌面：由资产释放或安装包预置到这里，无项目根时优先可用）
  final greenixPlugins = greenixPluginsDir;
  if (Directory(greenixPlugins).existsSync()) {
    _ensureDir(greenixPlugins);
    debugPrint('[GreenixPath] 🔌 pluginsRoot ← .greenix/plugins: $greenixPlugins');
    _cachedPluginsRoot = greenixPlugins;
    return greenixPlugins;
  }

  // 策略4：回退——当前工作目录下的 plugins
  final fallback = p.normalize(p.absolute(Directory.current.path, 'plugins'));
  _ensureDir(fallback);
  debugPrint('[GreenixPath] ⚠ pluginsRoot fallback: $fallback');
  _cachedPluginsRoot = fallback;
  return fallback;
}

/// 重置缓存（测试用）。
@visibleForTesting
void resetPluginsRootCache() {
  _cachedPluginsRoot = null;
}

/// 向上查找包含 pubspec.yaml 的目录作为项目根（公开 API，带缓存）。
///
/// 从 [Platform.resolvedExecutable] 所在目录向上查找；找不到时从
/// [Directory.current] 向上查找；均失败返回 null。
String? resolveProjectRoot() {
  if (_cachedProjectRoot != null) return _cachedProjectRoot!;
  final fromExe = _findProjectRoot(Directory(p.dirname(Platform.resolvedExecutable)));
  if (fromExe != null) {
    _cachedProjectRoot = fromExe;
    return fromExe;
  }
  final fromCwd = _findProjectRoot(Directory.current);
  if (fromCwd != null) {
    _cachedProjectRoot = fromCwd;
    return fromCwd;
  }
  return null;
}

String? _cachedProjectRoot;

/// 重置项目根缓存（测试用）。
@visibleForTesting
void resetProjectRootCache() {
  _cachedProjectRoot = null;
}

/// 向上查找包含 [markerFile] 的目录作为项目根。
String? _findProjectRoot(Directory start) {
  var dir = start;
  while (true) {
    if (File(p.join(dir.path, 'pubspec.yaml')).existsSync()) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break; // 到达文件系统根
    dir = parent;
  }
  return null;
}

/// 确保目录存在。
void _ensureDir(String path) {
  final dir = Directory(path);
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
    debugPrint('[GreenixPath] 📁 创建目录: $path');
  }
}

/// 探索授权范围（Scope Contract）JSON 文件路径（`ExploreScope` 持久化）。
String get greenixScopePath => p.join(_greenixBaseDir, 'scope.json');

/// 探索经验 Journal 目录（P1-2 field-journal：按域名一个 JSON 文件）。
String get greenixJournalDir => p.join(_greenixBaseDir, 'scraper_journal');

/// 配置凭证 JSON 文件路径（供 scraper 脚本直接读取，跳过 HTTP ConfigHttpServer）。
///
/// 启动时 ConfigHttpServer 将全部 SharedPreferences 设置覆写到该文件。
/// Python scraper 的 `_get_config()` 将此作为 Tier 2 降级路径。
String get greenixConfigPath => p.join(_greenixBaseDir, 'config.json');

/// AI 写入的爬虫环境变量 JSON 文件路径（`ScraperEnvStore` 持久化）。
///
/// 扁平字典 `{"KEY": "value", ...}`；运行 Python 子进程时合并进环境变量，
/// 使 scraper.py 的 `_get_config()` Tier 3（`os.environ`）与直接 `os.environ`
/// 都能读到 AI/用户写入的账号密码等凭据。
String get greenixEnvPath => p.join(_greenixBaseDir, 'env.json');

/// SSO cookie jar（PersistCookieJar FileStorage）路径——zju_modle 会话持久化。
///
/// PersistCookieJar 会在此目录下按域名分文件存储 cookie，跨重启保持登录态。
/// 与 CookieStore（[zjuCookiesPath]）各司其职：本路径服务 Dio 的 CookieManager。
String get cookieJarPath => p.join(_greenixBaseDir, '.cookies');

/// ZJU SSO cookie JSON 存储路径（CookieStore：iPlanetDirectoryPro / synjones-auth）。
///
/// 独立于 PersistCookieJar，供 SSO 会话恢复（[CookieStore.ssoCookie]）与
/// 一卡通 synjones-auth token 存取。
String get zjuCookiesPath => p.join(_greenixBaseDir, 'zju_cookies.json');

/// 记忆存储目录。
String get greenixMemoriesDir => p.join(_greenixBaseDir, 'memories');

/// Skill 文件目录。
String get greenixSkillsDir => p.join(_greenixBaseDir, 'skills');

/// 构造 Skill 文件落盘路径，统一 AI 助手/技能管理与 Skill 创作中心的导出规则。
///
/// 与旧实现保持一致：`Directory(greenixSkillsDir)` + 平台分隔符，
/// 文件名规则为“空白转 `-` + 小写”。
String greenixSkillPath(String name) {
  final skillsDir = Directory(greenixSkillsDir);
  if (!skillsDir.existsSync()) {
    skillsDir.createSync(recursive: true);
  }
  final filename = '${name.replaceAll(RegExp(r'\s+'), '-').toLowerCase()}.md';
  return '${skillsDir.path}${Platform.pathSeparator}$filename';
}

/// 会话持久化目录。
String get greenixSessionsDir => p.join(_greenixBaseDir, 'sessions');

/// 嵌入式 Python 运行时目录（python.exe + site-packages）。
String get greenixPythonDir => p.join(_greenixBaseDir, 'python');

/// 管线脚本目录（OCR/论文/翻译等 *.py + requirements.txt）。
/// 由资产释放（Android）或安装包预置（Windows）填充到 `.greenix/scripts`。
String get greenixScriptsDir => p.join(_greenixBaseDir, 'scripts');

/// 插件目录（应用数据目录下）。与 [androidPluginsDir] 同路径，桌面分布式的
/// `.greenix/plugins` 也走这里。
String get greenixPluginsDir => p.join(_greenixBaseDir, 'plugins');

// ═══════ 文件工作区 ═══════

/// 工作区根目录——每个模块的文件工作区数据存于此。
String get greenixWorkspacesDir => p.join(_greenixBaseDir, 'workspaces');

/// 指定模块的工作区目录。id 为 [ModuleDescriptor.id]。
String greenixWorkspaceDir(String moduleId) =>
    p.join(greenixWorkspacesDir, moduleId);

/// 确保工作区目录存在。模块注册时调用一次。
void ensureWorkspaceDir(String moduleId) {
  final dir = Directory(greenixWorkspaceDir(moduleId));
  if (!dir.existsSync()) dir.createSync(recursive: true);
}

/// 列出工作区目录下的所有文件。
List<FileSystemEntity> listWorkspaceFiles(String moduleId) {
  final dir = Directory(greenixWorkspaceDir(moduleId));
  if (!dir.existsSync()) return [];
  return dir.listSync();
}

// ═══════════════════════════════════════════════════════════════════════════
// 插件资源路径解析（slot 中 manifest 相对路径 → 绝对文件系统路径）
// ═══════════════════════════════════════════════════════════════════════════

/// 将 manifest 中的相对资源路径解析为插件目录下的绝对文件系统路径。
///
/// 用于 pdf-viewer / video-player / audio-player / image-gallery 等需要
/// 直接读取插件文件的 slot：
/// - 绝对路径（/ 或盘符开头）→ 原样返回
/// - 相对路径 `assets/...` → `$pluginsDir/$moduleId/$relativePath`
/// - null / 空 → 返回 null
///
/// 结果已规范化（[p.normalize]）。
String? resolvePluginAssetPath(
  String? raw,
  String moduleId,
  String pluginsDir,
) {
  if (raw == null || raw.isEmpty) return null;
  if (p.isAbsolute(raw)) return raw;
  return p.normalize(p.absolute(p.join(pluginsDir, moduleId, raw)));
}
