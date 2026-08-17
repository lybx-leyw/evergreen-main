/// 探索授权范围（Scope Contract，移植自 reverse-skill scope-contract.md）。
///
/// 持久化用户授权边界：目标站点 + 数据范围。探索开始前由用户确认并落盘
/// `.greenix/scope.json`；运行时所有导航守卫（[ExploreWorkflow.recordNavigation]）
/// 与 Guardian 审查 prompt 均以本 scope 为唯一授权事实源。
///
/// 纯 Dart 无 Flutter 依赖，可独立单测。
library explore_scope;

// ═══════ 授权范围模型 ═══════

/// 探索授权范围（用户确认的持久化授权）。
class ExploreScope {
  /// 目标名称（如 "ZJU 教务课程"）。
  final String name;

  /// 基础域名（用于锁定展示与 UI）。
  final String baseHost;

  /// 授权资产 host 列表；`*.` 前缀表示含子域（如 `*.zju.edu.cn`）。
  final List<String> assets;

  /// 授权路径前缀；空 = 路径全部放行。匹配为前缀匹配（`/course` 命中 `/course/123`）。
  final List<String> paths;

  /// 数据范围描述（用户语义授权："课程列表与详情"）。
  final String dataScope;

  /// 授权时间（ISO8601 落盘；null 时落盘用当前时间）。
  final DateTime? signedAt;

  /// 状态：active | expired | revoked。
  final String status;

  const ExploreScope({
    required this.name,
    required this.baseHost,
    required this.assets,
    this.paths = const [],
    this.dataScope = '',
    this.signedAt,
    this.status = 'active',
  });

  bool get isActive => status == 'active';

  /// 校验 URL 是否落在授权范围内。
  ///
  /// 返回 null = 放行；否则为拒绝原因（http(s) / host 不在 assets /
  /// path 不在 paths）。仅校验授权边界，不做节流/页数等运行时守卫。
  String? validateUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return 'URL 为空';
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return 'URL 无法解析';
    final scheme = (uri.scheme.isEmpty ? 'http' : uri.scheme).toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return '超出授权范围：仅允许 http/https（"$scheme"）';
    }
    final host = uri.host.toLowerCase();
    if (host.isEmpty) return 'URL 缺少主机名';

    if (!_hostInAssets(host, assets)) {
      return '超出授权范围：主机 $host 不在授权资产（${assets.join(', ')}）内';
    }
    final path = uri.path.isEmpty ? '/' : uri.path;
    if (!_pathAllowed(path, paths)) {
      return '超出授权范围：路径 $path 不在授权路径（${paths.isEmpty ? '全部' : paths.join(', ')}）内';
    }
    return null;
  }

  /// 生成 Guardian prompt 注入摘要（英文，贴合 guardian_policy 语言）。
  String toPromptSummary() {
    final buf = StringBuffer()
      ..writeln('The user has authorised scraping ONLY the following target:')
      ..writeln('Name: $name')
      ..writeln('Hosts: ${assets.join(', ')}')
      ..writeln('Allowed path prefixes: ${paths.isEmpty ? 'all' : paths.join(', ')}')
      ..writeln('Data scope: ${dataScope.isEmpty ? '(not specified)' : dataScope}')
      ..writeln('Method: GET only');
    return buf.toString();
  }

  /// 简短 UI 摘要。
  String toDisplaySummary() {
    final parts = <String>[
      '站点: $baseHost',
      if (paths.isNotEmpty) '路径: ${paths.join(', ')}',
      if (dataScope.isNotEmpty) '范围: $dataScope',
    ];
    return parts.join(' · ');
  }

  // ── JSON 往返（.greenix/scope.json 持久化）──

  factory ExploreScope.fromJson(Map<String, dynamic> json) {
    return ExploreScope(
      name: (json['name'] as String? ?? '').trim(),
      baseHost: (json['baseHost'] as String? ?? '').trim(),
      assets: (json['assets'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .map((s) => s.trim().toLowerCase())
          .where((s) => s.isNotEmpty)
          .toList(),
      paths: (json['paths'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(),
      dataScope: (json['dataScope'] as String? ?? '').trim(),
      signedAt: DateTime.tryParse(json['signedAt'] as String? ?? ''),
      status: json['status'] as String? ?? 'active',
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'baseHost': baseHost,
        'assets': assets,
        'paths': paths,
        'dataScope': dataScope,
        'signedAt': (signedAt ?? DateTime.now()).toIso8601String(),
        'status': status,
      };
}

// ═══════ 纯函数 ═══════

/// host 是否命中授权资产：精确相等或 `*.` 子域通配。
bool _hostInAssets(String host, List<String> assets) {
  for (final raw in assets) {
    final a = raw.trim().toLowerCase();
    if (a.startsWith('*.')) {
      final suffix = a.substring(2);
      if (host == suffix || host.endsWith('.$suffix')) return true;
    } else if (host == a) {
      return true;
    }
  }
  return false;
}

/// path 是否命中授权前缀（空 paths = 全部放行）。
bool _pathAllowed(String path, List<String> paths) {
  if (paths.isEmpty) return true;
  for (final pt in paths) {
    final prefix = pt.trim();
    if (prefix.isEmpty) continue;
    if (path == prefix || path.startsWith(prefix)) return true;
  }
  return false;
}
