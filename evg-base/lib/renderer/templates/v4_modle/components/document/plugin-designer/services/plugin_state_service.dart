/// 插件状态持久化服务 —— enabled/disabled + sidebar 可见性 + 用户排序布局。
///
/// 状态文件: `plugins/.plugin_states.json`
/// 格式:
/// ```json
/// {
///   "_config": {
///     "sortMode": "group",
///     "groups": { "分组名": { "order": 0, "showNameInSidebar": true, "collapsed": false } }
///   },
///   "plugin_id": { "enabled": true, "sidebarVisible": true,
///                  "installedAt": "...", "lastUsedAt": "...", "sortOrder": 0 }
/// }
/// ```
///
/// 说明：
/// - `_config` 为插件中心布局配置（排序策略 / 分组顺序 / 组名是否显示在侧边栏 / 分组折叠）；
/// - 每条插件记录的 `sortOrder` 为**组内**用户拖拽顺序（null = 未拖拽，回退 manifest 顺序）；
/// - `lastUsedAt` 由 `touch()` 在用户打开插件时更新，供「按最近使用」排序。
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// 状态文件中的配置保留键（与插件 id 区分，加载记录时跳过）。
const String kPluginConfigKey = '_config';

/// 单个插件的运行时状态。
class PluginStateRecord {
  final String pluginId;
  final bool enabled;
  final bool sidebarVisible;
  final DateTime installedAt;
  final DateTime lastUsedAt;

  /// 组内用户拖拽顺序；null = 未自定义，回退 manifest 顺序。
  final int? sortOrder;

  const PluginStateRecord({
    required this.pluginId,
    this.enabled = true,
    this.sidebarVisible = true,
    required this.installedAt,
    required this.lastUsedAt,
    this.sortOrder,
  });

  PluginStateRecord copyWith({
    bool? enabled,
    bool? sidebarVisible,
    DateTime? lastUsedAt,
    int? sortOrder,
  }) {
    return PluginStateRecord(
      pluginId: pluginId,
      enabled: enabled ?? this.enabled,
      sidebarVisible: sidebarVisible ?? this.sidebarVisible,
      installedAt: installedAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  Map<String, dynamic> toJson() => {
        'pluginId': pluginId,
        'enabled': enabled,
        'sidebarVisible': sidebarVisible,
        'installedAt': installedAt.toIso8601String(),
        'lastUsedAt': lastUsedAt.toIso8601String(),
        if (sortOrder != null) 'sortOrder': sortOrder,
      };

  factory PluginStateRecord.fromJson(Map<String, dynamic> json) {
    return PluginStateRecord(
      pluginId: json['pluginId'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? true,
      sidebarVisible: json['sidebarVisible'] as bool? ?? true,
      installedAt: json['installedAt'] != null
          ? DateTime.tryParse(json['installedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      lastUsedAt: json['lastUsedAt'] != null
          ? DateTime.tryParse(json['lastUsedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      sortOrder: json['sortOrder'] as int?,
    );
  }
}

/// 单个分组的用户布局配置。
///
/// key 为分组名（插件 manifest 的 `nav.sidebar.section`，无侧栏时为「未分组」）。
class PluginGroupConfig {
  const PluginGroupConfig({
    required this.label,
    this.order = 0,
    this.showNameInSidebar = true,
    this.collapsed = false,
  });

  /// 分组名（与配置文件中的 key 一致）。
  final String label;

  /// 分组间拖拽顺序（0 起）；用户拖拽后按序落盘。
  final int order;

  /// 侧边栏是否显示本分组的组名（分组标题）。
  final bool showNameInSidebar;

  /// 插件中心分组视图是否折叠本组（仅影响插件中心展示）。
  final bool collapsed;

  PluginGroupConfig copyWith({
    int? order,
    bool? showNameInSidebar,
    bool? collapsed,
  }) {
    return PluginGroupConfig(
      label: label,
      order: order ?? this.order,
      showNameInSidebar: showNameInSidebar ?? this.showNameInSidebar,
      collapsed: collapsed ?? this.collapsed,
    );
  }

  Map<String, dynamic> toJson() => {
        'label': label,
        'order': order,
        'showNameInSidebar': showNameInSidebar,
        'collapsed': collapsed,
      };

  factory PluginGroupConfig.fromJson(Map<String, dynamic> json) {
    return PluginGroupConfig(
      label: json['label'] as String? ?? '',
      order: json['order'] as int? ?? 0,
      showNameInSidebar: json['showNameInSidebar'] as bool? ?? true,
      collapsed: json['collapsed'] as bool? ?? false,
    );
  }
}

/// 插件中心布局配置（`_config` 键）。
class PluginCenterConfig {
  const PluginCenterConfig({
    this.sortMode = 'group',
    this.groups = const {},
  });

  /// 排序策略：'group'（分组）/ 'name'（按名称）/ 'recent'（按最近使用）。
  final String sortMode;

  /// 分组名 → 分组配置（仅存用户自定义过的分组）。
  final Map<String, PluginGroupConfig> groups;

  PluginCenterConfig copyWith({
    String? sortMode,
    Map<String, PluginGroupConfig>? groups,
  }) {
    return PluginCenterConfig(
      sortMode: sortMode ?? this.sortMode,
      groups: groups ?? this.groups,
    );
  }

  Map<String, dynamic> toJson() => {
        'sortMode': sortMode,
        'groups': {
          for (final e in groups.entries) e.key: e.value.toJson(),
        },
      };

  factory PluginCenterConfig.fromJson(Map<String, dynamic> json) {
    final groups = <String, PluginGroupConfig>{};
    final raw = json['groups'];
    if (raw is Map<String, dynamic>) {
      for (final e in raw.entries) {
        if (e.value is Map<String, dynamic>) {
          groups[e.key] = PluginGroupConfig.fromJson({
            ...e.value as Map<String, dynamic>,
            'label': e.key,
          });
        }
      }
    }
    return PluginCenterConfig(
      sortMode: json['sortMode'] as String? ?? 'group',
      groups: groups,
    );
  }
}

/// 插件状态持久化服务。
///
/// 管理本地插件的 enabled/disabled/sidebarVisibility 状态，
/// 持久化到 `plugins/.plugin_states.json`。
class PluginStateService {
  final String _pluginsDir;

  PluginStateService(this._pluginsDir);

  String get _statePath => p.join(_pluginsDir, '.plugin_states.json');

  /// 读取整个状态文件的原始 JSON；不存在/损坏时返回 null（调用方按空处理）。
  Map<String, dynamic>? _readAllJson() {
    final file = File(_statePath);
    if (!file.existsSync()) return null;
    try {
      return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// 整体写回状态文件（保留记录与 `_config` 布局配置）。
  void _writeJson(Map<String, dynamic> all) {
    final file = File(_statePath);
    final dir = file.parent;
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(all));
  }

  /// 读取全部插件状态（跳过 `_config` 配置键）。文件不存在时返回空 Map。
  Map<String, PluginStateRecord> loadAll() {
    final json = _readAllJson();
    if (json == null) return {};

    final result = <String, PluginStateRecord>{};
    for (final entry in json.entries) {
      if (entry.key == kPluginConfigKey) continue;
      if (entry.value is Map<String, dynamic>) {
        result[entry.key] = PluginStateRecord.fromJson(
            entry.value as Map<String, dynamic>);
      }
    }
    return result;
  }

  /// 读取单个插件状态。
  PluginStateRecord? load(String pluginId) {
    return loadAll()[pluginId];
  }

  /// 保存单个插件状态（保留 `_config`）。
  void save(PluginStateRecord record) {
    final json = _readAllJson() ?? <String, dynamic>{};
    json[record.pluginId] = record.toJson();
    _writeJson(json);
  }

  // ═══════ 布局配置（_config） ═══════

  /// 读取插件中心布局配置；文件缺失/损坏时返回默认配置。
  PluginCenterConfig loadConfig() {
    final json = _readAllJson();
    final raw = json?[kPluginConfigKey];
    if (raw is Map<String, dynamic>) {
      return PluginCenterConfig.fromJson(raw);
    }
    return const PluginCenterConfig();
  }

  /// 保存布局配置（保留所有插件记录）。
  void saveConfig(PluginCenterConfig config) {
    final json = _readAllJson() ?? <String, dynamic>{};
    json[kPluginConfigKey] = config.toJson();
    _writeJson(json);
  }

  /// 设置排序策略（'group' / 'name' / 'recent'）。
  void setSortMode(String mode) {
    saveConfig(loadConfig().copyWith(sortMode: mode));
  }

  /// 按序落盘全部分组的拖拽顺序（0..n-1）。
  void setGroupOrderAll(List<String> orderedLabels) {
    final config = loadConfig();
    final groups = Map<String, PluginGroupConfig>.from(config.groups);
    for (var i = 0; i < orderedLabels.length; i++) {
      final label = orderedLabels[i];
      final g = groups[label] ?? PluginGroupConfig(label: label);
      groups[label] = g.copyWith(order: i);
    }
    saveConfig(config.copyWith(groups: groups));
  }

  /// 设置分组「侧边栏是否显示组名」。
  void setGroupShowNameInSidebar(String label, bool show) {
    final config = loadConfig();
    final groups = Map<String, PluginGroupConfig>.from(config.groups);
    final g = groups[label] ?? PluginGroupConfig(label: label);
    groups[label] = g.copyWith(showNameInSidebar: show);
    saveConfig(config.copyWith(groups: groups));
  }

  /// 设置分组在插件中心的折叠状态。
  void setGroupCollapsed(String label, bool collapsed) {
    final config = loadConfig();
    final groups = Map<String, PluginGroupConfig>.from(config.groups);
    final g = groups[label] ?? PluginGroupConfig(label: label);
    groups[label] = g.copyWith(collapsed: collapsed);
    saveConfig(config.copyWith(groups: groups));
  }

  /// 按序落盘某个分组内插件的拖拽顺序（0..n-1，单次写盘）。
  ///
  /// 无状态记录的插件会顺带补建默认记录（默认启用 + 侧栏可见）。
  void setPluginSortOrderAll(String groupLabel, List<String> orderedIds) {
    final json = _readAllJson() ?? <String, dynamic>{};
    final now = DateTime.now().toIso8601String();
    for (var i = 0; i < orderedIds.length; i++) {
      final id = orderedIds[i];
      final raw = json[id];
      final Map<String, dynamic> rec;
      if (raw is Map<String, dynamic>) {
        rec = Map<String, dynamic>.from(raw);
      } else {
        rec = {
          'pluginId': id,
          'enabled': true,
          'sidebarVisible': true,
          'installedAt': now,
          'lastUsedAt': now,
        };
      }
      rec['sortOrder'] = i;
      json[id] = rec;
    }
    _writeJson(json);
  }

  /// 设置插件启用/禁用。
  void setEnabled(String pluginId, bool enabled) {
    final existing = load(pluginId);
    if (existing != null) {
      save(existing.copyWith(enabled: enabled));
    } else {
      save(PluginStateRecord(
        pluginId: pluginId,
        enabled: enabled,
        sidebarVisible: true,
        installedAt: DateTime.now(),
        lastUsedAt: DateTime.now(),
      ));
    }
  }

  /// 设置侧边栏可见性。
  void setSidebarVisible(String pluginId, bool visible) {
    final existing = load(pluginId);
    if (existing != null) {
      save(existing.copyWith(sidebarVisible: visible));
    } else {
      save(PluginStateRecord(
        pluginId: pluginId,
        enabled: true,
        sidebarVisible: visible,
        installedAt: DateTime.now(),
        lastUsedAt: DateTime.now(),
      ));
    }
  }

  /// 标记插件已使用（用户打开插件时调用，驱动「按最近使用」排序）。
  ///
  /// 无状态记录的插件（如内置模块）会顺带补建默认记录，
  /// 否则它们永远不会出现在「最近使用」排序中。
  void touch(String pluginId) {
    final existing = load(pluginId);
    if (existing != null) {
      save(existing.copyWith(lastUsedAt: DateTime.now()));
    } else {
      save(PluginStateRecord(
        pluginId: pluginId,
        enabled: true,
        sidebarVisible: true,
        installedAt: DateTime.now(),
        lastUsedAt: DateTime.now(),
      ));
    }
  }

  /// 注册新安装的插件。
  void registerInstalled(String pluginId) {
    save(PluginStateRecord(
      pluginId: pluginId,
      enabled: true,
      sidebarVisible: true,
      installedAt: DateTime.now(),
      lastUsedAt: DateTime.now(),
    ));
  }

  /// 删除插件的状态记录（卸载时）。
  void remove(String pluginId) {
    final json = _readAllJson();
    if (json == null) return;
    json.remove(pluginId);
    _writeJson(json);
  }

  /// 清除所有状态（含布局配置）。
  void clear() {
    final file = File(_statePath);
    if (file.existsSync()) file.deleteSync();
  }
}
