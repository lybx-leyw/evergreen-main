/// 仓库路径配置服务。
///
/// 允许用户自定义技术规划的目标代码仓库路径（本地/远程），
/// 在 AI 调研前做路径合法性校验，结果持久化保存。
///
/// 存储路径：`.greenix/workspaces/<moduleId>/repo-config.json`
library;

import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:evergreen_base/core/utils/greenix_path.dart';

/// 仓库路径校验状态。
enum RepoValidationStatus {
  /// 尚未校验。
  unknown,

  /// 校验通过——路径可达，包含可识别项目文件。
  valid,

  /// 路径无效——目录不存在或权限不足。
  invalid,

  /// 权限被拒——目录存在但无法读取。
  permissionDenied,

  /// 路径不存在。
  notFound,
}

/// 仓库配置模型。
///
/// 支持本地路径和远程 URL 两种模式，可独立或同时配置。
class RepoConfig {
  /// 本地仓库路径（绝对路径）。
  final String? localPath;

  /// 远程仓库 URL（可选，用于参考）。
  final String? remoteUrl;

  /// 校验状态。
  final RepoValidationStatus validationStatus;

  /// 上次校验时间。
  final DateTime? lastValidated;

  /// 校验时的错误/提示信息。
  final String? validationMessage;

  const RepoConfig({
    this.localPath,
    this.remoteUrl,
    this.validationStatus = RepoValidationStatus.unknown,
    this.lastValidated,
    this.validationMessage,
  });

  /// 是否有有效配置。
  bool get hasValidConfig =>
      validationStatus == RepoValidationStatus.valid && localPath != null;

  /// 从 JSON 反序列化。
  factory RepoConfig.fromJson(Map<String, dynamic> json) => RepoConfig(
        localPath: json['localPath'] as String?,
        remoteUrl: json['remoteUrl'] as String?,
        validationStatus: _parseStatus(json['validationStatus'] as String?),
        lastValidated: json['lastValidated'] != null
            ? DateTime.parse(json['lastValidated'] as String)
            : null,
        validationMessage: json['validationMessage'] as String?,
      );

  /// 序列化为 JSON。
  Map<String, dynamic> toJson() => {
        if (localPath != null) 'localPath': localPath,
        if (remoteUrl != null) 'remoteUrl': remoteUrl,
        'validationStatus': validationStatus.name,
        if (lastValidated != null)
          'lastValidated': lastValidated!.toIso8601String(),
        if (validationMessage != null) 'validationMessage': validationMessage,
      };

  /// 创建表示"尚未配置"的实例。
  factory RepoConfig.empty() => const RepoConfig();

  /// 拷贝并更新字段。
  RepoConfig copyWith({
    String? localPath,
    String? remoteUrl,
    RepoValidationStatus? validationStatus,
    DateTime? lastValidated,
    String? validationMessage,
    bool clearLocalPath = false,
    bool clearRemoteUrl = false,
    bool clearValidationMessage = false,
  }) {
    return RepoConfig(
      localPath: clearLocalPath ? null : (localPath ?? this.localPath),
      remoteUrl: clearRemoteUrl ? null : (remoteUrl ?? this.remoteUrl),
      validationStatus: validationStatus ?? this.validationStatus,
      lastValidated: lastValidated ?? this.lastValidated,
      validationMessage: clearValidationMessage
          ? null
          : (validationMessage ?? this.validationMessage),
    );
  }

  static RepoValidationStatus _parseStatus(String? s) {
    if (s == null) return RepoValidationStatus.unknown;
    return RepoValidationStatus.values.firstWhere(
      (e) => e.name == s,
      orElse: () => RepoValidationStatus.unknown,
    );
  }
}

/// 仓库配置服务。
///
/// 负责配置的校验、持久化和加载。
class RepoConfigService {
  final String moduleId;

  RepoConfigService({required this.moduleId});

  // ═══════ 校验 ═══════

  /// 校验指定路径是否为有效代码仓库。
  ///
  /// 返回更新后的 [RepoConfig]（含校验结果和时间戳）。
  Future<RepoConfig> validatePath(String rawPath) async {
    final trimmed = rawPath.trim();

    if (trimmed.isEmpty) {
      return RepoConfig(
        localPath: '',
        validationStatus: RepoValidationStatus.invalid,
        lastValidated: DateTime.now(),
        validationMessage: '路径不能为空',
      );
    }

    try {
      final dir = Directory(trimmed);

      // 检查路径是否存在
      if (!dir.existsSync()) {
        return RepoConfig(
          localPath: trimmed,
          validationStatus: RepoValidationStatus.notFound,
          lastValidated: DateTime.now(),
          validationMessage: '路径不存在: $trimmed',
        );
      }

      // 检查是否可读
      try {
        final entities = dir.listSync(recursive: false);
        if (entities.isEmpty) {
          return RepoConfig(
            localPath: trimmed,
            validationStatus: RepoValidationStatus.invalid,
            lastValidated: DateTime.now(),
            validationMessage: '目录为空，未检测到项目文件',
          );
        }

        // 检查是否包含可识别的项目文件
        final hasProjectFiles = entities.any((e) {
          final name = p.basename(e.path).toLowerCase();
          return _projectFilePatterns.any((pattern) => name == pattern);
        });

        if (!hasProjectFiles) {
          // 尝试递归查找子目录
          final subDirs = entities.whereType<Directory>();
          for (final sub in subDirs) {
            try {
              final subEntities = sub.listSync(recursive: false);
              final subHasProject = subEntities.any((e) {
                final name = p.basename(e.path).toLowerCase();
                return _projectFilePatterns.any((pattern) => name == pattern);
              });
              if (subHasProject) {
                return RepoConfig(
                  localPath: trimmed,
                  validationStatus: RepoValidationStatus.valid,
                  lastValidated: DateTime.now(),
                  validationMessage: '子目录中检测到项目文件 — 路径有效',
                );
              }
            } catch (_) {}
          }

          return RepoConfig(
            localPath: trimmed,
            validationStatus: RepoValidationStatus.valid,
            lastValidated: DateTime.now(),
            validationMessage:
                '未检测到常见项目文件，但仍可继续（AI 会自行探索）',
          );
        }

        return RepoConfig(
          localPath: trimmed,
          validationStatus: RepoValidationStatus.valid,
          lastValidated: DateTime.now(),
          validationMessage: '校验通过 — 检测到项目文件',
        );
      } on FileSystemException catch (e) {
        return RepoConfig(
          localPath: trimmed,
          validationStatus: RepoValidationStatus.permissionDenied,
          lastValidated: DateTime.now(),
          validationMessage: '权限不足: ${e.message}',
        );
      }
    } on FileSystemException catch (e) {
      return RepoConfig(
        localPath: trimmed,
        validationStatus: RepoValidationStatus.invalid,
        lastValidated: DateTime.now(),
        validationMessage: '文件系统错误: ${e.message}',
      );
    } catch (e) {
      return RepoConfig(
        localPath: trimmed,
        validationStatus: RepoValidationStatus.invalid,
        lastValidated: DateTime.now(),
        validationMessage: '校验异常: $e',
      );
    }
  }

  // ═══════ 持久化 ═══════

  /// 保存 [RepoConfig] 到文件。
  Future<void> saveConfig(RepoConfig config) async {
    try {
      final file = _configFile;
      final dir = file.parent;
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }

      final jsonStr = const JsonEncoder.withIndent('  ').convert(config.toJson());
      await file.writeAsString(jsonStr, flush: true);

      debugPrint('[RepoConfigService] ✓ 配置已保存 → ${file.path}');
    } catch (e) {
      debugPrint('[RepoConfigService] ✗ 保存配置失败: $e');
      rethrow;
    }
  }

  /// 从文件加载 [RepoConfig]。
  ///
  /// 返回 null 表示无已保存配置。
  Future<RepoConfig?> loadConfig() async {
    final file = _configFile;
    if (!file.existsSync()) return null;

    try {
      final raw = await file.readAsString();
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return RepoConfig.fromJson(json);
    } catch (e) {
      debugPrint('[RepoConfigService] 加载配置失败: $e');
      return null;
    }
  }

  /// 一键校验并保存。
  ///
  /// 校验 [rawPath] 后，将结果保存到磁盘，并返回校验后的 [RepoConfig]。
  Future<RepoConfig> validateAndSave(String rawPath) async {
    final config = await validatePath(rawPath);
    await saveConfig(config);
    return config;
  }

  /// 清空配置（重置为未配置状态）。
  Future<void> clearConfig() async {
    await saveConfig(RepoConfig.empty());
  }

  // ═══════ 内部 ═══════

  File get _configFile =>
      File(p.join(greenixWorkspaceDir(moduleId), 'repo-config.json'));

  /// 可识别的项目根目录文件名（大小写不敏感）。breakpoint
  static const _projectFilePatterns = <String>[
    'pubspec.yaml',
    'package.json',
    'build.gradle',
    'build.gradle.kts',
    'Cargo.toml',
    'go.mod',
    'CMakeLists.txt',
    'requirements.txt',
    'setup.py',
    'pyproject.toml',
    'Makefile',
    'pom.xml',
    '.git',
  ];

  static void debugPrint(String msg) {
    // 生产环境可关闭；当前保留以便调试
    print(msg);
  }
}
