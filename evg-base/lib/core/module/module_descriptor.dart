/// 模块描述符——所有模块通过 manifest.json 声明，[ModuleDescriptor.fromJson] 解析。
///
/// # [ModuleDescriptor] —— 模块声明
///
/// | 工厂 / 方法 | 输入 | 输出 | 说明 |
/// |---|---|---|---|
/// | `ModuleDescriptor(...)` | 各字段 | `ModuleDescriptor` | const 构造，内置模块用 |
/// | `ModuleDescriptor.fromJson(json)` | `Map<String, dynamic>` | `ModuleDescriptor` | 从 manifest.json 解析 |
/// | `ModuleDescriptor.fromJsonString(str)` | `String` | `ModuleDescriptor` | JSON 字符串解析 |
/// | `toJson()` | — | `Map<String, dynamic>` | 序列化 |
///
/// # 子描述符（全部 const 构造 + fromJson/toJson）
///
/// | 类 | 说明 |
/// |---|---|
/// | `SidebarDescriptor` | 侧边栏配置 |
/// | `NavDescriptor` | 子导航条目声明 |
/// | `LayoutDescriptor` | UI 布局偏好 |
/// | `GridOptions` | 分框布局 |
/// | `PanelDescriptor` | 多 tab 面板声明 |
/// | `ZoomDescriptor` | 缩放配置 |
/// | `SearchDescriptor` | 搜索栏配置 |
/// | `DataBindingDescriptor` | 数据绑定声明 |
/// | `ActionDescriptor` | 交互规则声明 |
/// | `ActionButtonDescriptor` | 动作按钮声明（composite 模式） |
/// | `RefreshDescriptor` | 刷新配置 |
/// | `DeletableDescriptor` | 删除行为配置 |
/// | `SpreadsheetOptions` | 电子表格模式选项 |
/// | `DocEditorOptions` | 文档编辑器选项 |
/// | `PresentationOptions` | 幻灯片模式选项 |
/// | `ChatOptions` | Chat 模式选项 |
/// | `ThinkingOptions` | 思考栏展示选项 |
/// | `ToolCallOptions` | 工具调用提示选项 |
/// | `BubbleOptions` | 气泡样式选项 |
/// | `StreamOptions` | 流式输出选项 |
/// | `InputOptions` | 键盘交互声明（与 actions 并列） |
/// | `AttachmentOptions` | 附件上传选项 |
/// | `FeedbackOptions` | 输入反馈配置（type-check 模式） |
/// | `FeedbackStateOptions` | 单次反馈状态（正确/错误） |
/// | `WorkspaceDescriptor` | 文件工作区声明 |
/// | `MediaDescriptor` | 内嵌文件展示声明 |
/// | `VideoOptions` | 视频选项（倍速/缓存/画质） |
/// | `AudioOptions` | 音频选项（倍速/波形） |
/// | `DocumentOptions` | 文档选项（缩放/搜索/分页） |
/// | `ImageOptions` | 图片选项（缩放/画廊） |
/// | `TimelineDescriptor` | 时间线/日历声明 |
/// | `MapDescriptor` | 地图/位置声明 |
/// | `FormDescriptor` | 结构化表单声明 |
/// | `FormFieldDescriptor` | 表单字段 |
/// | `FixedSizeOptions` | fixed 模式尺寸 |
/// | `ProcessDescriptor` | 后端进程配置 |
/// | `ComponentConfig` | 内容组件配置（composite 模式） |
/// | `PageDescriptor` | 页面描述符（composite 模式） |
library;

import 'dart:convert';
import 'package:flutter/material.dart';

// ═══════ JSON helpers ═══════

String _require(Map<String, dynamic> json, String key) {
  final v = json[key];
  if (v == null) throw FormatException('缺少必填字段 "$key"');
  return v.toString();
}

void _requireField(Map<String, dynamic> json, String key, String expected) {
  final v = _require(json, key);
  if (v != expected) throw FormatException('字段 "$key" 期望 "$expected"，实际 "$v"');
}

List<T> _requireList<T>(
  Map<String, dynamic> json,
  String key,
  T Function(dynamic) convert,
) {
  final raw = json[key];
  if (raw == null) return [];
  if (raw is! List) throw FormatException('字段 "$key" 必须是数组');
  return raw.map(convert).toList();
}

// ═══════ Icon 解析 ═══════

IconData? _parseIcon(dynamic raw) {
  if (raw == null) return null;
  if (raw is int) return IconData(raw);
  if (raw is String) {
    // 先查内置映射，再尝试 hex 解析
    final mapped = _iconMap[raw];
    if (mapped != null) return mapped;
    final i = int.tryParse(raw);
    if (i != null) return IconData(i);
    return null;
  }
  return null;
}

int? _iconToJson(IconData? icon) => icon?.codePoint;

const _iconMap = <String, IconData>{
  'extension': Icons.extension,
  'home': Icons.home,
  'settings': Icons.settings,
  'person': Icons.person,
  'school': Icons.school,
  'auto_awesome': Icons.auto_awesome,
  'code': Icons.code,
  'star': Icons.star,
  'bookmark': Icons.bookmark,
  'build': Icons.build,
  'dashboard': Icons.dashboard,
  'analytics': Icons.analytics,
  'chat': Icons.chat,
  'email': Icons.email,
  'notifications': Icons.notifications,
  'language': Icons.language,
  'search': Icons.search,
  'favorite': Icons.favorite,
  'timeline': Icons.timeline,
  'date_range': Icons.date_range,
  'folder': Icons.folder,
  'insert_drive_file': Icons.insert_drive_file,
  'cloud': Icons.cloud,
  'lock': Icons.lock,
  'account_circle': Icons.account_circle,
  'admin_panel_settings': Icons.admin_panel_settings,
  'apps': Icons.apps,
  'article': Icons.article,
  'assessment': Icons.assessment,
  'attach_money': Icons.attach_money,
  'bar_chart': Icons.bar_chart,
  'business': Icons.business,
  'calendar_month': Icons.calendar_month,
  'checklist': Icons.checklist,
  'contact_support': Icons.contact_support,
  'credit_card': Icons.credit_card,
  'dark_mode': Icons.dark_mode,
  'delete': Icons.delete,
  'description': Icons.description,
  'done': Icons.done,
  'download': Icons.download,
  'edit': Icons.edit,
  'engineering': Icons.engineering,
  'event': Icons.event,
  'explore': Icons.explore,
  'face': Icons.face,
  'filter_alt': Icons.filter_alt,
  'gavel': Icons.gavel,
  'group': Icons.group,
  'handshake': Icons.handshake,
  'help': Icons.help,
  'history': Icons.history,
  'info': Icons.info,
  'inventory': Icons.inventory,
  'lightbulb': Icons.lightbulb,
  'list_alt': Icons.list_alt,
  'local_library': Icons.local_library,
  'map': Icons.map,
  'mediation': Icons.mediation,
  'menu_book': Icons.menu_book,
  'model_training': Icons.model_training,
  'more_horiz': Icons.more_horiz,
  'music_note': Icons.music_note,
  'new_releases': Icons.new_releases,
  'open_in_new': Icons.open_in_new,
  'paid': Icons.paid,
  'palette': Icons.palette,
  'people': Icons.people,
  'percent': Icons.percent,
  'pie_chart': Icons.pie_chart,
  'playlist_add': Icons.playlist_add,
  'precision_manufacturing': Icons.precision_manufacturing,
  'preview': Icons.preview,
  'psychology': Icons.psychology,
  'public': Icons.public,
  'publish': Icons.publish,
  'push_pin': Icons.push_pin,
  'quiz': Icons.quiz,
  'receipt': Icons.receipt,
  'rocket': Icons.rocket,
  'rule': Icons.rule,
  'schedule': Icons.schedule,
  'science': Icons.science,
  'score': Icons.score,
  'security': Icons.security,
  'self_improvement': Icons.self_improvement,
  'shopping_cart': Icons.shopping_cart,
  'smart_toy': Icons.smart_toy,
  'spa': Icons.spa,
  'speed': Icons.speed,
  'storage': Icons.storage,
  'store': Icons.store,
  'stream': Icons.stream,
  'support': Icons.support,
  'switch_account': Icons.switch_account,
  'task': Icons.task,
  'thermostat': Icons.thermostat,
  'thumb_up': Icons.thumb_up,
  'tour': Icons.tour,
  'toys': Icons.toys,
  'translate': Icons.translate,
  'trending_up': Icons.trending_up,
  'tune': Icons.tune,
  'update': Icons.update,
  'upgrade': Icons.upgrade,
  'verified': Icons.verified,
  'videocam': Icons.videocam,
  'view_kanban': Icons.view_kanban,
  'visibility': Icons.visibility,
  'volume_up': Icons.volume_up,
  'wallet': Icons.wallet,
  'warning': Icons.warning,
  'workspace_premium': Icons.workspace_premium,
};

// ═══════ ProcessDescriptor ═══════

/// 后端进程配置（.exe 插件）。
class ProcessDescriptor {
  final String exe;

  /// 通信协议："http"（localhost HTTP）| "stdio"（stdin/stdout JSON）。
  final String protocol;

  final int preferredPort;

  const ProcessDescriptor({
    required this.exe,
    this.protocol = 'http',
    this.preferredPort = 0,
  });

  factory ProcessDescriptor.fromJson(Map<String, dynamic> json) => ProcessDescriptor(
    exe: _require(json, 'exe'),
    protocol: json['protocol'] as String? ?? 'http',
    preferredPort: json['preferredPort'] as int? ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'exe': exe,
    'protocol': protocol,
    'preferredPort': preferredPort,
  };
}

// ═══════ DataBindingDescriptor ═══════

/// 数据绑定声明——引用 [DataType.name] 并指定展示方式。
class DataBindingDescriptor {
  /// 指向 data/ 模块的 DataType.name。
  final String dataType;

  /// 展示方式：table | list | card | raw。
  final String display;

  /// 是否支持前端筛选。
  final bool filter;

  const DataBindingDescriptor({
    required this.dataType,
    this.display = 'list',
    this.filter = false,
  });

  factory DataBindingDescriptor.fromJson(Map<String, dynamic> json) =>
      DataBindingDescriptor(
        dataType: _require(json, 'type'),
        display: json['display'] as String? ?? 'list',
        filter: json['filter'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
    'type': dataType,
    'display': display,
    'filter': filter,
  };
}

// ═══════ RefreshDescriptor ═══════

/// 刷新配置。
class RefreshDescriptor {
  final bool enabled;
  final bool pullToRefresh;
  final int autoInterval; // 自动刷新间隔（秒），0 = 不自动刷新

  const RefreshDescriptor({
    this.enabled = false,
    this.pullToRefresh = true,
    this.autoInterval = 0,
  });

  factory RefreshDescriptor.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const RefreshDescriptor();
    return RefreshDescriptor(
      enabled: json['enabled'] as bool? ?? false,
      pullToRefresh: json['pullToRefresh'] as bool? ?? true,
      autoInterval: json['autoInterval'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'pullToRefresh': pullToRefresh,
    'autoInterval': autoInterval,
  };
}

// ═══════ DeletableDescriptor ═══════

/// 删除行为配置。
class DeletableDescriptor {
  /// 是否允许删除。
  final bool enabled;

  /// 删除前是否需要确认弹窗。
  final bool confirm;

  const DeletableDescriptor({
    this.enabled = false,
    this.confirm = true,
  });

  factory DeletableDescriptor.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const DeletableDescriptor();
    return DeletableDescriptor(
      enabled: json['enabled'] as bool? ?? false,
      confirm: json['confirm'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'confirm': confirm,
  };
}

// ═══════ ActionDescriptor ═══════

/// 交互规则声明——告诉下游渲染层模块支持哪些用户操作。
class ActionDescriptor {
  /// 点击列表项行为：null | "detail" | "select" | "none"
  final String? itemTap;

  /// 长按列表项行为：null | "context_menu" | "none"
  final String? itemLongPress;

  /// 侧滑列表项行为：null | "delete" | "archive" | "none"
  final String? itemSwipe;

  /// 选择模式："none" | "single" | "multi"
  final String selection;

  final RefreshDescriptor? refresh;

  /// 可排序字段列表。
  final List<String> sortable;

  /// 是否允许新增。
  final bool creatable;

  /// 是否允许编辑。
  final bool editable;

  /// 删除行为配置。
  final DeletableDescriptor? deletable;

  /// 可导出格式：csv / pdf / json。
  final List<String> exportable;

  const ActionDescriptor({
    this.itemTap,
    this.itemLongPress,
    this.itemSwipe,
    this.selection = 'none',
    this.refresh,
    this.sortable = const [],
    this.creatable = false,
    this.editable = false,
    this.deletable,
    this.exportable = const [],
  });

  factory ActionDescriptor.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ActionDescriptor();
    return ActionDescriptor(
      itemTap: json['itemTap'] as String?,
      itemLongPress: json['itemLongPress'] as String?,
      itemSwipe: json['itemSwipe'] as String?,
      selection: json['selection'] as String? ?? 'none',
      refresh: RefreshDescriptor.fromJson(
          json['refresh'] as Map<String, dynamic>?),
      sortable: (json['sortable'] as List?)
              ?.map((s) => s.toString())
              .toList() ??
          [],
      creatable: json['creatable'] as bool? ?? false,
      editable: json['editable'] as bool? ?? false,
      deletable: DeletableDescriptor.fromJson(
          json['deletable'] as Map<String, dynamic>?),
      exportable: (json['exportable'] as List?)
              ?.map((s) => s.toString())
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'selection': selection,
      'creatable': creatable,
      'editable': editable,
    };
    if (itemTap != null) m['itemTap'] = itemTap;
    if (itemLongPress != null) m['itemLongPress'] = itemLongPress;
    if (itemSwipe != null) m['itemSwipe'] = itemSwipe;
    if (refresh != null) m['refresh'] = refresh!.toJson();
    if (sortable.isNotEmpty) m['sortable'] = sortable;
    if (deletable != null) m['deletable'] = deletable!.toJson();
    if (exportable.isNotEmpty) m['exportable'] = exportable;
    return m;
  }
}

// ═══════ ZoomDescriptor ═══════

/// 缩放配置。
class ZoomDescriptor {
  final bool enabled;
  final double min;
  final double max;

  const ZoomDescriptor({
    this.enabled = false,
    this.min = 0.5,
    this.max = 2.0,
  });

  factory ZoomDescriptor.fromJson(Map<String, dynamic> json) => ZoomDescriptor(
    enabled: json['enabled'] as bool? ?? false,
    min: (json['min'] as num?)?.toDouble() ?? 0.5,
    max: (json['max'] as num?)?.toDouble() ?? 2.0,
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'min': min,
    'max': max,
  };
}

// ═══════ SearchDescriptor ═══════

/// 搜索栏配置。
class SearchDescriptor {
  final bool enabled;
  final String placeholder;

  const SearchDescriptor({
    this.enabled = false,
    this.placeholder = '搜索...',
  });

  factory SearchDescriptor.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const SearchDescriptor();
    return SearchDescriptor(
      enabled: json['enabled'] as bool? ?? false,
      placeholder: json['placeholder'] as String? ?? '搜索...',
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'placeholder': placeholder,
  };
}

// ═══════ PanelDescriptor ═══════

/// 多 tab 面板声明。
class PanelDescriptor {
  final String id;
  final String label;
  final String path;
  final bool isDefault;

  const PanelDescriptor({
    required this.id,
    required this.label,
    required this.path,
    this.isDefault = false,
  });

  factory PanelDescriptor.fromJson(Map<String, dynamic> json) =>
      PanelDescriptor(
        id: _require(json, 'id'),
        label: _require(json, 'label'),
        path: _require(json, 'path'),
        isDefault: json['default'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'path': path,
    'default': isDefault,
  };
}

// ═══════ GridOptions ═══════

/// 分框布局——一页内多框并排展示。
///
/// 不填 = 不分框（默认单列流式布局）。
class GridOptions {
  /// 列数。
  final int columns;

  /// 框间距（像素）。
  final int gap;

  const GridOptions({
    this.columns = 2,
    this.gap = 16,
  });

  factory GridOptions.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const GridOptions();
    return GridOptions(
      columns: json['columns'] as int? ?? 2,
      gap: json['gap'] as int? ?? 16,
    );
  }

  Map<String, dynamic> toJson() => {
    'columns': columns,
    'gap': gap,
  };
}

// ═══════ LayoutDescriptor ═══════

/// UI 布局偏好。
class LayoutDescriptor {
  /// 滚动模式：scroll（滑动窗口）| fit（自适应缩放）。
  final String mode;

  /// 分框布局（不填 = 单列）。
  final GridOptions? grid;

  final ZoomDescriptor zoom;
  final List<String> drawers; // 子集: top, left, right, bottom
  final SearchDescriptor? search;
  final List<PanelDescriptor> panels;

  const LayoutDescriptor({
    this.mode = 'scroll',
    this.grid,
    this.zoom = const ZoomDescriptor(),
    this.drawers = const [],
    this.search,
    this.panels = const [],
  });

  factory LayoutDescriptor.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const LayoutDescriptor();
    return LayoutDescriptor(
      mode: json['mode'] as String? ?? 'scroll',
      grid: GridOptions.fromJson(
          json['grid'] as Map<String, dynamic>?),
      zoom: json['zoom'] != null
          ? ZoomDescriptor.fromJson(json['zoom'] as Map<String, dynamic>)
          : const ZoomDescriptor(),
      drawers: (json['drawers'] as List?)
              ?.map((d) => d.toString())
              .toList() ??
          [],
      search: SearchDescriptor.fromJson(
          json['search'] as Map<String, dynamic>?),
      panels: _requireList(json, 'panels',
          (d) => PanelDescriptor.fromJson(d as Map<String, dynamic>)),
    );
  }

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'mode': mode,
      'zoom': zoom.toJson(),
      'drawers': drawers,
      'search': search?.toJson(),
      'panels': panels.map((p) => p.toJson()).toList(),
    };
    if (grid != null) m['grid'] = grid!.toJson();
    return m;
  }
}

// ═══════ NavDescriptor ═══════

/// 子导航条目声明（多页面模块用）。
class NavDescriptor {
  final IconData? icon;
  final String label;
  final String routePath;
  final String section; // SidebarSection.label

  const NavDescriptor({
    this.icon,
    required this.label,
    required this.routePath,
    required this.section,
  });

  factory NavDescriptor.fromJson(Map<String, dynamic> json) => NavDescriptor(
    icon: _parseIcon(json['icon']),
    label: _require(json, 'label'),
    routePath: _require(json, 'routePath'),
    section: _require(json, 'section'),
  );

  Map<String, dynamic> toJson() => {
    'label': label,
    'routePath': routePath,
    'section': section,
    if (icon != null) 'icon': _iconToJson(icon),
  };
}

// ═══════ ThinkingOptions ═══════

/// 思考栏展示选项（chat 模式）。
class ThinkingOptions {
  /// 是否展示思考栏。
  final bool visible;

  /// 思考栏背景是否透明（类似 DeepSeek 网页版）。
  final bool transparent;

  /// 展开模式："expand"（直接展开）| "scroll"（滑动窗口）。
  final String mode;

  /// 是否展示思考耗时。
  final bool showDuration;

  const ThinkingOptions({
    this.visible = true,
    this.transparent = false,
    this.mode = 'expand',
    this.showDuration = false,
  });

  factory ThinkingOptions.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ThinkingOptions();
    return ThinkingOptions(
      visible: json['visible'] as bool? ?? true,
      transparent: json['transparent'] as bool? ?? false,
      mode: json['mode'] as String? ?? 'expand',
      showDuration: json['showDuration'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'visible': visible,
    'transparent': transparent,
    'mode': mode,
    'showDuration': showDuration,
  };
}

// ═══════ ToolCallOptions ═══════

/// 工具调用提示选项（chat 模式）。
class ToolCallOptions {
  /// 是否展示工具调用。
  final bool visible;

  /// 是否展示调用参数。
  final bool showArgs;

  /// 是否展示调用结果。
  final bool showResult;

  /// 完成后是否自动折叠。
  final bool autoCollapse;

  const ToolCallOptions({
    this.visible = true,
    this.showArgs = true,
    this.showResult = true,
    this.autoCollapse = false,
  });

  factory ToolCallOptions.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ToolCallOptions();
    return ToolCallOptions(
      visible: json['visible'] as bool? ?? true,
      showArgs: json['showArgs'] as bool? ?? true,
      showResult: json['showResult'] as bool? ?? true,
      autoCollapse: json['autoCollapse'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'visible': visible,
    'showArgs': showArgs,
    'showResult': showResult,
    'autoCollapse': autoCollapse,
  };
}

// ═══════ BubbleOptions ═══════

/// 气泡样式选项（chat 模式）。
class BubbleOptions {
  /// 气泡风格："rounded" | "flat" | "minimal"。
  final String style;

  /// 头像位置："left" | "none"。
  final String avatarPosition;

  /// 是否显示时间戳。
  final bool showTimestamp;

  const BubbleOptions({
    this.style = 'rounded',
    this.avatarPosition = 'left',
    this.showTimestamp = true,
  });

  factory BubbleOptions.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const BubbleOptions();
    return BubbleOptions(
      style: json['style'] as String? ?? 'rounded',
      avatarPosition: json['avatarPosition'] as String? ?? 'left',
      showTimestamp: json['showTimestamp'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'style': style,
    'avatarPosition': avatarPosition,
    'showTimestamp': showTimestamp,
  };
}

// ═══════ StreamOptions ═══════

/// 流式输出选项（chat 模式）。
class StreamOptions {
  /// 是否启用流式输出。
  final bool enabled;

  /// 动画类型："typewriter" | "fade" | "none"。
  final String animation;

  /// 光标样式："blinking" | "static" | "none"。
  final String cursorStyle;

  const StreamOptions({
    this.enabled = true,
    this.animation = 'typewriter',
    this.cursorStyle = 'blinking',
  });

  factory StreamOptions.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const StreamOptions();
    return StreamOptions(
      enabled: json['enabled'] as bool? ?? true,
      animation: json['animation'] as String? ?? 'typewriter',
      cursorStyle: json['cursorStyle'] as String? ?? 'blinking',
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'animation': animation,
    'cursorStyle': cursorStyle,
  };
}

// ═══════ AttachmentOptions ═══════

/// 附件/上传选项（chat 输入区）。
class AttachmentOptions {
  /// 是否支持附件。
  final bool enabled;

  /// 允许的附件类型：image / file / audio。
  final List<String> types;

  /// 单文件最大体积（MB），0 = 不限制。
  final int maxSizeMb;

  const AttachmentOptions({
    this.enabled = false,
    this.types = const ['image', 'file'],
    this.maxSizeMb = 0,
  });

  factory AttachmentOptions.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const AttachmentOptions();
    return AttachmentOptions(
      enabled: json['enabled'] as bool? ?? false,
      types: (json['types'] as List?)
              ?.map((t) => t.toString())
              .toList() ??
          ['image', 'file'],
      maxSizeMb: json['maxSizeMb'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'types': types,
    'maxSizeMb': maxSizeMb,
  };
}

// ═══════ FeedbackStateOptions ═══════

/// 输入反馈——单次状态（正确/错误）的 UI 配置。
class FeedbackStateOptions {
  /// 反馈颜色（hex，如 "#4caf50"）。
  final String color;

  /// 反馈动画："bounce" | "shake" | "pulse" | "none"。
  final String animation;

  const FeedbackStateOptions({
    this.color = '#4caf50',
    this.animation = 'bounce',
  });

  factory FeedbackStateOptions.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const FeedbackStateOptions();
    return FeedbackStateOptions(
      color: json['color'] as String? ?? '#4caf50',
      animation: json['animation'] as String? ?? 'bounce',
    );
  }

  Map<String, dynamic> toJson() => {
    'color': color,
    'animation': animation,
  };
}

// ═══════ FeedbackOptions ═══════

/// 输入反馈配置——type-check 模式用。
class FeedbackOptions {
  final FeedbackStateOptions correct;
  final FeedbackStateOptions incorrect;

  const FeedbackOptions({
    this.correct = const FeedbackStateOptions(),
    this.incorrect = const FeedbackStateOptions(color: '#f44336', animation: 'shake'),
  });

  factory FeedbackOptions.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const FeedbackOptions();
    return FeedbackOptions(
      correct: FeedbackStateOptions.fromJson(
          json['correct'] as Map<String, dynamic>?),
      incorrect: FeedbackStateOptions.fromJson(
          json['incorrect'] as Map<String, dynamic>?),
    );
  }

  Map<String, dynamic> toJson() => {
    'correct': correct.toJson(),
    'incorrect': incorrect.toJson(),
  };
}

// ═══════ InputOptions ═══════

/// 键盘交互声明——与 [ActionDescriptor]（鼠标/触摸）并列的输入原语。
///
/// 顶层字段，不限于 chat 模式。不同 [mode] 适用不同子选项。
///
/// | mode | 适用场景 | 生效子字段 |
/// |---|---|---|
/// | `free-text` | 聊天输入、评论框 | multiline, sendOnEnter, attachments, voice, slashCommands, quickReplies |
/// | `type-check` | 打字背词、听写 | caseSensitive, feedback |
/// | `code` | 代码编辑器 | language, autoIndent, tabSize |
/// | `select` | 单选题 | options |
class InputOptions {
  /// 输入模式："free-text" | "type-check" | "code" | "select"。
  final String mode;

  /// 自动聚焦。
  final bool autoFocus;

  /// 最大输入长度，0 = 不限制。
  final int maxLength;

  // ── free-text 模式 ──

  /// 多行输入。
  final bool multiline;

  /// Enter 发送（false = Shift+Enter 发送）。
  final bool sendOnEnter;

  /// 附件上传。
  final AttachmentOptions attachments;

  /// 语音输入。
  final bool voice;

  /// 斜杠命令（/help、/clear）。
  final bool slashCommands;

  /// 快捷回复建议。
  final List<String> quickReplies;

  // ── type-check 模式 ──

  /// 是否区分大小写。
  final bool caseSensitive;

  /// 正确/错误 UI 反馈。
  final FeedbackOptions feedback;

  // ── code 模式 ──

  /// 编程语言（语法高亮用）。
  final String language;

  /// 自动缩进。
  final bool autoIndent;

  /// Tab 空格数。
  final int tabSize;

  // ── select 模式 ──

  /// 选项列表。
  final List<String> options;

  const InputOptions({
    this.mode = 'free-text',
    this.autoFocus = true,
    this.maxLength = 0,
    this.multiline = true,
    this.sendOnEnter = true,
    this.attachments = const AttachmentOptions(),
    this.voice = false,
    this.slashCommands = false,
    this.quickReplies = const [],
    this.caseSensitive = false,
    this.feedback = const FeedbackOptions(),
    this.language = '',
    this.autoIndent = true,
    this.tabSize = 2,
    this.options = const [],
  });

  factory InputOptions.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const InputOptions();
    return InputOptions(
      mode: json['mode'] as String? ?? 'free-text',
      autoFocus: json['autoFocus'] as bool? ?? true,
      maxLength: json['maxLength'] as int? ?? 0,
      multiline: json['multiline'] as bool? ?? true,
      sendOnEnter: json['sendOnEnter'] as bool? ?? true,
      attachments: AttachmentOptions.fromJson(
          json['attachments'] as Map<String, dynamic>?),
      voice: json['voice'] as bool? ?? false,
      slashCommands: json['slashCommands'] as bool? ?? false,
      quickReplies: (json['quickReplies'] as List?)
              ?.map((r) => r.toString())
              .toList() ??
          [],
      caseSensitive: json['caseSensitive'] as bool? ?? false,
      feedback: FeedbackOptions.fromJson(
          json['feedback'] as Map<String, dynamic>?),
      language: json['language'] as String? ?? '',
      autoIndent: json['autoIndent'] as bool? ?? true,
      tabSize: json['tabSize'] as int? ?? 2,
      options: (json['options'] as List?)
              ?.map((o) => o.toString())
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'mode': mode,
      'autoFocus': autoFocus,
      'maxLength': maxLength,
    };
    if (mode == 'free-text') {
      m['multiline'] = multiline;
      m['sendOnEnter'] = sendOnEnter;
      m['attachments'] = attachments.toJson();
      m['voice'] = voice;
      m['slashCommands'] = slashCommands;
      if (quickReplies.isNotEmpty) m['quickReplies'] = quickReplies;
    }
    if (mode == 'type-check') {
      m['caseSensitive'] = caseSensitive;
      m['feedback'] = feedback.toJson();
    }
    if (mode == 'code') {
      m['language'] = language;
      m['autoIndent'] = autoIndent;
      m['tabSize'] = tabSize;
    }
    if (mode == 'select') {
      if (options.isNotEmpty) m['options'] = options;
    }
    return m;
  }
}

// ═══════ FixedSizeOptions ═══════

/// fixed 模式尺寸（"adaptive" 或硬编码像素）。
class FixedSizeOptions {
  /// 宽度：null = 自适应，"auto" = 内容撑开，数字 = 像素。
  final dynamic width;

  /// 高度：null = 自适应，"auto" = 内容撑开，数字 = 像素。
  final dynamic height;

  const FixedSizeOptions({this.width, this.height});

  factory FixedSizeOptions.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const FixedSizeOptions();
    return FixedSizeOptions(
      width: json['width'],
      height: json['height'],
    );
  }

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{};
    if (width != null) m['width'] = width;
    if (height != null) m['height'] = height;
    return m;
  }
}

// ═══════ WorkspaceDescriptor ═══════

/// 文件工作区声明——用户与 AI 共享的持久文件池。
///
/// 与 [MediaDescriptor]（展示）、[InputOptions.attachments]（上传到消息）正交。
/// .exe 后端负责存储、索引、生成。
class WorkspaceDescriptor {
  /// 是否启用文件工作区。
  final bool enabled;

  /// 接受的文件后缀。
  final String accept;

  /// 最大文件数，0 = 不限制。
  final int maxFiles;

  /// 单文件最大体积（MB），0 = 不限制。
  final int maxSizeMb;

  /// AI 可创建的文件格式：pptx / docx / pdf / xlsx / csv / tex / png。
  final List<String> aiCreatable;

  /// 文件是否跨会话持久。
  final bool persistAcrossSessions;

  const WorkspaceDescriptor({
    this.enabled = false,
    this.accept = '*.pdf,*.docx,*.pptx,*.xlsx,*.jpg,*.png,*.txt',
    this.maxFiles = 20,
    this.maxSizeMb = 50,
    this.aiCreatable = const [],
    this.persistAcrossSessions = true,
  });

  factory WorkspaceDescriptor.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const WorkspaceDescriptor();
    return WorkspaceDescriptor(
      enabled: json['enabled'] as bool? ?? false,
      accept: json['accept'] as String? ??
          '*.pdf,*.docx,*.pptx,*.xlsx,*.jpg,*.png,*.txt',
      maxFiles: json['maxFiles'] as int? ?? 20,
      maxSizeMb: json['maxSizeMb'] as int? ?? 50,
      aiCreatable: (json['aiCreatable'] as List?)
              ?.map((f) => f.toString())
              .toList() ??
          [],
      persistAcrossSessions: json['persistAcrossSessions'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'accept': accept,
    'maxFiles': maxFiles,
    'maxSizeMb': maxSizeMb,
    'aiCreatable': aiCreatable,
    'persistAcrossSessions': persistAcrossSessions,
  };
}

// ═══════ VideoOptions ═══════

/// 视频专属选项。
class VideoOptions {
  /// 倍速选项：[0.5, 1.0, 1.5, 2.0]。
  final List<double> speeds;

  /// 是否缓存。
  final bool cache;

  /// 默认画质："auto" | "360p" | "720p" | "1080p"。
  final String quality;

  /// 是否显示字幕。
  final bool captions;

  const VideoOptions({
    this.speeds = const [0.5, 1.0, 1.5, 2.0],
    this.cache = false,
    this.quality = 'auto',
    this.captions = false,
  });

  factory VideoOptions.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const VideoOptions();
    return VideoOptions(
      speeds: (json['speeds'] as List?)
              ?.map((s) => (s as num).toDouble())
              .toList() ??
          [0.5, 1.0, 1.5, 2.0],
      cache: json['cache'] as bool? ?? false,
      quality: json['quality'] as String? ?? 'auto',
      captions: json['captions'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'speeds': speeds,
    'cache': cache,
    'quality': quality,
    'captions': captions,
  };
}

// ═══════ AudioOptions ═══════

/// 音频专属选项。
class AudioOptions {
  /// 倍速选项。
  final List<double> speeds;

  /// 是否显示波形。
  final bool waveform;

  const AudioOptions({
    this.speeds = const [0.5, 1.0, 1.5, 2.0],
    this.waveform = false,
  });

  factory AudioOptions.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const AudioOptions();
    return AudioOptions(
      speeds: (json['speeds'] as List?)
              ?.map((s) => (s as num).toDouble())
              .toList() ??
          [0.5, 1.0, 1.5, 2.0],
      waveform: json['waveform'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'speeds': speeds,
    'waveform': waveform,
  };
}

// ═══════ DocumentOptions ═══════

/// 文档专属选项（pdf / docx / pptx / xlsx 等）。
class DocumentOptions {
  /// 捏合缩放。
  final bool zoomable;

  /// 文档内搜索。
  final bool searchable;

  /// 是否显示页码。
  final bool pageIndicator;

  /// 分页展示（dropdown 模式）。
  final bool paginated;

  const DocumentOptions({
    this.zoomable = true,
    this.searchable = false,
    this.pageIndicator = true,
    this.paginated = false,
  });

  factory DocumentOptions.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const DocumentOptions();
    return DocumentOptions(
      zoomable: json['zoomable'] as bool? ?? true,
      searchable: json['searchable'] as bool? ?? false,
      pageIndicator: json['pageIndicator'] as bool? ?? true,
      paginated: json['paginated'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'zoomable': zoomable,
    'searchable': searchable,
    'pageIndicator': pageIndicator,
    'paginated': paginated,
  };
}

// ═══════ ImageOptions ═══════

/// 图片专属选项。
class ImageOptions {
  /// 捏合缩放。
  final bool zoomable;

  /// 是否以画廊模式展示（多图左右翻页）。
  final bool gallery;

  const ImageOptions({
    this.zoomable = true,
    this.gallery = false,
  });

  factory ImageOptions.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ImageOptions();
    return ImageOptions(
      zoomable: json['zoomable'] as bool? ?? true,
      gallery: json['gallery'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'zoomable': zoomable,
    'gallery': gallery,
  };
}

// ═══════ MediaDescriptor ═══════

/// 内嵌文件展示声明——本质是文件，由后缀决定解析方式。
///
/// 与 [ActionDescriptor]、[InputOptions] 并列的展示原语。
///
/// | mode | 行为 |
/// |---|---|
/// | `inline` | 内嵌在内容流中，随页面滚动 |
/// | `fullscreen` | 撑满模块视口（保留导航栏） |
/// | `drawer` | 从边缘滑入面板，推挤现有内容 |
/// | `dropdown` | 从顶部下拉面板，下方内容重排到面板之下 |
/// | `fixed` | 固定尺寸区域；不填 fixedSize 则自适应 |
class MediaDescriptor {
  /// 接受的文件后缀，逗号分隔：如 "*.mp4,*.webm" / "*.pdf" / "*.docx,*.doc" / "*.jpg,*.png"。
  final String accept;

  /// 展示模式："inline" | "fullscreen" | "drawer" | "dropdown" | "fixed"。
  final String mode;

  /// drawer/dropdown 滑入方向："top" | "bottom" | "left" | "right"。
  final String direction;

  /// fixed 模式尺寸（不填 = 自适应）。
  final FixedSizeOptions? fixedSize;

  /// 是否显示控件（播放器按钮 / 文档工具栏）。
  final bool controls;

  /// 视频选项（accept 含 *.mp4 等时生效）。
  final VideoOptions? video;

  /// 音频选项（accept 含 *.mp3 等时生效）。
  final AudioOptions? audio;

  /// 文档选项（accept 含 *.pdf/*.docx 等时生效）。
  final DocumentOptions? document;

  /// 图片选项（accept 含 *.jpg/*.png 等时生效）。
  final ImageOptions? image;

  const MediaDescriptor({
    required this.accept,
    this.mode = 'inline',
    this.direction = 'top',
    this.fixedSize,
    this.controls = true,
    this.video,
    this.audio,
    this.document,
    this.image,
  });

  factory MediaDescriptor.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const MediaDescriptor(accept: '*.*');
    return MediaDescriptor(
      accept: json['accept'] as String? ?? '*.*',
      mode: json['mode'] as String? ?? 'inline',
      direction: json['direction'] as String? ?? 'top',
      fixedSize: FixedSizeOptions.fromJson(
          json['fixedSize'] as Map<String, dynamic>?),
      controls: json['controls'] as bool? ?? true,
      video: VideoOptions.fromJson(
          json['video'] as Map<String, dynamic>?),
      audio: AudioOptions.fromJson(
          json['audio'] as Map<String, dynamic>?),
      document: DocumentOptions.fromJson(
          json['document'] as Map<String, dynamic>?),
      image: ImageOptions.fromJson(
          json['image'] as Map<String, dynamic>?),
    );
  }

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'accept': accept,
      'mode': mode,
      'controls': controls,
    };
    if (mode == 'drawer' || mode == 'dropdown') m['direction'] = direction;
    if (mode == 'fixed' && fixedSize != null) m['fixedSize'] = fixedSize!.toJson();
    if (video != null) m['video'] = video!.toJson();
    if (audio != null) m['audio'] = audio!.toJson();
    if (document != null) m['document'] = document!.toJson();
    if (image != null) m['image'] = image!.toJson();
    return m;
  }
}

// ═══════ SpreadsheetOptions ═══════

/// 电子表格模式专用选项。
///
/// 仅当 [ModuleDescriptor.ui] == `"spreadsheet"` 时生效。
class SpreadsheetOptions {
  /// 是否支持公式（=SUM、=VLOOKUP 等）。
  final bool formulas;

  /// 是否支持图表。
  final bool charts;

  /// 是否支持多 sheet。
  final bool sheets;

  /// 是否支持条件格式。
  final bool conditionalFormatting;

  /// 是否列可拖拽调整宽度。
  final bool resizableColumns;

  /// 默认列数。
  final int columns;

  /// 默认行数。
  final int rows;

  const SpreadsheetOptions({
    this.formulas = false,
    this.charts = false,
    this.sheets = false,
    this.conditionalFormatting = false,
    this.resizableColumns = true,
    this.columns = 26,
    this.rows = 100,
  });

  factory SpreadsheetOptions.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const SpreadsheetOptions();
    return SpreadsheetOptions(
      formulas: json['formulas'] as bool? ?? false,
      charts: json['charts'] as bool? ?? false,
      sheets: json['sheets'] as bool? ?? false,
      conditionalFormatting: json['conditionalFormatting'] as bool? ?? false,
      resizableColumns: json['resizableColumns'] as bool? ?? true,
      columns: json['columns'] as int? ?? 26,
      rows: json['rows'] as int? ?? 100,
    );
  }

  Map<String, dynamic> toJson() => {
    'formulas': formulas,
    'charts': charts,
    'sheets': sheets,
    'conditionalFormatting': conditionalFormatting,
    'resizableColumns': resizableColumns,
    'columns': columns,
    'rows': rows,
  };
}

// ═══════ DocEditorOptions ═══════

/// 文档编辑器模式专用选项。
///
/// 仅当 [ModuleDescriptor.ui] == `"document"` 时生效。
class DocEditorOptions {
  /// 修订模式。
  final bool trackChanges;

  /// 批注。
  final bool comments;

  /// 目录。
  final bool tableOfContents;

  /// 脚注/尾注。
  final bool footnotes;

  /// 页眉页脚。
  final bool headersFooters;

  /// 页面设置（边距、方向、分栏）。
  final bool pageSetup;

  /// 可导出格式。
  final List<String> exportFormats;

  const DocEditorOptions({
    this.trackChanges = false,
    this.comments = false,
    this.tableOfContents = false,
    this.footnotes = false,
    this.headersFooters = false,
    this.pageSetup = true,
    this.exportFormats = const ['pdf', 'docx'],
  });

  factory DocEditorOptions.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const DocEditorOptions();
    return DocEditorOptions(
      trackChanges: json['trackChanges'] as bool? ?? false,
      comments: json['comments'] as bool? ?? false,
      tableOfContents: json['tableOfContents'] as bool? ?? false,
      footnotes: json['footnotes'] as bool? ?? false,
      headersFooters: json['headersFooters'] as bool? ?? false,
      pageSetup: json['pageSetup'] as bool? ?? true,
      exportFormats: (json['exportFormats'] as List?)
              ?.map((f) => f.toString())
              .toList() ??
          ['pdf', 'docx'],
    );
  }

  Map<String, dynamic> toJson() => {
    'trackChanges': trackChanges,
    'comments': comments,
    'tableOfContents': tableOfContents,
    'footnotes': footnotes,
    'headersFooters': headersFooters,
    'pageSetup': pageSetup,
    'exportFormats': exportFormats,
  };
}

// ═══════ PresentationOptions ═══════

/// 幻灯片模式专用选项。
///
/// 仅当 [ModuleDescriptor.ui] == `"presentation"` 时生效。
class PresentationOptions {
  /// 切换动画。
  final bool transitions;

  /// 元素动画。
  final bool animations;

  /// 演讲者备注。
  final bool speakerNotes;

  /// 演讲者视图（双屏）。
  final bool presenterView;

  /// 母版编辑。
  final bool slideMaster;

  /// 可用版式。
  final List<String> layouts;

  /// 可导出格式。
  final List<String> exportFormats;

  const PresentationOptions({
    this.transitions = false,
    this.animations = false,
    this.speakerNotes = false,
    this.presenterView = false,
    this.slideMaster = false,
    this.layouts = const ['title', 'content', 'blank', 'two-column'],
    this.exportFormats = const ['pdf', 'pptx'],
  });

  factory PresentationOptions.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const PresentationOptions();
    return PresentationOptions(
      transitions: json['transitions'] as bool? ?? false,
      animations: json['animations'] as bool? ?? false,
      speakerNotes: json['speakerNotes'] as bool? ?? false,
      presenterView: json['presenterView'] as bool? ?? false,
      slideMaster: json['slideMaster'] as bool? ?? false,
      layouts: (json['layouts'] as List?)
              ?.map((l) => l.toString())
              .toList() ??
          ['title', 'content', 'blank', 'two-column'],
      exportFormats: (json['exportFormats'] as List?)
              ?.map((f) => f.toString())
              .toList() ??
          ['pdf', 'pptx'],
    );
  }

  Map<String, dynamic> toJson() => {
    'transitions': transitions,
    'animations': animations,
    'speakerNotes': speakerNotes,
    'presenterView': presenterView,
    'slideMaster': slideMaster,
    'layouts': layouts,
    'exportFormats': exportFormats,
  };
}

// ═══════ ChatOptions ═══════

/// Chat 模式专用选项——声明对话界面的展示风格。
///
/// 仅当 [ModuleDescriptor.ui] == `"chat"` 时生效。
class ChatOptions {
  final ThinkingOptions thinking;
  final ToolCallOptions toolCalls;
  final BubbleOptions bubble;
  final StreamOptions stream;
  final String placeholder;

  /// 是否启用多会话（PLAN_NOW §5 参数16）。
  /// 为 true 时，ChatView 顶部显示会话选择器。
  final bool multiSession;

  const ChatOptions({
    this.thinking = const ThinkingOptions(),
    this.toolCalls = const ToolCallOptions(),
    this.bubble = const BubbleOptions(),
    this.stream = const StreamOptions(),
    this.placeholder = '输入消息...',
    this.multiSession = false,
  });

  factory ChatOptions.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ChatOptions();
    return ChatOptions(
      thinking: ThinkingOptions.fromJson(
          json['thinking'] as Map<String, dynamic>?),
      toolCalls: ToolCallOptions.fromJson(
          json['toolCalls'] as Map<String, dynamic>?),
      bubble: BubbleOptions.fromJson(
          json['bubble'] as Map<String, dynamic>?),
      stream: StreamOptions.fromJson(
          json['stream'] as Map<String, dynamic>?),
      placeholder: json['placeholder'] as String? ?? '输入消息...',
      multiSession: json['multi_session'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'thinking': thinking.toJson(),
    'toolCalls': toolCalls.toJson(),
    'bubble': bubble.toJson(),
    'stream': stream.toJson(),
    'placeholder': placeholder,
    'multi_session': multiSession,
  };
}

// ═══════ FormFieldDescriptor ═══════

/// 表单字段声明。
class FormFieldDescriptor {
  /// 字段标识。
  final String key;

  /// 展示标签。
  final String label;

  /// 字段类型："text" | "textarea" | "select" | "datetime" | "number" | "file" | "checkbox"。
  final String type;

  /// 是否必填。
  final bool required;

  /// select 选项列表。
  final List<String> options;

  /// 占位文本。
  final String placeholder;

  const FormFieldDescriptor({
    required this.key,
    required this.label,
    this.type = 'text',
    this.required = false,
    this.options = const [],
    this.placeholder = '',
  });

  factory FormFieldDescriptor.fromJson(Map<String, dynamic> json) =>
      FormFieldDescriptor(
        key: _require(json, 'key'),
        label: _require(json, 'label'),
        type: json['type'] as String? ?? 'text',
        required: json['required'] as bool? ?? false,
        options: (json['options'] as List?)
                ?.map((o) => o.toString())
                .toList() ??
            [],
        placeholder: json['placeholder'] as String? ?? '',
      );

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'key': key,
      'label': label,
      'type': type,
      'required': required,
    };
    if (options.isNotEmpty) m['options'] = options;
    if (placeholder.isNotEmpty) m['placeholder'] = placeholder;
    return m;
  }
}

// ═══════ FormDescriptor ═══════

/// 结构化表单声明。
class FormDescriptor {
  /// 字段列表。
  final List<FormFieldDescriptor> fields;

  /// 提交按钮文字。
  final String submitLabel;

  /// 失焦时校验。
  final bool validateOnBlur;

  const FormDescriptor({
    this.fields = const [],
    this.submitLabel = '提交',
    this.validateOnBlur = true,
  });

  factory FormDescriptor.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const FormDescriptor();
    return FormDescriptor(
      fields: _requireList(json, 'fields',
          (f) => FormFieldDescriptor.fromJson(f as Map<String, dynamic>)),
      submitLabel: json['submitLabel'] as String? ?? '提交',
      validateOnBlur: json['validateOnBlur'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'fields': fields.map((f) => f.toJson()).toList(),
    'submitLabel': submitLabel,
    'validateOnBlur': validateOnBlur,
  };
}

// ═══════ TimelineDescriptor ═══════

/// 时间线/日历声明。
class TimelineDescriptor {
  /// 模式："calendar" | "timeline" | "agenda"。
  final String mode;

  /// 可用视图：["day", "week", "month"]。
  final List<String> view;

  /// 默认视图。
  final String defaultView;

  /// 点击事件行为："detail" | "edit" | null。
  final String? itemTap;

  /// 是否允许创建事件。
  final bool creatable;

  const TimelineDescriptor({
    this.mode = 'timeline',
    this.view = const ['day', 'week', 'month'],
    this.defaultView = 'week',
    this.itemTap,
    this.creatable = false,
  });

  factory TimelineDescriptor.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const TimelineDescriptor();
    return TimelineDescriptor(
      mode: json['mode'] as String? ?? 'timeline',
      view: (json['view'] as List?)
              ?.map((v) => v.toString())
              .toList() ??
          ['day', 'week', 'month'],
      defaultView: json['defaultView'] as String? ?? 'week',
      itemTap: json['itemTap'] as String?,
      creatable: json['creatable'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'mode': mode,
      'view': view,
      'defaultView': defaultView,
      'creatable': creatable,
    };
    if (itemTap != null) m['itemTap'] = itemTap;
    return m;
  }
}

// ═══════ MapDescriptor ═══════

/// 地图/位置声明。
class MapDescriptor {
  /// 中心纬度。
  final double? centerLat;

  /// 中心经度。
  final double? centerLng;

  /// 默认缩放级别。
  final int zoom;

  /// 是否显示标记点。
  final bool markers;

  /// 是否启用搜索。
  final bool search;

  /// 是否支持路线规划。
  final bool route;

  const MapDescriptor({
    this.centerLat,
    this.centerLng,
    this.zoom = 15,
    this.markers = true,
    this.search = false,
    this.route = false,
  });

  factory MapDescriptor.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const MapDescriptor();
    return MapDescriptor(
      centerLat: (json['center'] as Map<String, dynamic>?)?['lat'] as double?,
      centerLng: (json['center'] as Map<String, dynamic>?)?['lng'] as double?,
      zoom: json['zoom'] as int? ?? 15,
      markers: json['markers'] as bool? ?? true,
      search: json['search'] as bool? ?? false,
      route: json['route'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'zoom': zoom,
      'markers': markers,
      'search': search,
      'route': route,
    };
    if (centerLat != null && centerLng != null) {
      m['center'] = {'lat': centerLat, 'lng': centerLng};
    }
    return m;
  }
}

// ═══════ SidebarDescriptor ═══════

/// 侧边栏配置。
class SidebarDescriptor {
  /// 分类标签，匹配 [SidebarSection.label]。
  final String section;

  /// 分类间排序权重。
  final int sectionOrder;

  /// 分类内排序权重。
  final int order;

  /// 是否显示角标。
  final bool badge;

  const SidebarDescriptor({
    required this.section,
    this.sectionOrder = 50,
    this.order = 50,
    this.badge = false,
  });

  factory SidebarDescriptor.fromJson(Map<String, dynamic> json) =>
      SidebarDescriptor(
        section: _require(json, 'section'),
        sectionOrder: json['sectionOrder'] as int? ?? 50,
        order: json['order'] as int? ?? 50,
        badge: json['badge'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
    'section': section,
    'sectionOrder': sectionOrder,
    'order': order,
    'badge': badge,
  };
}

// ═══════ ComponentConfig ═══════

/// 内容组件配置——在 slot 中声明哪个组件、什么配置、可选后端进程。
///
/// 对应 manifest.json 中 `pages[].slots.<key>` 的值。
class ComponentConfig {
  /// 组件类型名：`"ai-assistant"` | `"form"` | `"code-editor"` | `"data-table"` | ...
  final String component;

  /// 组件专属配置（透传给组件 Widget）。
  final Map<String, dynamic> config;

  /// 栏级后端进程（栏可见时运行，隐藏时停止）。
  final ProcessDescriptor? process;

  const ComponentConfig({
    required this.component,
    this.config = const {},
    this.process,
  });

  factory ComponentConfig.fromJson(Map<String, dynamic> json) =>
      ComponentConfig(
        component: _require(json, 'component'),
        config: (json['config'] as Map<String, dynamic>?) ?? const {},
        process: json['process'] != null
            ? ProcessDescriptor.fromJson(
                json['process'] as Map<String, dynamic>)
            : null,
      );

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{'component': component};
    if (config.isNotEmpty) m['config'] = config;
    if (process != null) m['process'] = process!.toJson();
    return m;
  }
}

// ═══════ PageDescriptor ═══════

/// 页面描述符——模块内多页面声明。
///
/// 对应 manifest.json 中 `pages[]` 的一个元素。
/// 每个页面有自己的 layout、一组 slot、及可选页面级后端进程。
class PageDescriptor {
  /// 页面唯一标识（模块内）。
  final String id;

  /// 页面标题（Tab 标签）。
  final String label;

  /// 页面级布局设置（复用 [LayoutDescriptor]）。
  final LayoutDescriptor layout;

  /// 栏目内容映射。key 为栏位名（`"left"`、`"right"`、`"main"` 等）。
  final Map<String, ComponentConfig> slots;

  /// 页面级后端进程（页面激活时运行，切走时停止）。
  final ProcessDescriptor? globalProcess;

  const PageDescriptor({
    required this.id,
    required this.label,
    this.layout = const LayoutDescriptor(),
    this.slots = const {},
    this.globalProcess,
  });

  factory PageDescriptor.fromJson(Map<String, dynamic> json) =>
      PageDescriptor(
        id: _require(json, 'id'),
        label: _require(json, 'label'),
        layout: LayoutDescriptor.fromJson(
            json['layout'] as Map<String, dynamic>?),
        slots: _parseSlots(json['slots']),
        globalProcess: json['globalProcess'] != null
            ? ProcessDescriptor.fromJson(
                json['globalProcess'] as Map<String, dynamic>)
            : null,
      );

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{'id': id, 'label': label};
    m['layout'] = layout.toJson();
    if (slots.isNotEmpty) {
      m['slots'] = slots.map((k, v) => MapEntry(k, v.toJson()));
    }
    if (globalProcess != null) {
      m['globalProcess'] = globalProcess!.toJson();
    }
    return m;
  }

  /// 本页所有 slot 的 component 类型名列表。
  List<String> get componentTypes =>
      slots.values.map((c) => c.component).toList();
}

/// 解析 `slots` JSON 对象 → `Map<String, ComponentConfig>`。
Map<String, ComponentConfig> _parseSlots(dynamic raw) {
  if (raw == null || raw is! Map<String, dynamic>) return {};
  final result = <String, ComponentConfig>{};
  for (final entry in raw.entries) {
    result[entry.key] = ComponentConfig.fromJson(entry.value);
  }
  return result;
}

// ═══════ ActionButtonDescriptor ═══════

/// 动作按钮描述符——声明带有后端进程的动作按钮。
///
/// 对应 manifest.json 中 `actions[]`（注意：此为新的数组格式，
/// 与旧版单对象 [ActionDescriptor] 在 JSON 层共存，Dart 层分两个字段）。
class ActionButtonDescriptor {
  /// 触发器标识（如 `"button:quick-translate"`）。
  final String trigger;

  /// 按钮标签。
  final String label;

  /// 动作级后端进程（触发时启动，完成即退出）。
  final ProcessDescriptor? process;

  const ActionButtonDescriptor({
    required this.trigger,
    required this.label,
    this.process,
  });

  factory ActionButtonDescriptor.fromJson(Map<String, dynamic> json) =>
      ActionButtonDescriptor(
        trigger: _require(json, 'trigger'),
        label: _require(json, 'label'),
        process: json['process'] != null
            ? ProcessDescriptor.fromJson(
                json['process'] as Map<String, dynamic>)
            : null,
      );

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{'trigger': trigger, 'label': label};
    if (process != null) m['process'] = process!.toJson();
    return m;
  }
}

// ═══════ ModuleDescriptor ═══════

/// 模块描述符——模块声明的唯一数据结构。
///
/// 内置模块用 const 构造；外部插件从 manifest.json 解析。
class ModuleDescriptor {
  final String id;
  final String name;
  final String description;
  final IconData? icon;
  final String? route;
  final SidebarDescriptor? sidebar;
  final List<NavDescriptor> secondaryNavs;
  final LayoutDescriptor layout;
  final List<DataBindingDescriptor> dataBindings;
  /// UI 范式："default" | "chat" | "dashboard" | "editor"。
  final String ui;

  /// Chat 模式专用选项（仅 ui == "chat" 时生效）。
  final ChatOptions? chat;

  /// 电子表格模式专用选项（仅 ui == "spreadsheet" 时生效）。
  final SpreadsheetOptions? spreadsheet;

  /// 文档编辑器模式专用选项（仅 ui == "document" 时生效）。
  final DocEditorOptions? document;

  /// 幻灯片模式专用选项（仅 ui == "presentation" 时生效）。
  final PresentationOptions? presentation;

  /// 键盘交互声明（与 actions 并列）。
  final InputOptions? input;

  /// 文件工作区声明。
  final WorkspaceDescriptor? workspace;

  /// 内嵌文件展示声明。
  final MediaDescriptor? media;

  /// 时间线/日历声明。
  final TimelineDescriptor? timeline;

  /// 地图/位置声明。
  final MapDescriptor? map;

  /// 结构化表单声明。
  final FormDescriptor? form;

  final ActionDescriptor? actions;
  final ProcessDescriptor? process;
  final List<String> dependencies;

  /// 打开模块时自动激活的 Skill 名列表。
  ///
  /// 供 AgentController.activateSkill 消费。每个元素为 Skill 的 `name` 字段。
  /// 例如 `["web_search", "memory"]` 表示进入模块时自动激活这两个 Skill。
  final List<String> activateSkills;

  /// 语义版本号（如 `"1.2.3"`）。
  final String version;

  // ── PLAN_NOW: composite 模式字段 ──

  /// 多页面声明（`ui: "composite"` 时生效）。
  ///
  /// 每个元素为一个 [PageDescriptor]，包含 layout、slots、可选 globalProcess。
  final List<PageDescriptor> pages;

  /// 动作按钮列表（`ui: "composite"` 时生效）。
  ///
  /// 与旧版单对象 [ActionDescriptor] 不同，这是新数组格式，
  /// 每项声明一个动作按钮及其可选后端进程。
  final List<ActionButtonDescriptor> actionButtons;

  const ModuleDescriptor({
    required this.id,
    required this.name,
    this.description = '',
    this.icon,
    this.route,
    this.sidebar,
    this.secondaryNavs = const [],
    this.layout = const LayoutDescriptor(),
    this.dataBindings = const [],
    this.ui = 'default',
    this.chat,
    this.spreadsheet,
    this.document,
    this.presentation,
    this.input,
    this.workspace,
    this.media,
    this.timeline,
    this.map,
    this.form,
    this.actions,
    this.process,
    this.dependencies = const [],
    this.activateSkills = const [],
    this.version = '0.0.0',
    this.pages = const [],
    this.actionButtons = const [],
  });

  // ═══ 便捷查询 ═══

  /// 是否为纯服务模块（无 UI 页面）。
  bool get isServiceOnly => route == null || route!.isEmpty;

  /// 是否出现在侧边栏。
  bool get hasSidebar => sidebar != null && icon != null && !isServiceOnly;

  /// 所有路由路径（主路由 + 子面板路由 + pages 子路由）。
  List<String> get allRoutePaths {
    final paths = <String>[];
    if (route != null && route!.isNotEmpty) {
      paths.add(route!);
      // composite 模式：每个 page 生成主子路由
      if (ui == 'composite') {
        for (final page in pages) {
          paths.add('${route!}/${page.id}');
        }
      }
    }
    for (final p in layout.panels) {
      paths.add(p.path);
    }
    for (final s in secondaryNavs) {
      paths.add(s.routePath);
    }
    return paths;
  }

  // ═══ JSON 序列化 ═══

  factory ModuleDescriptor.fromJson(Map<String, dynamic> json) {
    _requireField(json, 'type', 'module');

    // actions 智能检测：数组 → actionButtons；对象 → 旧 ActionDescriptor
    ActionDescriptor? oldActions;
    List<ActionButtonDescriptor> newActionButtons = [];
    final rawActions = json['actions'];
    if (rawActions is List) {
      newActionButtons = rawActions
          .map((a) =>
              ActionButtonDescriptor.fromJson(a as Map<String, dynamic>))
          .toList();
    } else if (rawActions is Map) {
      oldActions = ActionDescriptor.fromJson(
          rawActions.cast<String, dynamic>());
    }

    return ModuleDescriptor(
      id: _require(json, 'id'),
      name: _require(json, 'name'),
      description: json['description'] as String? ?? '',
      icon: _parseIcon(json['icon']),
      route: json['route'] as String?,
      sidebar: json['sidebar'] != null
          ? SidebarDescriptor.fromJson(json['sidebar'] as Map<String, dynamic>)
          : null,
      secondaryNavs: _requireList(
        json,
        'secondaryNavs',
        (d) => NavDescriptor.fromJson(d as Map<String, dynamic>),
      ),
      layout: LayoutDescriptor.fromJson(json['layout'] as Map<String, dynamic>?),
      dataBindings: _requireList(
        json,
        'data',
        (d) => DataBindingDescriptor.fromJson(d as Map<String, dynamic>),
      ),
      ui: json['ui'] as String? ?? 'default',
      chat: ChatOptions.fromJson(
          json['chat'] as Map<String, dynamic>?),
      spreadsheet: SpreadsheetOptions.fromJson(
          json['spreadsheet'] as Map<String, dynamic>?),
      document: DocEditorOptions.fromJson(
          json['document'] as Map<String, dynamic>?),
      presentation: PresentationOptions.fromJson(
          json['presentation'] as Map<String, dynamic>?),
      input: InputOptions.fromJson(
          json['input'] as Map<String, dynamic>?),
      workspace: WorkspaceDescriptor.fromJson(
          json['workspace'] as Map<String, dynamic>?),
      media: MediaDescriptor.fromJson(
          json['media'] as Map<String, dynamic>?),
      timeline: TimelineDescriptor.fromJson(
          json['timeline'] as Map<String, dynamic>?),
      map: MapDescriptor.fromJson(
          json['map'] as Map<String, dynamic>?),
      form: FormDescriptor.fromJson(
          json['form'] as Map<String, dynamic>?),
      actions: oldActions,
      actionButtons: newActionButtons,
      process: json['process'] != null
          ? ProcessDescriptor.fromJson(json['process'] as Map<String, dynamic>)
          : null,
      dependencies: (json['dependencies'] as List?)
              ?.map((d) => d.toString())
              .toList() ??
          [],
      activateSkills: (json['activateSkills'] as List?)
              ?.map((s) => s.toString())
              .toList() ??
          [],
      version: json['version'] as String? ?? '0.0.0',
      pages: _requireList(
        json,
        'pages',
        (p) => PageDescriptor.fromJson(p as Map<String, dynamic>),
      ),
    );
  }

  factory ModuleDescriptor.fromJsonString(String str) =>
      ModuleDescriptor.fromJson(jsonDecode(str) as Map<String, dynamic>);

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'type': 'module',
      'id': id,
      'name': name,
    };
    if (description.isNotEmpty) m['description'] = description;
    if (icon != null) m['icon'] = _iconToJson(icon);
    if (route != null) m['route'] = route;
    if (sidebar != null) m['sidebar'] = sidebar!.toJson();
    if (secondaryNavs.isNotEmpty) {
      m['secondaryNavs'] = secondaryNavs.map((n) => n.toJson()).toList();
    }
    m['ui'] = ui;
    if (chat != null) m['chat'] = chat!.toJson();
    if (spreadsheet != null) m['spreadsheet'] = spreadsheet!.toJson();
    if (document != null) m['document'] = document!.toJson();
    if (presentation != null) m['presentation'] = presentation!.toJson();
    if (input != null) m['input'] = input!.toJson();
    if (workspace != null) m['workspace'] = workspace!.toJson();
    if (media != null) m['media'] = media!.toJson();
    if (timeline != null) m['timeline'] = timeline!.toJson();
    if (map != null) m['map'] = map!.toJson();
    if (form != null) m['form'] = form!.toJson();
    m['layout'] = layout.toJson();
    if (dataBindings.isNotEmpty) {
      m['data'] = dataBindings.map((d) => d.toJson()).toList();
    }
    if (actions != null) m['actions'] = actions!.toJson();
    if (process != null) m['process'] = process!.toJson();
    if (dependencies.isNotEmpty) m['dependencies'] = dependencies;
    if (activateSkills.isNotEmpty) m['activateSkills'] = activateSkills;
    if (version != '0.0.0') m['version'] = version;
    if (pages.isNotEmpty) {
      m['pages'] = pages.map((p) => p.toJson()).toList();
    }
    if (actionButtons.isNotEmpty) {
      m['actions'] = actionButtons.map((a) => a.toJson()).toList();
    }
    return m;
  }

  @override
  bool operator ==(Object other) =>
      other is ModuleDescriptor && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'ModuleDescriptor($id, $name)';
}
