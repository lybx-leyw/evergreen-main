/// Manifest V2 模块描述符——树形架构：模块→页面→布局→插槽→组件。
///
/// # [ModuleDescriptor] —— 模块声明（V2）
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
/// | `StyleDescriptor` | 样式超参数（width/height/padding/margin/color/flex...） |
/// | `EventDescriptor` | 事件声明（emit + listen + delegates） |
/// | `DataBindingDescriptor` | 数据绑定声明 |
/// | `DataSourceDescriptor` | 数据源声明（页面/组件级） |
/// | `ProcessDescriptor` | 后端进程配置（V2: id/scope/autoStart/autoRestart） |
/// | `NavDescriptor` | 子导航条目声明 |
/// | `SidebarDescriptor` | 侧边栏配置 |
/// | `NavObjectDescriptor` | 导航聚合（sidebar + secondary） |
/// | `LayoutDescriptor` | 布局（type/preset/features/style/slots） |
/// | `LayoutPreset` | 布局预设超参数 |
/// | `LayoutFeatures` | 布局特性（zoom/search/drawers） |
/// | `SlotDescriptor` | 插槽（style/process/events/component） |
/// | `ComponentDescriptor` | 组件声明（type/config/input/events/process/dataSource） |
/// | `PageDescriptor` | 页面描述符 |
/// | `ActionDescriptor` | 交互规则声明 |
/// | `ActionButtonDescriptor` | 动作按钮声明 |
/// | `RefreshDescriptor` | 刷新配置 |
/// | `DeletableDescriptor` | 删除行为配置 |
/// | `ZoomDescriptor` | 缩放配置 |
/// | `SearchDescriptor` | 搜索栏配置 |
/// | `PanelDescriptor` | 多 tab 面板声明 |
/// | `WorkspaceDescriptor` | 文件工作区声明 |
/// | `MediaDescriptor` | 内嵌文件展示声明 |
/// | `TimelineDescriptor` | 时间线/日历声明 |
/// | `MapDescriptor` | 地图/位置声明 |
/// | `FormDescriptor` | 结构化表单声明 |
/// | `FormFieldDescriptor` | 表单字段 |
/// | `ChatOptions` | Chat 模式选项 |
/// | `ThinkingOptions` | 思考栏展示选项 |
/// | `ToolCallOptions` | 工具调用提示选项 |
/// | `BubbleOptions` | 气泡样式选项 |
/// | `StreamOptions` | 流式输出选项 |
/// | `InputOptions` | 键盘交互声明 |
/// | `AttachmentOptions` | 附件上传选项 |
/// | `FeedbackOptions` | 输入反馈配置 |
/// | `FeedbackStateOptions` | 单次反馈状态 |
/// | `SpreadsheetOptions` | 电子表格模式选项 |
/// | `DocEditorOptions` | 文档编辑器选项 |
/// | `PresentationOptions` | 幻灯片模式选项 |
/// | `VideoOptions` | 视频选项 |
/// | `AudioOptions` | 音频选项 |
/// | `DocumentOptions` | 文档选项 |
/// | `ImageOptions` | 图片选项 |
/// | `FixedSizeOptions` | fixed 模式尺寸 |
/// | `ExposeStateConfig` | 栏状态暴露声明 |
library;

import 'dart:convert';

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

/// 从 JSON 解析图标：int（codePoint）或 String（名称映射或 hex）。
/// 安全解析布尔标记：支持 `true`/`false` 或对象（有内容=enabled）。
bool _parseFlag(dynamic raw) {
  if (raw == null) return false;
  if (raw is bool) return raw;
  if (raw is Map) return raw.isNotEmpty;
  if (raw is List) return raw.isNotEmpty;
  return false;
}

int? _parseIcon(dynamic raw) {
  if (raw == null) return null;
  if (raw is int) return raw;
  if (raw is String) {
    final mapped = _iconMap[raw];
    if (mapped != null) return mapped;
    final i = int.tryParse(raw);
    if (i != null) return i;
    return null;
  }
  return null;
}

int? _iconToJson(int? codePoint) => codePoint;

const _iconMap = <String, int>{
  'extension': 0xe24b, // Icons.extension
  'home': 0xe88a,
  'settings': 0xe8b8,
  'person': 0xe7fd,
  'school': 0xe80c,
  'auto_awesome': 0xe65f,
  'code': 0xe86f,
  'star': 0xe838,
  'bookmark': 0xe8e7,
  'build': 0xe869,
  'dashboard': 0xe871,
  'analytics': 0xef3e,
  'chat': 0xe0b7,
  'email': 0xe0be,
  'notifications': 0xe7f4,
  'language': 0xe894,
  'search': 0xe8b6,
  'favorite': 0xe87d,
  'timeline': 0xe922,
  'date_range': 0xe916,
  'folder': 0xe2c7,
  'insert_drive_file': 0xe24d,
  'cloud': 0xe2bd,
  'lock': 0xe897,
  'account_circle': 0xe853,
  'admin_panel_settings': 0xef3d,
  'apps': 0xe40b,
  'article': 0xef42,
  'assessment': 0xf0a5,
  'attach_money': 0xe227,
  'bar_chart': 0xe26b,
  'business': 0xe0af,
  'calendar_month': 0xebcc,
  'checklist': 0xe6b1,
  'contact_support': 0xe94c,
  'credit_card': 0xe870,
  'dark_mode': 0xe51c,
  'delete': 0xe872,
  'description': 0xe873,
  'done': 0xe876,
  'download': 0xf090,
  'edit': 0xe3c9,
  'engineering': 0xea4d,
  'event': 0xe878,
  'explore': 0xe87a,
  'face': 0xe87c,
  'filter_alt': 0xef4f,
  'gavel': 0xe90e,
  'group': 0xe7ef,
  'handshake': 0xebcb,
  'help': 0xe887,
  'history': 0xe889,
  'info': 0xe88e,
  'inventory': 0xe179,
  'lightbulb': 0xe0f0,
  'list_alt': 0xe0ee,
  'local_library': 0xe54b,
  'map': 0xe55b,
  'mediation': 0xefa7,
  'menu_book': 0xea19,
  'model_training': 0xf0cf,
  'more_horiz': 0xe5d3,
  'music_note': 0xe405,
  'new_releases': 0xe031,
  'open_in_new': 0xe89e,
  'paid': 0xf0a7,
  'palette': 0xe40a,
  'people': 0xe7fb,
  'percent': 0xeb58,
  'pie_chart': 0xec2a,
  'playlist_add': 0xe03b,
  'precision_manufacturing': 0xf049,
  'preview': 0xf1c5,
  'psychology': 0xea4a,
  'public': 0xe80b,
  'publish': 0xe255,
  'push_pin': 0xf10d,
  'quiz': 0xf04e,
  'receipt': 0xe8b0,
  'rocket': 0xeba5,
  'rule': 0xf1c2,
  'schedule': 0xe8b5,
  'science': 0xea4e,
  'score': 0xe269,
  'security': 0xe32a,
  'self_improvement': 0xea78,
  'shopping_cart': 0xe8cc,
  'smart_toy': 0xf06c,
  'spa': 0xe4b4,
  'speed': 0xe9e4,
  'storage': 0xe1db,
  'store': 0xe8d1,
  'stream': 0xe9e6,
  'support': 0xef73,
  'switch_account': 0xe9ed,
  'task': 0xf075,
  'thermostat': 0xf076,
  'thumb_up': 0xe8dc,
  'tour': 0xef75,
  'toys': 0xf332,
  'translate': 0xe8e2,
  'trending_up': 0xe8e5,
  'tune': 0xe429,
  'update': 0xe923,
  'upgrade': 0xf0fb,
  'verified': 0xef76,
  'videocam': 0xe04b,
  'view_kanban': 0xeb7f,
  'visibility': 0xe8f4,
  'volume_up': 0xe050,
  'wallet': 0xe8ff,
  'warning': 0xe002,
  'workspace_premium': 0xe7af,
};

// ═══════ StyleDescriptor ═══════

/// 样式超参数——每层均可声明，用 JSON 预设超参数（非 CSS 字符串）。
///
/// 支持的预设超参数：
/// - 尺寸: width, height, minWidth, maxWidth, minHeight, maxHeight
/// - 间距: padding, paddingTop/Bottom/Left/Right, margin, marginTop/Bottom/Left/Right
/// - 外观: background, borderRadius, border, shadow, opacity
/// - 弹性: flex, flexDirection, justifyContent, alignItems, alignSelf, gap, wrap
/// - 网格定位: gridColumn, gridRow
/// - 定位: position, top, right, bottom, left, zIndex
/// - 文字: color, fontSize, fontWeight, textAlign
/// - 溢出: overflow
class StyleDescriptor {
  final dynamic width;
  final dynamic height;
  final dynamic minWidth;
  final dynamic maxWidth;
  final dynamic minHeight;
  final dynamic maxHeight;

  final double? padding;
  final double? paddingTop;
  final double? paddingRight;
  final double? paddingBottom;
  final double? paddingLeft;
  final double? margin;
  final double? marginTop;
  final double? marginRight;
  final double? marginBottom;
  final double? marginLeft;

  final String? background;
  final double? borderRadius;
  final String? border;
  final String? shadow;
  final double? opacity;

  final int? flex;
  final String? flexDirection;
  final String? justifyContent;
  final String? alignItems;
  final String? alignSelf;
  final double? gap;
  final bool? wrap;

  final String? gridColumn;
  final String? gridRow;

  final String? position;
  final double? top;
  final double? right;
  final double? bottom;
  final double? left;
  final int? zIndex;

  final String? color;
  final double? fontSize;
  final String? fontWeight;
  final String? textAlign;

  final String? overflow;

  const StyleDescriptor({
    this.width,
    this.height,
    this.minWidth,
    this.maxWidth,
    this.minHeight,
    this.maxHeight,
    this.padding,
    this.paddingTop,
    this.paddingRight,
    this.paddingBottom,
    this.paddingLeft,
    this.margin,
    this.marginTop,
    this.marginRight,
    this.marginBottom,
    this.marginLeft,
    this.background,
    this.borderRadius,
    this.border,
    this.shadow,
    this.opacity,
    this.flex,
    this.flexDirection,
    this.justifyContent,
    this.alignItems,
    this.alignSelf,
    this.gap,
    this.wrap,
    this.gridColumn,
    this.gridRow,
    this.position,
    this.top,
    this.right,
    this.bottom,
    this.left,
    this.zIndex,
    this.color,
    this.fontSize,
    this.fontWeight,
    this.textAlign,
    this.overflow,
  });

  factory StyleDescriptor.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const StyleDescriptor();
    return StyleDescriptor(
      width: json['width'],
      height: json['height'],
      minWidth: json['minWidth'],
      maxWidth: json['maxWidth'],
      minHeight: json['minHeight'],
      maxHeight: json['maxHeight'],
      padding: (json['padding'] as num?)?.toDouble(),
      paddingTop: (json['paddingTop'] as num?)?.toDouble(),
      paddingRight: (json['paddingRight'] as num?)?.toDouble(),
      paddingBottom: (json['paddingBottom'] as num?)?.toDouble(),
      paddingLeft: (json['paddingLeft'] as num?)?.toDouble(),
      margin: (json['margin'] as num?)?.toDouble(),
      marginTop: (json['marginTop'] as num?)?.toDouble(),
      marginRight: (json['marginRight'] as num?)?.toDouble(),
      marginBottom: (json['marginBottom'] as num?)?.toDouble(),
      marginLeft: (json['marginLeft'] as num?)?.toDouble(),
      background: json['background'] as String?,
      borderRadius: (json['borderRadius'] as num?)?.toDouble(),
      border: json['border'] as String?,
      shadow: json['shadow'] as String?,
      opacity: (json['opacity'] as num?)?.toDouble(),
      flex: json['flex'] as int?,
      flexDirection: json['flexDirection'] as String?,
      justifyContent: json['justifyContent'] as String?,
      alignItems: json['alignItems'] as String?,
      alignSelf: json['alignSelf'] as String?,
      gap: (json['gap'] as num?)?.toDouble(),
      wrap: json['wrap'] as bool?,
      gridColumn: json['gridColumn'] as String?,
      gridRow: json['gridRow'] as String?,
      position: json['position'] as String?,
      top: (json['top'] as num?)?.toDouble(),
      right: (json['right'] as num?)?.toDouble(),
      bottom: (json['bottom'] as num?)?.toDouble(),
      left: (json['left'] as num?)?.toDouble(),
      zIndex: json['zIndex'] as int?,
      color: json['color'] as String?,
      fontSize: (json['fontSize'] as num?)?.toDouble(),
      fontWeight: json['fontWeight'] as String?,
      textAlign: json['textAlign'] as String?,
      overflow: json['overflow'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{};
    _putIf(m, 'width', width);
    _putIf(m, 'height', height);
    _putIf(m, 'minWidth', minWidth);
    _putIf(m, 'maxWidth', maxWidth);
    _putIf(m, 'minHeight', minHeight);
    _putIf(m, 'maxHeight', maxHeight);
    _putIf(m, 'padding', padding);
    _putIf(m, 'paddingTop', paddingTop);
    _putIf(m, 'paddingRight', paddingRight);
    _putIf(m, 'paddingBottom', paddingBottom);
    _putIf(m, 'paddingLeft', paddingLeft);
    _putIf(m, 'margin', margin);
    _putIf(m, 'marginTop', marginTop);
    _putIf(m, 'marginRight', marginRight);
    _putIf(m, 'marginBottom', marginBottom);
    _putIf(m, 'marginLeft', marginLeft);
    _putIf(m, 'background', background);
    _putIf(m, 'borderRadius', borderRadius);
    _putIf(m, 'border', border);
    _putIf(m, 'shadow', shadow);
    _putIf(m, 'opacity', opacity);
    _putIf(m, 'flex', flex);
    _putIf(m, 'flexDirection', flexDirection);
    _putIf(m, 'justifyContent', justifyContent);
    _putIf(m, 'alignItems', alignItems);
    _putIf(m, 'alignSelf', alignSelf);
    _putIf(m, 'gap', gap);
    _putIf(m, 'wrap', wrap);
    _putIf(m, 'gridColumn', gridColumn);
    _putIf(m, 'gridRow', gridRow);
    _putIf(m, 'position', position);
    _putIf(m, 'top', top);
    _putIf(m, 'right', right);
    _putIf(m, 'bottom', bottom);
    _putIf(m, 'left', left);
    _putIf(m, 'zIndex', zIndex);
    _putIf(m, 'color', color);
    _putIf(m, 'fontSize', fontSize);
    _putIf(m, 'fontWeight', fontWeight);
    _putIf(m, 'textAlign', textAlign);
    _putIf(m, 'overflow', overflow);
    return m;
  }

  /// 是否有任何非空字段。
  bool get isEmpty {
    return width == null && height == null && minWidth == null &&
        maxWidth == null && minHeight == null && maxHeight == null &&
        padding == null && paddingTop == null && paddingRight == null &&
        paddingBottom == null && paddingLeft == null &&
        margin == null && marginTop == null && marginRight == null &&
        marginBottom == null && marginLeft == null &&
        background == null && borderRadius == null && border == null &&
        shadow == null && opacity == null &&
        flex == null && flexDirection == null && justifyContent == null &&
        alignItems == null && alignSelf == null && gap == null &&
        wrap == null && gridColumn == null && gridRow == null &&
        position == null && top == null && right == null &&
        bottom == null && left == null && zIndex == null &&
        color == null && fontSize == null && fontWeight == null &&
        textAlign == null && overflow == null;
  }
}

void _putIf(Map<String, dynamic> m, String key, Object? value) {
  if (value != null) m[key] = value;
}

// ═══════ EventDescriptor ═══════

/// 事件声明——每层均可声明 emit + listen + delegates。
///
/// - emit: 组件发出的事件
/// - listen: 监听的事件（支持 source/filter/handler）
/// - delegates: 委托事件（slot/page/module 层有效）
class EventDescriptor {
  /// 发出的事件列表。
  final List<EventEmitDescriptor> emit;

  /// 监听的事件列表。
  final List<EventListenDescriptor> listen;

  /// 委托事件（仅 slot/page/module 层有效）。
  final EventDelegatesDescriptor? delegates;

  const EventDescriptor({
    this.emit = const [],
    this.listen = const [],
    this.delegates,
  });

  factory EventDescriptor.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const EventDescriptor();
    return EventDescriptor(
      emit: _parseEmit(json['emit']),
      listen: _parseListen(json['listen']),
      delegates: EventDelegatesDescriptor.fromJson(
          json['delegates'] as Map<String, dynamic>?),
    );
  }

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{};
    if (emit.isNotEmpty) m['emit'] = emit.map((e) => e.toJson()).toList();
    if (listen.isNotEmpty) m['listen'] = listen.map((e) => e.toJson()).toList();
    if (delegates != null) m['delegates'] = delegates!.toJson();
    return m;
  }
}

List<EventEmitDescriptor> _parseEmit(dynamic raw) {
  if (raw == null || raw is! List) return [];
  return raw
      .map((e) => EventEmitDescriptor.fromJson(e as Map<String, dynamic>?))
      .toList();
}

List<EventListenDescriptor> _parseListen(dynamic raw) {
  if (raw == null || raw is! List) return [];
  return raw
      .map((e) => EventListenDescriptor.fromJson(e as Map<String, dynamic>?))
      .toList();
}

/// 单个 emit 事件声明。
class EventEmitDescriptor {
  final String name;
  final Map<String, String>? payload;

  const EventEmitDescriptor({required this.name, this.payload});

  factory EventEmitDescriptor.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const EventEmitDescriptor(name: '');
    final rawPayload = json['payload'];
    Map<String, String>? payload;
    if (rawPayload is Map) {
      payload = rawPayload.map((k, v) => MapEntry(k.toString(), v.toString()));
    }
    return EventEmitDescriptor(
      name: json['name'] as String? ?? '',
      payload: payload,
    );
  }

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{'name': name};
    if (payload != null) m['payload'] = payload;
    return m;
  }
}

/// 单个 listen 事件声明。
class EventListenDescriptor {
  final String event;
  final String? source;
  final Map<String, dynamic>? filter;
  final String? handler;

  const EventListenDescriptor({
    required this.event,
    this.source,
    this.filter,
    this.handler,
  });

  factory EventListenDescriptor.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const EventListenDescriptor(event: '');
    return EventListenDescriptor(
      event: json['event'] as String? ?? '',
      source: json['source'] as String?,
      filter: json['filter'] as Map<String, dynamic>?,
      handler: json['handler'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{'event': event};
    if (source != null) m['source'] = source;
    if (filter != null) m['filter'] = filter;
    if (handler != null) m['handler'] = handler;
    return m;
  }
}

/// 委托事件（slot/page/module 层）。
class EventDelegatesDescriptor {
  final String? onClick;
  final String? onKeyPress;
  final String? onHover;
  final bool propagate;

  const EventDelegatesDescriptor({
    this.onClick,
    this.onKeyPress,
    this.onHover,
    this.propagate = true,
  });

  factory EventDelegatesDescriptor.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const EventDelegatesDescriptor();
    return EventDelegatesDescriptor(
      onClick: json['onClick'] as String?,
      onKeyPress: json['onKeyPress'] as String?,
      onHover: json['onHover'] as String?,
      propagate: json['propagate'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{};
    if (onClick != null) m['onClick'] = onClick;
    if (onKeyPress != null) m['onKeyPress'] = onKeyPress;
    if (onHover != null) m['onHover'] = onHover;
    m['propagate'] = propagate;
    return m;
  }
}

// ═══════ DataSourceDescriptor ═══════

/// 数据源声明——页面级或组件级均可声明。
class DataSourceDescriptor {
  /// 数据端点 URL。
  final String? endpoint;

  /// HTTP 方法。
  final String method;

  /// 数据路径（JSONPath）。
  final String? dataPath;

  /// 数据转换函数名。
  final String? transform;

  /// 自动刷新间隔（秒），0 = 不自动刷新。
  final int refreshInterval;

  const DataSourceDescriptor({
    this.endpoint,
    this.method = 'GET',
    this.dataPath,
    this.transform,
    this.refreshInterval = 0,
  });

  factory DataSourceDescriptor.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const DataSourceDescriptor();
    return DataSourceDescriptor(
      endpoint: json['endpoint'] as String?,
      method: json['method'] as String? ?? 'GET',
      dataPath: json['dataPath'] as String?,
      transform: json['transform'] as String?,
      refreshInterval: json['refreshInterval'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{};
    if (endpoint != null) m['endpoint'] = endpoint;
    if (method != 'GET') m['method'] = method;
    if (dataPath != null) m['dataPath'] = dataPath;
    if (transform != null) m['transform'] = transform;
    if (refreshInterval != 0) m['refreshInterval'] = refreshInterval;
    return m;
  }
}

// ═══════ ProcessDescriptor ═══════

/// 后端进程配置（.exe 插件）——V2 升级。
class ProcessDescriptor {
  /// 进程唯一标识（V2 新增）。
  final String? id;

  /// .exe 路径。
  final String exe;

  /// 通信协议："http" | "stdio"。
  final String protocol;

  /// 进程作用域："long"（长期运行）| "short"（一次性任务）。
  final String scope;

  /// 是否自动启动。
  final bool autoStart;

  /// 崩溃后是否自动重启（仅 long 作用域）。
  final bool autoRestart;

  /// 优先端口（http 协议），0 = 自动分配。
  final int preferredPort;

  const ProcessDescriptor({
    this.id,
    required this.exe,
    this.protocol = 'http',
    this.scope = 'long',
    this.autoStart = true,
    this.autoRestart = false,
    this.preferredPort = 0,
  });

  factory ProcessDescriptor.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const ProcessDescriptor(exe: '');
    }
    return ProcessDescriptor(
      id: json['id'] as String?,
      exe: json['exe'] as String? ?? '',
      protocol: json['protocol'] as String? ?? 'http',
      scope: json['scope'] as String? ?? 'long',
      autoStart: json['autoStart'] as bool? ?? true,
      autoRestart: json['autoRestart'] as bool? ?? false,
      preferredPort: json['preferredPort'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'exe': exe,
      'protocol': protocol,
    };
    if (id != null) m['id'] = id;
    if (scope != 'long') m['scope'] = scope;
    if (!autoStart) m['autoStart'] = autoStart;
    if (autoRestart) m['autoRestart'] = autoRestart;
    if (preferredPort != 0) m['preferredPort'] = preferredPort;
    return m;
  }
}

// ═══════ DataBindingDescriptor ═══════

class DataBindingDescriptor {
  final String dataType;
  final String display;
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

class RefreshDescriptor {
  final bool enabled;
  final bool pullToRefresh;
  final int autoInterval;

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

class DeletableDescriptor {
  final bool enabled;
  final Object confirm;

  bool get confirmEnabled {
    final c = confirm;
    if (c is bool) return c;
    if (c is String) return c.isNotEmpty;
    return true;
  }

  String? get confirmMessage {
    final c = confirm;
    if (c is String && c.isNotEmpty) return c;
    return null;
  }

  const DeletableDescriptor({
    this.enabled = false,
    this.confirm = true,
  });

  factory DeletableDescriptor.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const DeletableDescriptor();
    final rawConfirm = json['confirm'];
    final Object confirm;
    if (rawConfirm is bool) {
      confirm = rawConfirm;
    } else if (rawConfirm is String) {
      confirm = rawConfirm;
    } else {
      confirm = true;
    }
    return DeletableDescriptor(
      enabled: json['enabled'] as bool? ?? false,
      confirm: confirm,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'confirm': confirm,
  };
}

// ═══════ ActionDescriptor ═══════

class ActionDescriptor {
  final String? itemTap;
  final String? itemLongPress;
  final String? itemSwipe;
  final String selection;
  final RefreshDescriptor? refresh;
  final List<String> sortable;
  final bool creatable;
  final bool editable;
  final DeletableDescriptor? deletable;
  final List<String> exportable;

  /// V2: 动作按钮列表。
  final List<ActionButtonDescriptor> actionButtons;

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
    this.actionButtons = const [],
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
      actionButtons: _parseActionButtons(json['actionButtons']),
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
    if (actionButtons.isNotEmpty) {
      m['actionButtons'] = actionButtons.map((a) => a.toJson()).toList();
    }
    return m;
  }
}

List<ActionButtonDescriptor> _parseActionButtons(dynamic raw) {
  if (raw == null || raw is! List) return [];
  return raw
      .map((a) => ActionButtonDescriptor.fromJson(a as Map<String, dynamic>))
      .toList();
}

// ═══════ ActionButtonDescriptor ═══════

class ActionButtonDescriptor {
  /// V2: 按钮唯一标识。
  final String? id;

  /// 触发器标识（如 "button:quick-translate"）。
  final String trigger;

  /// 按钮标签。
  final String label;

  /// 按钮图标（codePoint）。
  final int? icon;

  /// 动作级后端进程。
  final ProcessDescriptor? process;

  const ActionButtonDescriptor({
    this.id,
    required this.trigger,
    required this.label,
    this.icon,
    this.process,
  });

  factory ActionButtonDescriptor.fromJson(Map<String, dynamic> json) =>
      ActionButtonDescriptor(
        id: json['id'] as String?,
        trigger: _require(json, 'trigger'),
        label: _require(json, 'label'),
        icon: _parseIcon(json['icon']),
        process: json['process'] != null
            ? ProcessDescriptor.fromJson(
                json['process'] as Map<String, dynamic>)
            : null,
      );

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{'trigger': trigger, 'label': label};
    if (id != null) m['id'] = id;
    if (icon != null) m['icon'] = _iconToJson(icon);
    if (process != null) m['process'] = process!.toJson();
    return m;
  }
}

// ═══════ ZoomDescriptor ═══════

class ZoomDescriptor {
  final bool enabled;
  final double min;
  final double max;

  const ZoomDescriptor({
    this.enabled = false,
    this.min = 0.5,
    this.max = 2.0,
  });

  factory ZoomDescriptor.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ZoomDescriptor();
    return ZoomDescriptor(
      enabled: json['enabled'] as bool? ?? false,
      min: (json['min'] as num?)?.toDouble() ?? 0.5,
      max: (json['max'] as num?)?.toDouble() ?? 2.0,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'min': min,
    'max': max,
  };
}

// ═══════ SearchDescriptor ═══════

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

// ═══════ LayoutPreset ═══════

/// 布局预设超参数——由 layout.type 决定结构。
class LayoutPreset {
  /// grid 布局：列数。
  final int? columns;

  /// grid 布局：行数。
  final String? rows;

  /// flex 布局：方向。
  final String? direction;

  /// flex 布局：是否换行。
  final bool? wrap;

  /// 通用：间距。
  final double? gap;

  /// flex 布局：主轴对齐。
  final String? justify;

  /// flex 布局：交叉轴对齐。
  final String? align;

  /// dock 布局：各区域配置。
  final Map<String, dynamic>? regions;

  const LayoutPreset({
    this.columns,
    this.rows,
    this.direction,
    this.wrap,
    this.gap,
    this.justify,
    this.align,
    this.regions,
  });

  factory LayoutPreset.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const LayoutPreset();
    return LayoutPreset(
      columns: json['columns'] as int?,
      rows: json['rows'] as String?,
      direction: json['direction'] as String?,
      wrap: json['wrap'] as bool?,
      gap: (json['gap'] as num?)?.toDouble(),
      justify: json['justify'] as String?,
      align: json['align'] as String?,
      regions: json['top'] != null || json['bottom'] != null ||
              json['left'] != null || json['right'] != null || json['fill'] != null
          ? json
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{};
    if (columns != null) m['columns'] = columns;
    if (rows != null) m['rows'] = rows;
    if (direction != null) m['direction'] = direction;
    if (wrap != null) m['wrap'] = wrap;
    if (gap != null) m['gap'] = gap;
    if (justify != null) m['justify'] = justify;
    if (align != null) m['align'] = align;
    if (regions != null) m.addAll(regions!);
    return m;
  }
}

// ═══════ LayoutFeatures ═══════

/// 布局特性——zoom / search / drawers。
class LayoutFeatures {
  final ZoomDescriptor? zoom;
  final SearchDescriptor? search;
  final List<String> drawers;

  const LayoutFeatures({
    this.zoom,
    this.search,
    this.drawers = const [],
  });

  factory LayoutFeatures.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const LayoutFeatures();
    return LayoutFeatures(
      zoom: ZoomDescriptor.fromJson(
          json['zoom'] as Map<String, dynamic>?),
      search: SearchDescriptor.fromJson(
          json['search'] as Map<String, dynamic>?),
      drawers: (json['drawers'] as List?)
              ?.map((d) => d.toString())
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{};
    if (zoom != null) m['zoom'] = zoom!.toJson();
    if (search != null) m['search'] = search!.toJson();
    if (drawers.isNotEmpty) m['drawers'] = drawers;
    return m;
  }
}

// ═══════ LayoutDescriptor (V2) ═══════

/// 布局描述符（V2）——type / preset / features / style / slots。
class LayoutDescriptor {
  /// 布局范式："grid" | "flex" | "fullscreen" | "absolute" | "dock"。
  final String type;

  /// 布局预设超参数。
  final LayoutPreset preset;

  /// 布局特性（zoom/search/drawers）。
  final LayoutFeatures features;

  /// 布局级样式。
  final StyleDescriptor style;

  /// 布局级事件。
  final EventDescriptor events;

  /// 插槽映射：slotName → SlotDescriptor。
  final Map<String, SlotDescriptor> slots;

  const LayoutDescriptor({
    this.type = 'grid',
    this.preset = const LayoutPreset(),
    this.features = const LayoutFeatures(),
    this.style = const StyleDescriptor(),
    this.events = const EventDescriptor(),
    this.slots = const {},
  });

  factory LayoutDescriptor.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const LayoutDescriptor();
    return LayoutDescriptor(
      type: json['type'] as String? ?? 'grid',
      preset: LayoutPreset.fromJson(
          json['preset'] as Map<String, dynamic>?),
      features: LayoutFeatures.fromJson(
          json['features'] as Map<String, dynamic>?),
      style: StyleDescriptor.fromJson(
          json['style'] as Map<String, dynamic>?),
      events: EventDescriptor.fromJson(
          json['events'] as Map<String, dynamic>?),
      slots: _parseSlots(json['slots']),
    );
  }

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'type': type,
    };
    m['preset'] = preset.toJson();
    final f = features.toJson();
    if (f.isNotEmpty) m['features'] = f;
    final s = style.toJson();
    if (s.isNotEmpty) m['style'] = s;
    final e = events.toJson();
    if (e.isNotEmpty) m['events'] = e;
    if (slots.isNotEmpty) {
      m['slots'] = slots.map((k, v) => MapEntry(k, v.toJson()));
    }
    return m;
  }
}

// ═══════ SlotDescriptor ═══════

/// 插槽描述符（V2）——style / process / events / component。
///
/// Slot 不能嵌套 Slot，只能包含 Component。
class SlotDescriptor {
  /// 插槽级样式。
  final StyleDescriptor style;

  /// 插槽级进程列表。
  final List<ProcessDescriptor> process;

  /// 插槽级事件（delegates）。
  final EventDescriptor events;

  /// 组件声明。
  final ComponentDescriptor? component;

  const SlotDescriptor({
    this.style = const StyleDescriptor(),
    this.process = const [],
    this.events = const EventDescriptor(),
    this.component,
  });

  factory SlotDescriptor.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const SlotDescriptor();
    return SlotDescriptor(
      style: StyleDescriptor.fromJson(
          json['style'] as Map<String, dynamic>?),
      process: _parseProcessList(json['process']),
      events: EventDescriptor.fromJson(
          json['events'] as Map<String, dynamic>?),
      component: json['component'] != null
          ? ComponentDescriptor.fromJson(
              json['component'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{};
    final s = style.toJson();
    if (s.isNotEmpty) m['style'] = s;
    if (process.isNotEmpty) {
      m['process'] = process.map((p) => p.toJson()).toList();
    }
    final e = events.toJson();
    if (e.isNotEmpty) m['events'] = e;
    if (component != null) m['component'] = component!.toJson();
    return m;
  }
}

// ═══════ ComponentDescriptor ═══════

/// 组件描述符（V2）——type / config / input / events / process / dataSource。
class ComponentDescriptor {
  /// 组件类型名："chat" | "code-editor" | "data-table" | "chart" | ...
  final String type;

  /// 组件配置（透传给组件 Widget）。
  final Map<String, dynamic> config;

  /// 输入配置。
  final InputOptions? input;

  /// 组件事件（emit + listen）。
  final EventDescriptor events;

  /// 组件进程列表。
  final List<ProcessDescriptor> process;

  /// 组件数据源。
  final DataSourceDescriptor? dataSource;

  const ComponentDescriptor({
    required this.type,
    this.config = const {},
    this.input,
    this.events = const EventDescriptor(),
    this.process = const [],
    this.dataSource,
  });

  factory ComponentDescriptor.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ComponentDescriptor(type: 'unknown');
    return ComponentDescriptor(
      type: json['type'] as String? ?? 'unknown',
      config: (json['config'] as Map<String, dynamic>?) ?? const {},
      input: InputOptions.fromJson(
          json['input'] as Map<String, dynamic>?),
      events: EventDescriptor.fromJson(
          json['events'] as Map<String, dynamic>?),
      process: _parseProcessList(json['process']),
      dataSource: DataSourceDescriptor.fromJson(
          json['dataSource'] as Map<String, dynamic>?),
    );
  }

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{'type': type};
    if (config.isNotEmpty) m['config'] = config;
    if (input != null) m['input'] = input!.toJson();
    final e = events.toJson();
    if (e.isNotEmpty) m['events'] = e;
    if (process.isNotEmpty) {
      m['process'] = process.map((p) => p.toJson()).toList();
    }
    if (dataSource != null) {
      final ds = dataSource!.toJson();
      if (ds.isNotEmpty) m['dataSource'] = ds;
    }
    return m;
  }
}

List<ProcessDescriptor> _parseProcessList(dynamic raw, {dynamic fallback}) {
  if (raw is List) {
    return raw
        .map((p) => ProcessDescriptor.fromJson(p as Map<String, dynamic>?))
        .toList();
  }
  // V1 兼容：单对象 process / globalProcess
  if (raw is Map<String, dynamic>) {
    return [ProcessDescriptor.fromJson(raw)];
  }
  if (fallback is Map<String, dynamic>) {
    return [ProcessDescriptor.fromJson(fallback)];
  }
  return [];
}

Map<String, SlotDescriptor> _parseSlots(dynamic raw) {
  if (raw == null || raw is! Map<String, dynamic>) return {};
  final result = <String, SlotDescriptor>{};
  for (final entry in raw.entries) {
    result[entry.key] = SlotDescriptor.fromJson(entry.value);
  }
  return result;
}

// ═══════ NavDescriptor ═══════

class NavDescriptor {
  final int? icon;
  final String label;
  final String routePath;
  final String section;
  final bool badge;

  const NavDescriptor({
    this.icon,
    required this.label,
    required this.routePath,
    required this.section,
    this.badge = false,
  });

  factory NavDescriptor.fromJson(Map<String, dynamic> json) => NavDescriptor(
    icon: _parseIcon(json['icon']),
    label: _require(json, 'label'),
    routePath: _require(json, 'route'),
    section: _require(json, 'section'),
    badge: json['badge'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'label': label,
    'route': routePath,
    'section': section,
    if (icon != null) 'icon': _iconToJson(icon),
    if (badge) 'badge': badge,
  };
}

// ═══════ SidebarDescriptor ═══════

class SidebarDescriptor {
  final String section;
  final int sectionOrder;
  final int order;
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

// ═══════ NavObjectDescriptor ═══════

/// V2 导航聚合——sidebar + secondary。
class NavObjectDescriptor {
  final SidebarDescriptor? sidebar;
  final List<NavDescriptor> secondary;

  const NavObjectDescriptor({
    this.sidebar,
    this.secondary = const [],
  });

  factory NavObjectDescriptor.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const NavObjectDescriptor();
    return NavObjectDescriptor(
      sidebar: json['sidebar'] != null
          ? SidebarDescriptor.fromJson(
              json['sidebar'] as Map<String, dynamic>)
          : null,
      secondary: _requireList(json, 'secondary',
          (d) => NavDescriptor.fromJson(d as Map<String, dynamic>)),
    );
  }

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{};
    if (sidebar != null) m['sidebar'] = sidebar!.toJson();
    if (secondary.isNotEmpty) {
      m['secondary'] = secondary.map((n) => n.toJson()).toList();
    }
    return m;
  }
}

// ═══════ Chat 相关选项 ═══════

class ThinkingOptions {
  final bool visible;
  final bool transparent;
  final String mode;
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

class ToolCallOptions {
  final bool visible;
  final bool showArgs;
  final bool showResult;
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

class BubbleOptions {
  final String style;
  final String avatarPosition;
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

class StreamOptions {
  final bool enabled;
  final String animation;
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

class AttachmentOptions {
  final bool enabled;
  final List<String> types;
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

class FeedbackStateOptions {
  final String color;
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

class InputOptions {
  final String mode;
  final bool autoFocus;
  final int maxLength;

  // free-text
  final bool multiline;
  final bool sendOnEnter;
  final AttachmentOptions attachments;
  final bool voice;
  final bool slashCommands;
  final List<String> quickReplies;

  // type-check
  final bool caseSensitive;
  final FeedbackOptions feedback;

  // code
  final String language;
  final bool autoIndent;
  final int tabSize;

  // select
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
          json['attachments'] is Map ? (json['attachments'] as Map).cast<String, dynamic>() : null),
      voice: _parseFlag(json['voice']),
      slashCommands: _parseFlag(json['slashCommands']),
      quickReplies: (json['quickReplies'] is List)
              ? (json['quickReplies'] as List).map((r) => r.toString()).toList()
              : [],
      caseSensitive: json['caseSensitive'] as bool? ?? false,
      feedback: FeedbackOptions.fromJson(
          json['feedback'] is Map ? (json['feedback'] as Map).cast<String, dynamic>() : null),
      language: json['language'] as String? ?? '',
      autoIndent: json['autoIndent'] as bool? ?? true,
      tabSize: json['tabSize'] as int? ?? 2,
      options: (json['options'] is List)
              ? (json['options'] as List).map((o) => o.toString()).toList()
              : [],
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

class FixedSizeOptions {
  final dynamic width;
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

class WorkspaceDescriptor {
  final bool enabled;
  final String accept;
  final int maxFiles;
  final int maxSizeMb;
  final List<String> aiCreatable;
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

// ═══════ 媒体相关 ═══════

class VideoOptions {
  final List<double> speeds;
  final bool cache;
  final String quality;
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

class AudioOptions {
  final List<double> speeds;
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

class DocumentOptions {
  final bool zoomable;
  final bool searchable;
  final bool pageIndicator;
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

class ImageOptions {
  final bool zoomable;
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

class MediaDescriptor {
  final String accept;
  final String mode;
  final String direction;
  final FixedSizeOptions? fixedSize;
  final bool controls;
  final VideoOptions? video;
  final AudioOptions? audio;
  final DocumentOptions? document;
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

// ═══════ 文档编辑选项 ═══════

class SpreadsheetOptions {
  final bool formulas;
  final bool charts;
  final bool sheets;
  final bool conditionalFormatting;
  final bool resizableColumns;
  final int columns;
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

class DocEditorOptions {
  final bool trackChanges;
  final bool comments;
  final bool tableOfContents;
  final bool footnotes;
  final bool headersFooters;
  final bool pageSetup;
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

class PresentationOptions {
  final bool transitions;
  final bool animations;
  final bool speakerNotes;
  final bool presenterView;
  final bool slideMaster;
  final List<String> layouts;
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

class ChatOptions {
  final ThinkingOptions thinking;
  final ToolCallOptions toolCalls;
  final BubbleOptions bubble;
  final StreamOptions stream;
  final String placeholder;
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

// ═══════ 表单 ═══════

class FormFieldDescriptor {
  final String key;
  final String label;
  final String type;
  final bool required;
  final List<String> options;
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

class FormDescriptor {
  final List<FormFieldDescriptor> fields;
  final String submitLabel;
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

class TimelineDescriptor {
  final String mode;
  final List<String> view;
  final String defaultView;
  final String? itemTap;
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

class MapDescriptor {
  final double? centerLat;
  final double? centerLng;
  final int zoom;
  final bool markers;
  final bool search;
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

// ═══════ ExposeStateConfig ═══════

class ExposeStateConfig {
  final List<String> events;
  final String format;
  final String subdir;

  const ExposeStateConfig({
    required this.events,
    this.format = 'json',
    required this.subdir,
  });

  factory ExposeStateConfig.fromJson(Map<String, dynamic> json) {
    return ExposeStateConfig(
      events: (json['events'] as List?)?.map((e) => e.toString()).toList() ?? [],
      format: json['format'] as String? ?? 'json',
      subdir: json['subdir'] as String? ?? 'state',
    );
  }
}

// ═══════ PageDescriptor (V2) ═══════

/// 页面描述符（V2）——独立 route、events、process[]、dataSource、layout。
class PageDescriptor {
  /// 页面唯一标识（模块内）。
  final String id;

  /// 页面标签。
  final String label;

  /// 页面路由（V2: 独立 route，不再由模块 route + page.id 拼接）。
  final String? route;

  /// 是否为默认页面。
  final bool isDefault;

  /// 是否为单页面模式（不显示子导航）。
  final bool singlePage;

  /// 页面级事件。
  final EventDescriptor events;

  /// 页面级进程列表（V2: 数组，替代 V1 的 globalProcess）。
  final List<ProcessDescriptor> process;

  /// 页面级数据源。
  final DataSourceDescriptor? dataSource;

  /// 布局。
  final LayoutDescriptor layout;

  const PageDescriptor({
    required this.id,
    required this.label,
    this.route,
    this.isDefault = false,
    this.singlePage = false,
    this.events = const EventDescriptor(),
    this.process = const [],
    this.dataSource,
    this.layout = const LayoutDescriptor(),
  });

  factory PageDescriptor.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const PageDescriptor(id: '', label: '');
    return PageDescriptor(
      id: _require(json, 'id'),
      label: _require(json, 'label'),
      route: json['route'] as String?,
      isDefault: json['default'] as bool? ?? false,
      singlePage: json['singlePage'] as bool? ?? false,
      events: EventDescriptor.fromJson(
          json['events'] as Map<String, dynamic>?),
      process: _parseProcessList(json['process'], fallback: json['globalProcess']),
      dataSource: DataSourceDescriptor.fromJson(
          json['dataSource'] as Map<String, dynamic>?),
      layout: LayoutDescriptor.fromJson(
          json['layout'] as Map<String, dynamic>?),
    );
  }

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{'id': id, 'label': label};
    if (route != null) m['route'] = route;
    if (isDefault) m['default'] = true;
    if (singlePage) m['singlePage'] = true;
    final e = events.toJson();
    if (e.isNotEmpty) m['events'] = e;
    if (process.isNotEmpty) {
      m['process'] = process.map((p) => p.toJson()).toList();
    }
    if (dataSource != null) {
      final ds = dataSource!.toJson();
      if (ds.isNotEmpty) m['dataSource'] = ds;
    }
    m['layout'] = layout.toJson();
    return m;
  }

  /// 本页所有 slot 的 component type 列表。
  List<String> get componentTypes {
    return layout.slots.values
        .where((s) => s.component != null)
        .map((s) => s.component!.type)
        .toList();
  }
}

// ═══════ ModuleDescriptor (V2) ═══════

/// 模块描述符（V2）——树形架构的根节点。
class ModuleDescriptor {
  /// Schema 版本："2.0"。
  final String schemaVersion;

  /// 模块唯一标识。
  final String id;

  /// 模块名称。
  final String name;

  /// 模块描述。
  final String description;

  /// 图标（codePoint）。
  final int? icon;

  /// 模块版本号。
  final String version;

  /// 模块路由（V2: 可选，不再决定页面路由）。
  final String? route;

  /// 依赖模块 ID 列表。
  final List<String> dependencies;

  /// 激活的 Skill 名列表。
  final List<String> activateSkills;

  /// 模块级默认样式。
  final StyleDescriptor style;

  /// 导航配置（sidebar + secondary）。
  final NavObjectDescriptor nav;

  /// 模块级进程列表（V2: 数组）。
  final List<ProcessDescriptor> process;

  /// 模块级事件。
  final EventDescriptor events;

  /// 交互动作。
  final ActionDescriptor? actions;

  /// 数据绑定列表。
  final List<DataBindingDescriptor> dataBindings;

  /// 文件工作区。
  final WorkspaceDescriptor? workspace;

  /// 页面列表。
  final List<PageDescriptor> pages;

  const ModuleDescriptor({
    this.schemaVersion = '2.0',
    required this.id,
    required this.name,
    this.description = '',
    this.icon,
    this.version = '0.0.0',
    this.route,
    this.dependencies = const [],
    this.activateSkills = const [],
    this.style = const StyleDescriptor(),
    this.nav = const NavObjectDescriptor(),
    this.process = const [],
    this.events = const EventDescriptor(),
    this.actions,
    this.dataBindings = const [],
    this.workspace,
    this.pages = const [],
  });

  // ═══ 便捷查询 ═══

  /// 是否为纯服务模块（无 UI 页面）。
  bool get isServiceOnly => pages.isEmpty && (route == null || route!.isEmpty);

  /// 是否出现在侧边栏。
  bool get hasSidebar => nav.sidebar != null && icon != null && !isServiceOnly;

  /// 所有路由路径。
  List<String> get allRoutePaths {
    final paths = <String>[];
    for (final page in pages) {
      if (page.route != null && page.route!.isNotEmpty) {
        paths.add(page.route!);
      }
    }
    if (route != null && route!.isNotEmpty) {
      paths.add(route!);
    }
    return paths;
  }

  // ═══ JSON 序列化 ═══

  factory ModuleDescriptor.fromJson(Map<String, dynamic> json) {
    _requireField(json, 'type', 'module');

    // 兼容 V1 单对象 actions 和 V2 对象 actions
    ActionDescriptor? actions;
    final rawActions = json['actions'];
    if (rawActions is Map) {
      actions = ActionDescriptor.fromJson(rawActions.cast<String, dynamic>());
    }

    return ModuleDescriptor(
      schemaVersion: json['schemaVersion'] as String? ?? '2.0',
      id: _require(json, 'id'),
      name: _require(json, 'name'),
      description: json['description'] as String? ?? '',
      icon: _parseIcon(json['icon']),
      version: json['version'] as String? ?? '0.0.0',
      route: json['route'] as String?,
      dependencies: (json['dependencies'] as List?)
              ?.map((d) => d.toString())
              .toList() ??
          [],
      activateSkills: (json['activateSkills'] as List?)
              ?.map((s) => s.toString())
              .toList() ??
          [],
      style: StyleDescriptor.fromJson(
          json['style'] as Map<String, dynamic>?),
      nav: NavObjectDescriptor.fromJson(
          json['nav'] as Map<String, dynamic>?),
      process: _parseProcessList(json['process']),
      events: EventDescriptor.fromJson(
          json['events'] as Map<String, dynamic>?),
      actions: actions,
      dataBindings: _requireList(
        json,
        'data',
        (d) => DataBindingDescriptor.fromJson(d as Map<String, dynamic>),
      ),
      workspace: WorkspaceDescriptor.fromJson(
          json['workspace'] as Map<String, dynamic>?),
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
      'schemaVersion': schemaVersion,
      'type': 'module',
      'id': id,
      'name': name,
    };
    if (description.isNotEmpty) m['description'] = description;
    if (icon != null) m['icon'] = _iconToJson(icon);
    if (version != '0.0.0') m['version'] = version;
    if (route != null) m['route'] = route;
    if (dependencies.isNotEmpty) m['dependencies'] = dependencies;
    if (activateSkills.isNotEmpty) m['activateSkills'] = activateSkills;

    final s = style.toJson();
    if (s.isNotEmpty) m['style'] = s;

    final n = nav.toJson();
    if (n.isNotEmpty) m['nav'] = n;

    if (process.isNotEmpty) {
      m['process'] = process.map((p) => p.toJson()).toList();
    }

    final e = events.toJson();
    if (e.isNotEmpty) m['events'] = e;

    if (actions != null) m['actions'] = actions!.toJson();

    if (dataBindings.isNotEmpty) {
      m['data'] = dataBindings.map((d) => d.toJson()).toList();
    }

    if (workspace != null) m['workspace'] = workspace!.toJson();

    if (pages.isNotEmpty) {
      m['pages'] = pages.map((p) => p.toJson()).toList();
    }

    return m;
  }

  @override
  bool operator ==(Object other) =>
      other is ModuleDescriptor && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'ModuleDescriptor($id, $name, v$schemaVersion)';
}
