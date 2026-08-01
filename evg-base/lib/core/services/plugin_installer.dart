/// 插件生命周期管理器——安装、卸载、更新、签名校验、崩溃监控、沙箱隔离。
///
/// # 公开 API
///
/// | 方法 | 说明 |
/// |------|------|
/// | `install(packagePath)` | I17: 安装 .plugin 包（本地路径或 URL） |
/// | `uninstall(pluginId)` | I18: 卸载插件 |
/// | `checkUpdate(pluginId)` | I19: 检查插件更新 |
/// | `verifyAll()` | 启动时校验所有插件完整性，返回损坏列表 |
/// | `recordCrash(pluginId)` | 记录一次崩溃 |
/// | `isUnstable(pluginId)` | 是否已被标记为不稳定 |
/// | `listPlugins()` | 列出所有已安装插件状态 |
/// | `pluginStatus(pluginId)` | 单个插件状态 |
///
/// | 回调 | 说明 |
/// |------|------|
/// | `onInstall` | 安装后调用（全局工程师绑定到各 Loader 刷新） |
/// | `onUninstall` | 卸载后调用 |
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../log.dart';
import '../result.dart';
import '../errors.dart';

// ═══════ 类型定义 ═══════

/// 安装错误类型。
enum InstallErrorType {
  downloadFailed,
  signatureInvalid,
  extractFailed,
  diskFull,
  manifestInvalid,
  alreadyInstalled,
}

/// 安装操作结果。
class InstallResult {
  final bool success;
  final String pluginId;
  final String? error;
  final InstallErrorType? errorType;

  const InstallResult({
    required this.success,
    required this.pluginId,
    this.error,
    this.errorType,
  });

  /// 成功快捷构造。
  factory InstallResult.ok(String pluginId) =>
      InstallResult(success: true, pluginId: pluginId);

  /// 失败快捷构造。
  factory InstallResult.fail(String pluginId, String error, InstallErrorType type) =>
      InstallResult(success: false, pluginId: pluginId, error: error, errorType: type);

  Map<String, dynamic> toJson() => {
        'success': success,
        'pluginId': pluginId,
        if (error != null) 'error': error,
        if (errorType != null) 'errorType': errorType!.name,
      };
}

/// 更新检查结果。
class UpdateCheck {
  final bool hasUpdate;
  final String? currentVersion;
  final String? latestVersion;
  final String? downloadUrl;

  const UpdateCheck({
    required this.hasUpdate,
    this.currentVersion,
    this.latestVersion,
    this.downloadUrl,
  });

  Map<String, dynamic> toJson() => {
        'hasUpdate': hasUpdate,
        if (currentVersion != null) 'currentVersion': currentVersion,
        if (latestVersion != null) 'latestVersion': latestVersion,
        if (downloadUrl != null) 'downloadUrl': downloadUrl,
      };
}

/// 已安装插件状态。
class PluginStatus {
  final String id;
  final String name;
  final String version;
  final bool isUnstable;
  final int crashCount;
  final DateTime installedAt;
  final Map<String, bool> subComponents;

  const PluginStatus({
    required this.id,
    required this.name,
    required this.version,
    required this.isUnstable,
    required this.crashCount,
    required this.installedAt,
    required this.subComponents,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'version': version,
        'isUnstable': isUnstable,
        'crashCount': crashCount,
        'installedAt': installedAt.toIso8601String(),
        'subComponents': subComponents,
      };
}

// ═══════ PluginInstaller ═══════

/// 插件生命周期管理器。
///
/// 安装流程：下载（URL）或读取（本地）→ 签名校验 → 解压 → 写入元数据 → 通知。
/// 卸载流程：校验存在 → 删除目录 → 通知。
///
/// 崩溃监控：10 分钟窗口内 ≥ 3 次非零退出 → 标记为"不稳定"。
/// 沙箱隔离：校验插件路径不得逃逸到其他插件目录。
/// 配置回退：修改配置前备份，失败则恢复。
class PluginInstaller {
  final String _pluginsDir;
  final Dio _dio;

  /// 崩溃记录：pluginId → 崩溃时间戳列表。
  final Map<String, List<DateTime>> _crashLog = {};

  /// 不稳定阈值：10 分钟内 3 次崩溃。
  static const _crashWindowMinutes = 10;
  static const _crashThreshold = 3;

  /// 下载重试配置。
  static const _retryMaxAttempts = 3;
  static const _retryDelays = [Duration(seconds: 1), Duration(seconds: 3), Duration(seconds: 5)];

  /// 安装后回调（全局工程师在启动管线中绑定）。
  void Function(String pluginId)? onInstall;

  /// 卸载后回调。
  void Function(String pluginId)? onUninstall;

  PluginInstaller({required String pluginsDir, required Dio dio})
      : _pluginsDir = pluginsDir,
        _dio = dio;

  // ═══════ 公开 API ═══════

  /// I17: 安装 .plugin 包。
  ///
  /// [packagePath] 可以是本地文件路径或远程 URL。
  /// URL 时自动下载（3 次重试），本地路径时直接读取。
  Future<Result<InstallResult>> install(String packagePath) async {
    final isUrl = packagePath.startsWith('http://') || packagePath.startsWith('https://');

    try {
      // 1. 获取包文件
      List<int> bytes;
      if (isUrl) {
        final dlResult = await _downloadWithRetry(packagePath);
        if (dlResult == null) {
          return Err(NetworkError.unreachable(packagePath));
        }
        bytes = dlResult;
      } else {
        final file = File(packagePath);
        if (!file.existsSync()) {
          return Err(FileError.operationFailed(packagePath, 'read'));
        }
        bytes = await file.readAsBytes();
      }

      // 2. 解析 ZIP
      final archive = ZipDecoder().decodeBytes(bytes);
      final manifestFile = archive.files.firstWhere(
        (f) => f.name == 'manifest.json',
        orElse: () => ArchiveFile('', 0, <int>[]),
      );

      if (manifestFile.name.isEmpty) {
        return Err(DataIntegrityError.missingField('.plugin/manifest.json', 'file'));
      }

      final manifestJson = jsonDecode(utf8.decode(manifestFile.content)) as Map<String, dynamic>;

      // 3. 校验 manifest 必填字段
      final pluginId = manifestJson['id'] as String?;
      final pluginName = manifestJson['name'] as String?;
      final pluginVersion = manifestJson['version'] as String?;

      if (pluginId == null || pluginId.isEmpty) {
        return Err(ValidationError.required('manifest.id'));
      }
      if (pluginName == null || pluginName.isEmpty) {
        return Err(ValidationError.required('manifest.name'));
      }
      if (pluginVersion == null || pluginVersion.isEmpty) {
        return Err(ValidationError.required('manifest.version'));
      }

      // 4. 检查是否已安装
      final targetDir = _pluginDir(pluginId);
      if (Directory(targetDir).existsSync()) {
        return Err(ConfigError.invalid(
            'plugin.$pluginId', 'already_installed', 'not installed'));
      }

      // 5. 签名校验
      final sigFile = archive.files.firstWhere(
        (f) => f.name == '.signature',
        orElse: () => ArchiveFile('', 0, <int>[]),
      );

      if (sigFile.name.isEmpty) {
        return Err(DataIntegrityError.missingField('.plugin/.signature', 'file'));
      }

      final expectedSig = utf8.decode(sigFile.content).trim();
      final computedSig = _computeSignature(manifestFile.content);

      if (!_constantTimeEquals(expectedSig, computedSig)) {
        Log().warn('PluginInstaller: 签名校验失败 ($pluginId)');
        return Err(DataIntegrityError.logicalError(
          'signature',
          '签名不匹配：包可能已损坏或被篡改',
        ));
      }

      // 6. 解压到目标目录
      try {
        await _extractTo(archive, targetDir);
      } catch (e) {
        if (Directory(targetDir).existsSync()) {
          Directory(targetDir).deleteSync(recursive: true);
        }
        return Err(FileError.operationFailed(targetDir, 'extract'));
      }

      // 7. 写入元数据文件
      await File(p.join(targetDir, '.manifest')).writeAsString(
        jsonEncode(manifestJson),
      );
      await File(p.join(targetDir, '.signature')).writeAsString(computedSig);

      Log().info('PluginInstaller: 安装成功 ($pluginId v$pluginVersion)');

      // 8. 通知
      onInstall?.call(pluginId);

      return Ok(InstallResult.ok(pluginId));
    } catch (e, st) {
      Log().error('PluginInstaller: 安装失败', error: e, stack: st);
      return Err(UnknownError.from(e));
    }
  }

  /// I18: 卸载插件。
  Future<Result<void>> uninstall(String pluginId) async {
    final dir = Directory(_pluginDir(pluginId));
    if (!dir.existsSync()) {
      return Err(ConfigError.missing('plugin.$pluginId'));
    }

    try {
      await dir.delete(recursive: true);
      Log().info('PluginInstaller: 卸载成功 ($pluginId)');
      onUninstall?.call(pluginId);
      return const Ok(null);
    } catch (e) {
      Log().error('PluginInstaller: 卸载失败 ($pluginId)', error: e);
      return Err(FileError.operationFailed(dir.path, 'delete'));
    }
  }

  /// I19: 检查插件是否有更新。
  Future<UpdateCheck> checkUpdate(String pluginId) async {
    try {
      final manifestFile = File(p.join(_pluginDir(pluginId), '.manifest'));
      if (!manifestFile.existsSync()) {
        return const UpdateCheck(hasUpdate: false);
      }

      final manifest = jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
      final currentVersion = manifest['version'] as String? ?? '0.0.0';
      final updateUrl = manifest['updateUrl'] as String?;

      if (updateUrl == null) {
        return UpdateCheck(hasUpdate: false, currentVersion: currentVersion);
      }

      // 从更新源查询最新版本
      final response = await _dio.get(updateUrl);
      if (response.statusCode == 200 && response.data is Map) {
        final data = response.data as Map<String, dynamic>;
        final latestVersion = data['version'] as String?;
        final downloadUrl = data['downloadUrl'] as String?;

        if (latestVersion != null && _compareVersions(latestVersion, currentVersion) > 0) {
          return UpdateCheck(
            hasUpdate: true,
            currentVersion: currentVersion,
            latestVersion: latestVersion,
            downloadUrl: downloadUrl,
          );
        }
      }

      return UpdateCheck(hasUpdate: false, currentVersion: currentVersion);
    } catch (e) {
      Log().warn('PluginInstaller: 更新检查失败 ($pluginId): $e');
      return const UpdateCheck(hasUpdate: false);
    }
  }

  /// 启动时校验所有已安装插件完整性。
  ///
  /// 返回签名不匹配的插件 ID 列表。
  Future<List<String>> verifyAll() async {
    final corrupt = <String>[];
    final pluginsDir = Directory(_pluginsDir);

    if (!pluginsDir.existsSync()) return corrupt;

    for (final entity in pluginsDir.listSync()) {
      if (entity is! Directory) continue;

      final pluginId = p.basename(entity.path);
      final manifestFile = File(p.join(entity.path, '.manifest'));
      final sigFile = File(p.join(entity.path, '.signature'));

      if (!manifestFile.existsSync()) {
        corrupt.add(pluginId);
        Log().warn('PluginInstaller: $pluginId 缺少 .manifest');
        continue;
      }
      if (!sigFile.existsSync()) {
        corrupt.add(pluginId);
        Log().warn('PluginInstaller: $pluginId 缺少 .signature');
        continue;
      }

      try {
        final manifestBytes = await manifestFile.readAsBytes();
        final expectedSig = await sigFile.readAsString();
        final computedSig = _computeSignature(manifestBytes);

        if (!_constantTimeEquals(expectedSig.trim(), computedSig)) {
          corrupt.add(pluginId);
          Log().warn('PluginInstaller: $pluginId 签名不匹配');
        }
      } catch (e) {
        corrupt.add(pluginId);
        Log().warn('PluginInstaller: $pluginId 校验异常: $e');
      }
    }

    if (corrupt.isNotEmpty) {
      Log().error('PluginInstaller: verifyAll 发现 ${corrupt.length} 个损坏插件: $corrupt');
    }
    return corrupt;
  }

  /// 列出所有已安装插件。
  List<PluginStatus> listPlugins() {
    final result = <PluginStatus>[];
    final pluginsDir = Directory(_pluginsDir);

    if (!pluginsDir.existsSync()) return result;

    for (final entity in pluginsDir.listSync()) {
      if (entity is! Directory) continue;

      final status = pluginStatus(p.basename(entity.path));
      if (status != null) {
        result.add(status);
      }
    }

    return result;
  }

  /// 单个插件状态。
  PluginStatus? pluginStatus(String pluginId) {
    final dir = Directory(_pluginDir(pluginId));
    if (!dir.existsSync()) return null;

    final manifestFile = File(p.join(dir.path, '.manifest'));
    if (!manifestFile.existsSync()) return null;

    try {
      final manifest = jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
      final subComponents = <String, bool>{
        'agent': Directory(p.join(dir.path, 'agent')).existsSync(),
        'module': Directory(p.join(dir.path, 'module')).existsSync(),
        'data': Directory(p.join(dir.path, 'data')).existsSync(),
        'theme': Directory(p.join(dir.path, 'theme')).existsSync(),
        'config': Directory(p.join(dir.path, 'config')).existsSync(),
        'skill': Directory(p.join(dir.path, 'skill')).existsSync(),
      };

      final stat = manifestFile.statSync();
      return PluginStatus(
        id: pluginId,
        name: manifest['name'] as String? ?? pluginId,
        version: manifest['version'] as String? ?? '0.0.0',
        isUnstable: isUnstable(pluginId),
        crashCount: _crashLog[pluginId]?.length ?? 0,
        installedAt: stat.modified,
        subComponents: subComponents,
      );
    } catch (e) {
      Log().warn('PluginInstaller: 读取插件状态失败 ($pluginId): $e', error: e);
      return null;
    }
  }

  // ═══════ 崩溃监控 ═══════

  /// 记录一次崩溃。
  void recordCrash(String pluginId) {
    _crashLog.putIfAbsent(pluginId, () => <DateTime>[]).add(DateTime.now());
    // 清理过期记录
    _crashLog[pluginId]?.removeWhere(
      (t) => DateTime.now().difference(t).inMinutes > _crashWindowMinutes,
    );

    if (isUnstable(pluginId)) {
      Log().warn('PluginInstaller: $pluginId 已被标记为不稳定'
          '（${_crashLog[pluginId]!.length} 次崩溃）');
    }
  }

  /// 是否已被标记为不稳定（10 分钟内 ≥ 3 次崩溃）。
  bool isUnstable(String pluginId) {
    final crashes = _crashLog[pluginId];
    if (crashes == null || crashes.isEmpty) return false;

    final cutoff = DateTime.now().subtract(const Duration(minutes: _crashWindowMinutes));
    final recent = crashes.where((t) => t.isAfter(cutoff)).toList();
    return recent.length >= _crashThreshold;
  }

  // ═══════ 沙箱隔离 ═══════

  /// 校验给定路径在指定插件目录内。
  ///
  /// 防止插件 A 读取插件 B 的目录。
  bool isWithinPluginDir(String pluginId, String path) {
    try {
      final pluginDir = p.canonicalize(_pluginDir(pluginId));
      final target = p.canonicalize(path);
      return target == pluginDir || target.startsWith('$pluginDir${p.separator}');
    } catch (e) {
      Log().warn('PluginInstaller: 路径校验异常 ($pluginId, $path): $e', error: e);
      return false;
    }
  }

  // ═══════ 内部方法 ═══════

  /// 带重试的 HTTP 下载。
  ///
  /// 最多 3 次尝试，间隔 1s / 3s / 5s。返回文件字节或 null。
  Future<List<int>?> _downloadWithRetry(String url) async {
    for (var i = 0; i < _retryMaxAttempts; i++) {
      try {
        final response = await _dio.get<List<int>>(
          url,
          options: Options(responseType: ResponseType.bytes),
        );
        if (response.statusCode == 200 && response.data != null) {
          return response.data;
        }
      } catch (e) {
        Log().warn('PluginInstaller: 下载尝试 ${i + 1}/$_retryMaxAttempts 失败: $e');
      }

      if (i < _retryMaxAttempts - 1) {
        await Future.delayed(_retryDelays[i]);
      }
    }
    return null;
  }

  /// 计算 manifest.json 的 SHA-256 签名（hex 字符串）。
  String _computeSignature(List<int> manifestBytes) {
    return sha256.convert(manifestBytes).toString();
  }

  /// 常数时间字符串比较（防止时序攻击）。
  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }

  /// 解压 ZIP 到目标目录。
  Future<void> _extractTo(Archive archive, String targetDir) async {
    final dir = Directory(targetDir);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    for (final file in archive.files) {
      if (!file.isFile) continue;

      final destPath = p.join(targetDir, file.name);
      // 防止 zip slip 攻击：规范化后校验在目标目录内
      // 使用 canonicalize + startsWith 替代 p.isWithin（兼容旧版 path stub）
      final canonicalTarget = p.canonicalize(targetDir);
      final canonicalDest = p.canonicalize(destPath);
      if (canonicalDest != canonicalTarget &&
          !canonicalDest.startsWith('$canonicalTarget${p.separator}')) {
        Log().warn('PluginInstaller: 拒绝越界路径 ${file.name}');
        continue;
      }

      final destFile = File(destPath);
      // 确保父目录存在
      final parentDir = Directory(p.dirname(destPath));
      if (!parentDir.existsSync()) {
        parentDir.createSync(recursive: true);
      }

      await destFile.writeAsBytes(file.content);
    }
  }

  /// 配置修改保护——操作前备份，失败自动回退。
  ///
  /// 适用场景：插件更新时保留/修改 config/ 目录、运行时设置变更。
  /// 备份范围：`plugins/<id>/config/` → `.config_backup/`。
  /// 操作成功则删除备份，失败则恢复原 config/。
  ///
  /// **S3 联调时接入**：在 update 流程的配置迁移步骤中调用此方法。
  /// 当前已实现但暂未接入业务——待 update 流程添加配置保留逻辑后使用。
  Future<void> _withRollback(String pluginId, Future<void> Function() operation) async {
    final configDir = Directory(p.join(_pluginDir(pluginId), 'config'));
    final backupDir = Directory(p.join(_pluginDir(pluginId), '.config_backup'));

    // 1. 备份
    if (await configDir.exists()) {
      await _copyDir(configDir, backupDir);
    }

    try {
      // 2. 执行操作
      await operation();

      // 3. 成功 → 清理备份
      if (await backupDir.exists()) {
        await backupDir.delete(recursive: true);
      }
    } catch (e) {
      // 4. 失败 → 回退
      Log().warn('PluginInstaller: 配置修改失败，正在回退 ($pluginId): $e');
      if (await backupDir.exists()) {
        if (await configDir.exists()) {
          await configDir.delete(recursive: true);
        }
        await backupDir.rename(configDir.path);
      }
      rethrow;
    }
  }

  /// 递归复制目录。
  Future<void> _copyDir(Directory source, Directory target) async {
    if (await target.exists()) {
      await target.delete(recursive: true);
    }
    await target.create(recursive: true);

    await for (final entity in source.list()) {
      final targetPath = p.join(target.path, p.basename(entity.path));
      if (entity is Directory) {
        await _copyDir(entity, Directory(targetPath));
      } else if (entity is File) {
        await entity.copy(targetPath);
      }
    }
  }

  /// 版本比较：返回 -1 (a<b), 0 (a==b), 1 (a>b)。
  int _compareVersions(String a, String b) => compareVersions(a, b);

  /// 获取插件目录路径。
  String _pluginDir(String pluginId) => p.join(_pluginsDir, pluginId);
}

// ═══════ 公开工具函数 ═══════

/// 比较两个语义化版本号。
///
/// 忽略 pre-release 后缀（如 `-beta`），缺失段视为 0。
/// 返回 -1 (a<b), 0 (a==b), 1 (a>b)。
int compareVersions(String a, String b) {
  int parse(String v, int index) {
    final parts = v
        .split('-')
        .first
        .split('.')
        .map((s) => int.tryParse(s) ?? 0)
        .toList();
    return index < parts.length ? parts[index] : 0;
  }

  for (var i = 0; i < 3; i++) {
    final av = parse(a, i);
    final bv = parse(b, i);
    if (av > bv) return 1;
    if (av < bv) return -1;
  }
  return 0;
}
