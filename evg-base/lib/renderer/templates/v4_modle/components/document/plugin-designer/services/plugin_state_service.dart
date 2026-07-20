/// 插件状态持久化服务 —— enabled/disabled + sidebar 可见性。
///
/// 状态文件: `plugins/.plugin_states.json`
/// 格式: { "plugin_id": { "enabled": true, "sidebarVisible": true, "installedAt": "...", "lastUsedAt": "..." } }
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// 单个插件的运行时状态。
class PluginStateRecord {
  final String pluginId;
  final bool enabled;
  final bool sidebarVisible;
  final DateTime installedAt;
  final DateTime lastUsedAt;

  const PluginStateRecord({
    required this.pluginId,
    this.enabled = true,
    this.sidebarVisible = true,
    required this.installedAt,
    required this.lastUsedAt,
  });

  PluginStateRecord copyWith({
    bool? enabled,
    bool? sidebarVisible,
    DateTime? lastUsedAt,
  }) {
    return PluginStateRecord(
      pluginId: pluginId,
      enabled: enabled ?? this.enabled,
      sidebarVisible: sidebarVisible ?? this.sidebarVisible,
      installedAt: installedAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'pluginId': pluginId,
        'enabled': enabled,
        'sidebarVisible': sidebarVisible,
        'installedAt': installedAt.toIso8601String(),
        'lastUsedAt': lastUsedAt.toIso8601String(),
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

  /// 读取全部状态。文件不存在时返回空 Map。
  Map<String, PluginStateRecord> loadAll() {
    final file = File(_statePath);
    if (!file.existsSync()) return {};

    try {
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final result = <String, PluginStateRecord>{};
      for (final entry in json.entries) {
        if (entry.value is Map<String, dynamic>) {
          result[entry.key] = PluginStateRecord.fromJson(
              entry.value as Map<String, dynamic>);
        }
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  /// 读取单个插件状态。
  PluginStateRecord? load(String pluginId) {
    return loadAll()[pluginId];
  }

  /// 保存单个插件状态。
  void save(PluginStateRecord record) {
    final all = loadAll();
    all[record.pluginId] = record;
    _writeAll(all);
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

  /// 标记插件已使用。
  void touch(String pluginId) {
    final existing = load(pluginId);
    if (existing != null) {
      save(existing.copyWith(lastUsedAt: DateTime.now()));
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
    final all = loadAll();
    all.remove(pluginId);
    _writeAll(all);
  }

  void _writeAll(Map<String, PluginStateRecord> all) {
    final file = File(_statePath);
    final dir = file.parent;
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final json = <String, dynamic>{};
    for (final entry in all.entries) {
      json[entry.key] = entry.value.toJson();
    }
    file.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(json));
  }

  /// 清除所有状态。
  void clear() {
    final file = File(_statePath);
    if (file.existsSync()) file.deleteSync();
  }
}
