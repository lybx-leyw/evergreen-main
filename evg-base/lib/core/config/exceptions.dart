/// Config 模块异常。
///
/// | 类 | 说明 |
/// |----|------|
/// | `ConfigMissingException` | 请求了不存在的配置项 |
/// | `ConfigValidationException` | 配置值校验失败 |
/// | `PermissionDeniedException` | 插件权限被拒绝 |
/// | `SourceDuplicateException` | 插件源重复添加 |

/// 请求了不存在的配置项。
class ConfigMissingException implements Exception {
  final String key;
  final String? recoveryHint;

  const ConfigMissingException(this.key, {this.recoveryHint});

  @override
  String toString() {
    final hint = recoveryHint != null ? ' 建议：$recoveryHint' : '';
    return 'ConfigMissingException: 配置项 "$key" 未声明。$hint';
  }
}

/// 配置值校验失败。
///
/// [key] 配置键，[value] 被拒绝的值，[reason] 拒绝原因。
class ConfigValidationException implements Exception {
  final String key;
  final String value;
  final String reason;

  const ConfigValidationException({
    required this.key,
    required this.value,
    required this.reason,
  });

  @override
  String toString() =>
      'ConfigValidationException: "$key" = "$value" 校验失败：$reason';
}

/// 插件权限被拒绝。
class PermissionDeniedException implements Exception {
  final String pluginId;
  final String permissionKey;

  const PermissionDeniedException(this.pluginId, this.permissionKey);

  @override
  String toString() =>
      'PermissionDeniedException: 插件 "$pluginId" 的权限 "$permissionKey" 已被拒绝。';
}

/// 插件源重复添加。
class SourceDuplicateException implements Exception {
  final String url;

  const SourceDuplicateException(this.url);

  @override
  String toString() =>
      'SourceDuplicateException: 插件源 "$url" 已存在。';
}
