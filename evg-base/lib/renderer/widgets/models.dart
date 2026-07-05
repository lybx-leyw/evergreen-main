/// 渲染层共享数据模型——Chat、Presentation、Market 等视图的轻量数据类。
///
/// 与 core/agent 的类型保持独立，仅用于渲染层内部。
library;

/// 聊天消息。
class ChatMessage {
  final String role;
  final String content;
  final String? thinkingContent;
  final List<ToolCallData> toolCalls;
  final DateTime timestamp;

  ChatMessage({
    required this.role,
    this.content = '',
    this.thinkingContent,
    this.toolCalls = const [],
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';
}

/// 工具调用数据。
class ToolCallData {
  final String name;
  final String arguments;
  final String? result;
  final bool completed;

  const ToolCallData({
    required this.name,
    this.arguments = '',
    this.result,
    this.completed = false,
  });
}

/// 幻灯片数据。
class SlideData {
  final String title;
  final String layout;
  final String? content;

  const SlideData({
    required this.title,
    this.layout = 'content',
    this.content,
  });
}

/// 工作区文件。
class WorkspaceFile {
  final String name;
  final String path;
  final int sizeBytes;

  const WorkspaceFile({
    required this.name,
    required this.path,
    this.sizeBytes = 0,
  });
}

// ═══════ Sprint 2: 页面数据模型 ═══════

/// 能力维度——对应六色标签体系。
enum AbilityDim {
  agent,
  ui,
  data,
  theme,
  settings,
  skill;

  String get label {
    switch (this) {
      case AbilityDim.agent:
        return 'Agent';
      case AbilityDim.ui:
        return 'UI';
      case AbilityDim.data:
        return 'Data';
      case AbilityDim.theme:
        return 'Theme';
      case AbilityDim.settings:
        return 'Settings';
      case AbilityDim.skill:
        return 'Skill';
    }
  }

  String get displayName {
    switch (this) {
      case AbilityDim.agent:
        return '智能体';
      case AbilityDim.ui:
        return '界面';
      case AbilityDim.data:
        return '数据';
      case AbilityDim.theme:
        return '主题';
      case AbilityDim.settings:
        return '设置';
      case AbilityDim.skill:
        return '技能';
    }
  }
}

/// 权限级别。
enum PermissionLevel { safe, warning, danger }

/// 插件权限条目。
class PluginPermission {
  final String name;
  final PermissionLevel level;
  /// 权限是否已授予（权限管理页使用，安装弹窗忽略此字段）。
  final bool granted;

  const PluginPermission({
    required this.name,
    this.level = PermissionLevel.safe,
    this.granted = true,
  });

  String get levelLabel {
    switch (level) {
      case PermissionLevel.safe:
        return '安全';
      case PermissionLevel.warning:
        return '中危';
      case PermissionLevel.danger:
        return '高危';
    }
  }

  PluginPermission copyWith({
    String? name,
    PermissionLevel? level,
    bool? granted,
  }) {
    return PluginPermission(
      name: name ?? this.name,
      level: level ?? this.level,
      granted: granted ?? this.granted,
    );
  }
}

/// 插件权限状态快照——权限管理页使用。
class PluginPermissionSnapshot {
  final String pluginId;
  final String pluginName;
  final List<PluginPermission> permissions;

  const PluginPermissionSnapshot({
    required this.pluginId,
    required this.pluginName,
    required this.permissions,
  });

  int get safeCount => permissions.where((p) => p.level == PermissionLevel.safe).length;
  int get warningCount => permissions.where((p) => p.level == PermissionLevel.warning).length;
  int get dangerCount => permissions.where((p) => p.level == PermissionLevel.danger).length;
  int get grantedCount => permissions.where((p) => p.granted).length;
}

/// 插件描述符——市场/工作台/详情/我的插件共用。
class PluginDescriptor {
  final String id;
  final String name;
  final String description;
  final String longDescription;
  final String author;
  final String version;
  final List<AbilityDim> dimensions;
  final List<PluginPermission> permissions;
  final int screenshotCount;
  final int installCount;
  final double rating;
  final bool installed;
  final bool hasUpdate;

  const PluginDescriptor({
    required this.id,
    required this.name,
    this.description = '',
    this.longDescription = '',
    this.author = '',
    this.version = '1.0.0',
    this.dimensions = const [],
    this.permissions = const [],
    this.screenshotCount = 0,
    this.installCount = 0,
    this.rating = 0.0,
    this.installed = false,
    this.hasUpdate = false,
  });
}

/// 安装进度状态。
class InstallProgress {
  final String pluginId;
  final double progress; // 0.0 ~ 1.0
  final InstallStatus status;
  final String? message;

  const InstallProgress({
    required this.pluginId,
    this.progress = 0.0,
    this.status = InstallStatus.preparing,
    this.message,
  });
}

/// 安装状态枚举。
enum InstallStatus {
  preparing,
  downloading,
  installing,
  completed,
  failed;

  String get label {
    switch (this) {
      case InstallStatus.preparing:
        return '准备安装...';
      case InstallStatus.downloading:
        return '下载中...';
      case InstallStatus.installing:
        return '安装中...';
      case InstallStatus.completed:
        return '安装完成';
      case InstallStatus.failed:
        return '安装失败';
    }
  }
}

/// 设置项类型。
enum SettingsItemType { toggle, link, info, action }

/// 设置项。
class SettingsItem {
  final String label;
  final String? description;
  final SettingsItemType type;
  final bool value;
  final String? actionLabel;
  final void Function()? onTap;
  final void Function(bool)? onToggle;

  const SettingsItem({
    required this.label,
    this.description,
    this.type = SettingsItemType.info,
    this.value = false,
    this.actionLabel,
    this.onTap,
    this.onToggle,
  });
}

/// 设置分组。
class SettingsGroup {
  final String title;
  final List<SettingsItem> items;

  const SettingsGroup({required this.title, this.items = const []});
}
