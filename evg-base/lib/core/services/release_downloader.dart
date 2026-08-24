/// GitHub release 二进制下载器（M6 · 补 5）。
///
/// 针对 `install.strategy = "release"` 的插件：查 GitHub latest release，
/// 找匹配平台/模式的 asset，下载并解压（zip）或直接落盘（单文件）到
/// `plugins/<id>/` 目录，供插件中心统一管理。
///
/// 设计原则（与 github_issue_publisher / update_service 一致）：
/// - 永不抛异常到调用方：任何网络/解析错误都收敛为 [ReleaseResult.failure]。
/// - 默认 30s 超时。
library;

import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:evergreen_base/core/log.dart';
import 'package:evergreen_base/core/module/github_source.dart';

/// release 下载结果。
class ReleaseResult {
  final bool success;
  final String? error;
  final String? version; // 下载的 release tag
  final String? assetName; // 命中的 asset 名

  const ReleaseResult({
    required this.success,
    this.error,
    this.version,
    this.assetName,
  });

  factory ReleaseResult.ok(String version, String assetName) =>
      ReleaseResult(success: true, version: version, assetName: assetName);

  factory ReleaseResult.fail(String error) =>
      ReleaseResult(success: false, error: error);
}

/// 下载 GitHub 仓库的 latest release asset 到 [targetDir]。
///
/// [assetPattern] 用于筛选 asset；为空时按当前平台推断常见后缀
/// （windows→`windows`，macos→`darwin`，其他→`linux`）。
///
/// [assetPattern] 语法：`包含词!排除词`（`!` 可选，排除词多个用 `,` 分隔），
/// 匹配时归一化 `-`/`_`/`.`。支持平台占位符 `{platform}`（→windows/darwin/linux）
/// 与 `{arch}`（→amd64/arm64/386），运行时按当前平台替换。
/// 例：`zjuical_{platform}_{arch}!srv` 在 Windows 上展开为
/// `zjuical_windows_amd64!srv`，Mac 上为 `zjuical_darwin_amd64!srv`。
///
/// [platforms] 声明该 release 支持哪些平台（`windows`/`macos`/`linux`，不含
/// `android`）。当前平台不在白名单内时**直接返回明确错误**，不发起下载——
/// 安卓遇桌面专用 CLI 插件时立刻报「该插件不支持当前平台」，而非下载失败。
///
/// 命中 zip / tar.gz → 解压到 [targetDir]；命中单文件 → 直接放入 [targetDir]。
Future<ReleaseResult> downloadRelease(
  GithubSource src,
  String targetDir, {
  String? assetPattern,
  List<String>? platforms,
  Dio? dio,
  Duration timeout = const Duration(seconds: 30),
}) async {
  final client = dio ?? Dio();

  // 0. 平台支持检查：当前平台不在白名单 → 直接报错（不下载）。
  if (platforms != null && platforms.isNotEmpty) {
    final current = _currentPlatform();
    final supported = platforms.map((p) => p.toLowerCase()).toSet();
    if (current != null && !supported.contains(current)) {
      return ReleaseResult.fail(
          '该插件不支持当前平台（${_platformLabel()}），'
          '仅支持 ${platforms.join(' / ')}');
    }
  }

  try {
    // 1. 查 latest release
    final resp = await client.get(
      'https://api.github.com/repos/${src.owner}/${src.repo}/releases/latest',
      options: Options(
        headers: {'Accept': 'application/vnd.github+json'},
        receiveTimeout: timeout,
        sendTimeout: timeout,
      ),
    );
    if (resp.statusCode != 200 || resp.data is! Map) {
      return ReleaseResult.fail('查询 release 失败（HTTP ${resp.statusCode}）');
    }

    final tag = (resp.data['tag_name'] as String?) ?? '';
    final assets = (resp.data['assets'] as List?) ?? [];
    if (assets.isEmpty) {
      return ReleaseResult.fail('该 release 没有可下载的 asset');
    }

    // 2. 选 asset：优先 assetPattern（替换平台占位符），其次平台推断
    var pattern = (assetPattern != null && assetPattern.isNotEmpty)
        ? assetPattern
        : _platformPattern();
    pattern = _resolvePlatformPlaceholders(pattern);
    final chosen = _selectAsset(assets, pattern);
    if (chosen == null) {
      return ReleaseResult.fail('未找到匹配 "$pattern" 的 release asset');
    }
    final downloadUrl = chosen['browser_download_url'] as String?;
    final assetName = chosen['name'] as String? ?? '';
    if (downloadUrl == null || downloadUrl.isEmpty) {
      return ReleaseResult.fail('asset 缺少下载地址');
    }

    // 3. 下载
    final bytes = await _download(client, downloadUrl, timeout);
    if (bytes == null) {
      return ReleaseResult.fail('下载 asset 失败: $downloadUrl');
    }

    // 4. 落盘（zip / tar.gz 解压 / 单文件直放）
    final dir = Directory(targetDir);
    dir.createSync(recursive: true);
    final ok = _extractArchive(bytes, targetDir, assetName);
    if (!ok) return ReleaseResult.fail('解压 asset 失败: $assetName');

    Log().info('ReleaseDownloader: 下载成功 ($tag / $assetName)');
    return ReleaseResult.ok(tag, assetName);
  } on DioException catch (e) {
    return ReleaseResult.fail('下载 release 网络错误: ${e.message}');
  } catch (e) {
    return ReleaseResult.fail('下载 release 失败: $e');
  }
}

/// 按平台推断 asset 匹配片段。
String _platformPattern() {
  if (Platform.isWindows) return 'windows';
  if (Platform.isMacOS) return 'darwin';
  return 'linux';
}

/// 当前平台的标准标识（`windows`/`macos`/`linux`/`android`），用于 `platforms`
/// 白名单比对。非桌面/非安卓（如 Fuchsia/web）返回 null（不参与比对）。
String? _currentPlatform() {
  if (Platform.isAndroid) return 'android';
  if (Platform.isWindows) return 'windows';
  if (Platform.isMacOS) return 'macos';
  if (Platform.isLinux) return 'linux';
  return null;
}

/// 当前平台的人类可读名（用于错误提示）。
String _platformLabel() {
  if (Platform.isAndroid) return '安卓';
  if (Platform.isWindows) return 'Windows';
  if (Platform.isMacOS) return 'macOS';
  if (Platform.isLinux) return 'Linux';
  return '当前平台';
}

/// 替换 [pattern] 中的平台占位符：
/// - `{platform}` → `windows` / `darwin` / `linux`（安卓回退 `linux`）
/// - `{arch}` → `amd64` / `arm64` / `386`（按可执行架构推断）
String _resolvePlatformPlaceholders(String pattern) {
  var out = pattern;
  if (out.contains('{platform}')) {
    out = out.replaceAll('{platform}', _platformPattern());
  }
  if (out.contains('{arch}')) {
    out = out.replaceAll('{arch}', _archPattern());
  }
  return out;
}

/// 按当前平台/架构推断 arch 片段（amd64/arm64/386）。
///
/// 用 [Platform.operatingSystem] 无法直接拿 arch，这里用
/// [Platform.version] 里含 `arm`/`aarch` 判断 arm64，否则默认 amd64。
String _archPattern() {
  if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
    // 移动端 + Apple Silicon 常见 arm64
    final v = Platform.version.toLowerCase();
    if (v.contains('arm') || v.contains('aarch')) return 'arm64';
  }
  // 桌面默认 amd64（zju-ical 等桌面 CLI 的主流产物）
  return 'amd64';
}

/// 从 asset 列表里选第一个名字匹配 [pattern] 的。
///
/// [pattern] 语法（`!` 分隔）：`包含词!排除词`。
/// - 包含词：可多个，用**空格**分隔，asset 名（归一化后）必须**同时**包含每一个。
///   （空格分隔是为了让 `zjuical windows_amd64` 这类「品牌 + 平台」分开独立
///   匹配，避免品牌词与平台词被版本号隔开时连续子串匹配失败。）
/// - 排除词（可多个，`,` 分隔）：命中任一即剔除（用于区分 `zjuical` 客户端 vs
///   `zjuicalsrv` 服务端等同平台多产物）。
/// - 归一化：转小写并把 `-`/`_`/`.` 折叠成 `_`，使 `windows-amd64` 也能匹配
///   `windows_amd64` 这类命名。
///
/// 例：`zjuical windows_amd64!srv` → 选含 zjuical 且含 windows_amd64、且非
/// 服务端的 asset（中间隔着版本号也能命中）。
Map<String, dynamic>? _selectAsset(List assets, String pattern) {
  final parts = pattern.split('!');
  final includes = parts.first
      .split(RegExp(r'\s+'))
      .map(_normalize)
      .where((s) => s.isNotEmpty)
      .toList();
  final excludes =
      parts.length > 1 ? parts[1].split(',').map(_normalize).toList() : <String>[];

  for (final a in assets) {
    if (a is! Map) continue;
    final name = (a['name'] as String? ?? '');
    final normalized = _normalize(name);
    // 每个包含词都必须命中（AND）
    if (includes.any((inc) => !normalized.contains(inc))) continue;
    // 命中任一排除词即剔除
    if (excludes.any((e) => e.isNotEmpty && normalized.contains(e))) continue;
    return Map<String, dynamic>.from(a);
  }
  return null;
}

/// 归一化 asset 名用于匹配：转小写并把 `-`/`_`/`.` 统一折叠成同一分隔符。
String _normalize(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[-_.]'), '_');

bool _isZip(String name) => name.toLowerCase().endsWith('.zip');

bool _isTarGz(String name) =>
    name.toLowerCase().endsWith('.tar.gz') || name.toLowerCase().endsWith('.tgz');

Future<List<int>?> _download(
    Dio client, String url, Duration timeout) async {
  try {
    final resp = await client.get<List<int>>(
      url,
      options: Options(
        responseType: ResponseType.bytes,
        receiveTimeout: timeout,
        sendTimeout: timeout,
      ),
    );
    if (resp.statusCode == 200 && resp.data != null) {
      return resp.data;
    }
    return null;
  } catch (_) {
    return null;
  }
}

/// 解压 asset 到 [targetDir]（复用 archive 包，与 plugin_installer 一致）。
///
/// 支持 `.zip`、`.tar.gz`/`.tgz`；其它扩展名视为单文件，直接落盘到 [targetDir]。
bool _extractArchive(List<int> bytes, String targetDir, String assetName) {
  try {
    final Archive archive;
    if (_isZip(assetName)) {
      archive = ZipDecoder().decodeBytes(bytes);
    } else if (_isTarGz(assetName)) {
      // .tar.gz = gzip 解压 → tar 解包
      final gunzipped = GZipDecoder().decodeBytes(bytes);
      archive = TarDecoder().decodeBytes(gunzipped);
    } else {
      // 单文件：直接落盘
      File('$targetDir/$assetName').writeAsBytesSync(bytes);
      return true;
    }
    for (final f in archive.files) {
      if (!f.isFile) continue;
      final dest = File('$targetDir/${f.name}');
      dest.parent.createSync(recursive: true);
      dest.writeAsBytesSync(f.content);
    }
    return true;
  } catch (_) {
    return false;
  }
}
