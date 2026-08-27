/// 皮肤包描述符——AI 视图「DIY your own greenix」皮肤（manifest.json）。
///
/// # [SkinDescriptor] —— 皮肤包声明（agent 皮肤包）
///
/// | 工厂 / 方法 | 输入 | 输出 | 说明 |
/// |---|---|---|---|
/// | `SkinDescriptor(...)` | `id`, `name`, ... | `SkinDescriptor` | const 构造 |
/// | `SkinDescriptor.fromJson(json)` | `Map<String,dynamic>` | `SkinDescriptor` | 解析；校验 `type=="skin"` |
/// | `SkinDescriptor.fromJsonString(str)` | `String` | `SkinDescriptor` | JSON 字符串解析 |
/// | `toJson()` | — | `Map<String,dynamic>` | 序列化回 JSON（不含运行时 `sourceDir`） |
/// | `withSourceDir(dir)` | `String` | `SkinDescriptor` | 复制并标记插件目录（扫描加载时用） |
///
/// # DIY 段（全部可选，未知键静默忽略）
///
/// | 段 | 键 | 说明 | 渲染层消费 |
/// |----|----|------|-----------|
/// | `assets` | `logoDesktop`/`logoMobile`/`backgroundImage` | 图片资源引用（相对 manifest 路径） | 头像 / 空状态 logo 等 |
/// | `background` | `type`(solid/gradient)、`color`、`gradient.from/to/angle` | 对话背景（A1） | 消息列表容器 decoration |
/// | `buttons` | `inputBar.{workspace,webSearch,thinkingEffort,tools,bgProcess,skills,clear}`、`messageActions.{copy,regenerate,edit}` | 按钮显隐（B1/B2） | 工具栏 / 消息操作行 |
/// | `thinking` | `title`、`visible`、`colors.{header,containerBackground,containerBorder,contentText,chipMemoryBg/Fg,chipSkillBg/Fg,chipToolBg/Fg,chipToolResultBg/Fg}` | 思考栏配色（C1）+ 标题（E） | 思考栏渲染点 |
/// | `bubble` | `userBackground`/`assistantBackground`/`userTextColor`/`assistantTextColor`/`borderRadius`/`maxWidthRatio` | 消息气泡样式（D1） | 气泡 BoxDecoration / ConstrainedBox |
/// | `avatar` | `user`/`assistant`（hex 颜色或图片资源引用） | 头像 DIY（E） | CircleAvatar |
/// | `emptyState` | `logo`（hex 或图片引用）、`title` | 空状态欢迎区（E） | 空状态渲染 |
/// | 顶层 | `effortColor`、`toolActiveColor`、`codeInline`、`codeBlockBackground` | 功能色快捷覆盖（C1） | 深度思考档位 / 工具激活 / 代码色 |
///
/// # 「功能色 vs 语义色」边界
///
/// 皮肤包只覆盖「AI 视图内部消费点」的功能色与局部渲染，**绝不覆盖**
/// `ThemeData`/`ColorScheme` 语义色（primary/surface/onSurface/tertiary 等）。
/// 所有 getter 返回 `null` 表示「未配置 → 渲染层回退现有默认值」，
/// 保证未装皮肤包时零行为变化（与仓库「未知静默忽略」约定一致）。
library;

import 'dart:convert';

/// 皮肤包 manifest 的 `type` 值。
const String kSkinType = 'skin';

// ═══════ SkinDescriptor ═══════

/// 皮肤包描述符——AI 视图 DIY 皮肤声明。
///
/// 解析策略：`type` 必填且必须为 `"skin"`；`id`/`name` 缺失回退空串；
/// 其余 DIY 段全部可选，未知键静默忽略（沿用仓库解析约定）。
class SkinDescriptor {
  /// 唯一标识，如 `"evergreen-logo"`。
  final String id;

  /// 展示名称，如 `"绿意 Logo 皮肤"`。
  final String name;

  /// 版本号（可选，缺省空串）。
  final String version;

  /// 一句话描述（可选）。
  final String? description;

  /// 插件目录（`plugins/<id>`）——由 [SkinLoader] 扫描时填充；
  /// 内置皮肤包为 `null`（无外部图片资源）。
  final String? sourceDir;

  /// 原始 manifest 内容。DIY 段从这里读取；未知键保留但不消费。
  final Map<String, dynamic> raw;

  const SkinDescriptor({
    required this.id,
    required this.name,
    this.version = '',
    this.description,
    this.sourceDir,
    Map<String, dynamic>? raw,
  }) : raw = raw ?? const {};

  // ═══════ 段访问 ═══════

  Map<String, dynamic>? _section(String key) {
    final v = raw[key];
    return v is Map<String, dynamic> ? v : null;
  }

  /// 图片资源引用段（相对 manifest 路径）。
  Map<String, dynamic>? get assets => _section('assets');

  /// 对话背景段（A1：纯色 / 渐变）。
  Map<String, dynamic>? get background => _section('background');

  /// 按钮显隐段（B1 工具栏 / B2 消息操作）。
  Map<String, dynamic>? get buttons => _section('buttons');

  /// 思考栏段（C1 配色 + E 标题）。
  Map<String, dynamic>? get thinking => _section('thinking');

  /// 消息气泡段（D1）。
  Map<String, dynamic>? get bubble => _section('bubble');

  /// 头像段（E）。
  Map<String, dynamic>? get avatar => _section('avatar');

  /// 空状态欢迎区段（E）。
  Map<String, dynamic>? get emptyState => _section('emptyState');

  // ═══════ 类型化取值 ═══════

  static String? _str(Map<String, dynamic>? m, String key) {
    final v = m?[key];
    return v is String && v.isNotEmpty ? v : null;
  }

  static double? _num(Map<String, dynamic>? m, String key) {
    final v = m?[key];
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  static bool? _bool(Map<String, dynamic>? m, String key) {
    final v = m?[key];
    return v is bool ? v : null;
  }

  static Map<String, dynamic>? _subMap(Map<String, dynamic>? m, String key) {
    final v = m?[key];
    return v is Map<String, dynamic> ? v : null;
  }

  // ═══════ assets 段 ═══════

  /// 取 `assets.<key>` 的图片资源引用（相对 manifest 路径）。
  String? asset(String key) => _str(assets, key);

  /// 桌面/横板 logo 资源引用。
  String? get logoDesktop => asset('logoDesktop');

  /// 移动/竖板 logo 资源引用。
  String? get logoMobile => asset('logoMobile');

  /// 背景图资源引用（A2 图片背景预留；v1 不消费）。
  String? get backgroundImage => asset('backgroundImage');

  // ═══════ background 段（A1）═══════

  /// 背景类型：`solid` / `gradient`（未知值渲染层忽略 → 默认背景）。
  String? get backgroundType => _str(background, 'type');

  /// 纯色背景 hex（`#RRGGBB` / `#AARRGGBB`）。
  String? get backgroundColor => _str(background, 'color');

  Map<String, dynamic>? get _backgroundGradient =>
      _subMap(background, 'gradient');

  /// 渐变起始色 hex。
  String? get backgroundGradientFrom => _str(_backgroundGradient, 'from');

  /// 渐变结束色 hex。
  String? get backgroundGradientTo => _str(_backgroundGradient, 'to');

  /// 渐变角度（度，0=左→右；渲染层缺省 135）。
  double? get backgroundGradientAngle => _num(_backgroundGradient, 'angle');

  // ═══════ buttons 段（B1/B2）═══════

  /// B1 输入框上方按钮行逐项显隐。键：`workspace`/`webSearch`/
  /// `thinkingEffort`/`tools`/`bgProcess`/`skills`/`clear`。
  /// `null` = 未配置 → 渲染层显示（缺省全显示）。
  bool? inputBarVisible(String key) =>
      _bool(_subMap(buttons, 'inputBar'), key);

  /// B2 消息操作按钮显隐。键：`copy`/`regenerate`/`edit`。
  /// `null` = 未配置 → 渲染层显示（缺省全显示）。
  bool? messageActionVisible(String key) =>
      _bool(_subMap(buttons, 'messageActions'), key);

  // ═══════ thinking 段（C1 / E）═══════

  Map<String, dynamic>? get _thinkingColors => _subMap(thinking, 'colors');

  /// 思考栏功能色——兼容两种写法：`thinking.colors.<key>` 与扁平 `thinking.<key>`。
  /// 键：`header`/`containerBackground`/`contentText`/`chipMemoryBg`/
  /// `chipMemoryFg`/`chipSkillBg`/`chipSkillFg`/`chipToolBg`/`chipToolFg`/
  /// `chipToolResultBg`/`chipToolResultFg`。
  String? thinkingColor(String key) =>
      _str(_thinkingColors, key) ?? _str(thinking, key);

  /// 思考栏标题文案（E；缺省渲染层用「思考过程」）。
  String? get thinkingTitle => _str(thinking, 'title');

  /// 思考栏是否显示（C2 预留；v1 渲染层不消费，保持现有行为）。
  bool? get thinkingVisible => _bool(thinking, 'visible');

  // ═══════ bubble 段（D1）═══════

  /// 用户气泡底色 hex（null = 跟随 theme primary）。
  String? get bubbleUserBackground => _str(bubble, 'userBackground');

  /// AI 气泡底色 hex（null = 跟随 theme surfaceContainerHighest）。
  String? get bubbleAssistantBackground =>
      _str(bubble, 'assistantBackground');

  /// 用户气泡文字色 hex（null = 跟随 theme onPrimary）。
  String? get bubbleUserTextColor => _str(bubble, 'userTextColor');

  /// AI 气泡文字色 hex（null = 跟随 theme onSurface）。
  String? get bubbleAssistantTextColor => _str(bubble, 'assistantTextColor');

  /// 气泡圆角（缺省渲染层用 16/4）。
  double? get bubbleBorderRadius => _num(bubble, 'borderRadius');

  /// 气泡最大宽度占比（缺省渲染层用 0.72）。
  double? get bubbleMaxWidthRatio => _num(bubble, 'maxWidthRatio');

  // ═══════ avatar 段（E）═══════

  /// 用户头像：hex 颜色（`#` 开头）或图片资源引用（相对 manifest 路径）。
  String? get avatarUser => _str(avatar, 'user');

  /// AI 头像：hex 颜色（`#` 开头）或图片资源引用（相对 manifest 路径）。
  String? get avatarAssistant => _str(avatar, 'assistant');

  // ═══════ emptyState 段（E）═══════

  /// 空状态欢迎区 logo：hex 颜色（`#` 开头，作为默认图标着色）或图片资源引用。
  String? get emptyStateLogo => _str(emptyState, 'logo');

  /// 空状态欢迎区标题文案（缺省渲染层用「我是你的 AI 教学助手」）。
  String? get emptyStateTitle => _str(emptyState, 'title');

  // ═══════ 顶层功能色快捷覆盖（C1）═══════

  /// 深度思考档位紫色（现有默认 `0xFF7B1FA2`）可覆盖。
  String? get effortColor => _str(raw, 'effortColor');

  /// 「工具」按钮激活绿（现有默认 `0xFF2E7D32`）可覆盖。
  String? get toolActiveColor => _str(raw, 'toolActiveColor');

  /// 内联代码文字色（现有默认 `0xFFE53935`）可覆盖。兼容 `bubble.codeInline`。
  String? get codeInline =>
      _str(raw, 'codeInline') ?? _str(bubble, 'codeInline');

  /// 代码块背景兜底色（现有默认 `0xFFF5F5F5`）可覆盖。兼容 `bubble.codeBlockBackground`。
  String? get codeBlockBackground =>
      _str(raw, 'codeBlockBackground') ?? _str(bubble, 'codeBlockBackground');

  // ═══════ JSON ═══════

  /// 解析 manifest。`type` 必须为 `"skin"`，否则抛 [FormatException]。
  factory SkinDescriptor.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    if (type != kSkinType) {
      throw FormatException('type 必须为 "skin"，实际 "$type"');
    }
    return SkinDescriptor(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      version: json['version'] as String? ?? '',
      description: json['description'] as String?,
      raw: json,
    );
  }

  factory SkinDescriptor.fromJsonString(String str) =>
      SkinDescriptor.fromJson(jsonDecode(str) as Map<String, dynamic>);

  /// 序列化回 JSON（仅已知键；`sourceDir` 为运行时字段不入序列化）。
  Map<String, dynamic> toJson() {
    final out = <String, dynamic>{
      'type': kSkinType,
      'id': id,
      'name': name,
    };
    if (version.isNotEmpty) out['version'] = version;
    if (description != null) out['description'] = description;
    for (final key in const [
      'assets',
      'background',
      'buttons',
      'thinking',
      'bubble',
      'avatar',
      'emptyState',
    ]) {
      final v = raw[key];
      if (v is Map) out[key] = v;
    }
    for (final key in const [
      'effortColor',
      'toolActiveColor',
      'codeInline',
      'codeBlockBackground',
    ]) {
      final v = raw[key];
      if (v != null) out[key] = v;
    }
    return out;
  }

  /// 复制并标记插件目录（`plugins/<id>`），供渲染层解析皮肤内图片资源。
  SkinDescriptor withSourceDir(String dir) => SkinDescriptor(
        id: id,
        name: name,
        version: version,
        description: description,
        sourceDir: dir,
        raw: raw,
      );

  @override
  String toString() => 'SkinDescriptor($id, $name)';
}
