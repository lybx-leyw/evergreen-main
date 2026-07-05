/// 主题 token 常量定义——20 语义 token + 54 组件 token 的规范清单。
///
/// # [SemanticTokens] — 20 语义 token
///
/// | # | key | 说明 |
/// |---|-----|------|
/// | 1 | `primary` | 主色 |
/// | 2 | `secondary` | 辅色 |
/// | 3 | `tertiary` | 第三色 |
/// | 4 | `background` | 页面背景 |
/// | 5 | `surface` | 卡片/容器背景 |
/// | 6 | `surfaceVariant` | 次级容器背景 |
/// | 7 | `error` | 错误/危险色 |
/// | 8 | `success` | 成功色 |
/// | 9 | `warning` | 警告色 |
/// | 10 | `info` | 信息色 |
/// | 11 | `text` | 正文 |
/// | 12 | `textSecondary` | 次要文本 |
/// | 13 | `textTertiary` | 三级文本 |
/// | 14 | `textInverse` | 反色文本（深底亮字） |
/// | 15 | `border` | 边框 |
/// | 16 | `shadow` | 阴影 |
/// | 17 | `overlay` | 遮罩 |
/// | 18 | `disabled` | 禁用态 |
/// | 19 | `placeholder` | 占位符 |
/// | 20 | `divider` | 分割线 |
///
/// # [ComponentTokens] — 54 组件 token
///
/// ## 导航
/// | `sidebar` | bg, text, active, hover |
/// | `tab` | text, active, indicator, hover |
/// | `breadcrumb` | text, link, separator |
/// | `pagination` | bg, active, text, hover |
/// | `stepper` | done, active, pending, line |
///
/// ## 对话
/// | `bubble` | user, assistant, text, timestamp |
/// | `thinking` | bg, text, border |
/// | `toolCall` | bg, text, border |
/// | `codeBlock` | bg, text, border, header |
/// | `blockquote` | border, text, bg |
///
/// ## 表单
/// | `input` | bg, text, border, focus, placeholder, error |
/// | `checkbox` | border, fill, check |
/// | `radio` | border, fill |
/// | `switch_` | track, thumb, trackActive |
/// | `slider` | track, fill, thumb |
/// | `dropdown` | bg, text, border, itemHover |
/// | `datePicker` | header, selected, today, hover |
///
/// ## 反馈
/// | `progressBar` | track, fill, text |
/// | `spinner` | color, track |
/// | `skeleton` | bg, shimmer |
/// | `toast` | bg, text, border, success, error, warning, info |
/// | `alert` | bg, text, border, icon |
/// | `emptyState` | icon, text, action |
///
/// ## 数据展示
/// | `table` | header, stripe, text, border, hover |
/// | `card` | bg, border, shadow, text |
/// | `list` | bg, hover, divider |
/// | `chip` | bg, text, border, close |
/// | `avatar` | bg, text, border |
/// | `badge` | bg, text |
/// | `tooltip` | bg, text |
/// | `calendar` | header, selected, today, otherMonth, event |
/// | `timeline` | line, dot, card |
///
/// ## 按钮
/// | `button` | primary, hover, active, disabled, text |
/// | `iconButton` | color, hover, active |
/// | `fab` | bg, icon, shadow |
///
/// ## 布局
/// | `drawer` | bg, text, overlay |
/// | `modal` | bg, overlay, text, border |
/// | `header` | bg, text, border |
/// | `footer` | bg, text, border |
/// | `divider` | color, thickness |
/// | `scrollbar` | thumb, track |
///
/// ## 图表
/// | `chart` | colors, axis, grid, tooltip |
///
/// ## 媒体
/// | `videoPlayer` | controls, progress, overlay |
/// | `audioPlayer` | controls, waveform, progress |
/// | `imageViewer` | bg, overlay |
///
/// ## 杂项
/// | `link` | text, hover, visited |
/// | `menu` | bg, text, hover, divider |
/// | `commandPalette` | bg, text, highlight, border |
/// | `contextMenu` | bg, text, hover, divider |
/// | `search` | bg, text, border, focus, icon |
///
/// ## 范式（新增）
/// | `spreadsheet` | header, grid, cell, cellSelected, formulaBar, tab |
/// | `document` | bg, text, ruler, pageShadow, comment, selection |
/// | `presentation` | bg, canvas, slideBorder, toolbar, notes |
/// | `workspace` | bg, tabBar, panel, resizeHandle, empty |
library;

// ═══════ SemanticTokens ═══════

/// 20 语义 token 的规范 key。
class SemanticTokens {
  SemanticTokens._();

  // ── 品牌色 ──
  static const primary = 'primary';
  static const secondary = 'secondary';
  static const tertiary = 'tertiary';

  // ── 背景/表面 ──
  static const background = 'background';
  static const surface = 'surface';
  static const surfaceVariant = 'surfaceVariant';

  // ── 状态色 ──
  static const error = 'error';
  static const success = 'success';
  static const warning = 'warning';
  static const info = 'info';

  // ── 文本 ──
  static const text = 'text';
  static const textSecondary = 'textSecondary';
  static const textTertiary = 'textTertiary';
  static const textInverse = 'textInverse';

  // ── 结构 ──
  static const border = 'border';
  static const shadow = 'shadow';
  static const overlay = 'overlay';

  // ── 状态装饰 ──
  static const disabled = 'disabled';
  static const placeholder = 'placeholder';
  static const divider = 'divider';

  /// 20 个语义 token key 的白名单。
  static const allowedKeys = <String>{
    primary, secondary, tertiary,
    background, surface, surfaceVariant,
    error, success, warning, info,
    text, textSecondary, textTertiary, textInverse,
    border, shadow, overlay,
    disabled, placeholder, divider,
  };

  /// key 数量。
  static int get count => allowedKeys.length;
}

// ═══════ ComponentTokens ═══════

/// 54 组件 token 的规范 key + 各组件子 token。
class ComponentTokens {
  ComponentTokens._();

  // ── 导航 ──
  static const sidebar = 'sidebar';
  static const tab = 'tab';
  static const breadcrumb = 'breadcrumb';
  static const pagination = 'pagination';
  static const stepper = 'stepper';

  // ── 对话 ──
  static const bubble = 'bubble';
  static const thinking = 'thinking';
  static const toolCall = 'toolCall';
  static const codeBlock = 'codeBlock';
  static const blockquote = 'blockquote';

  // ── 表单 ──
  static const input = 'input';
  static const checkbox = 'checkbox';
  static const radio = 'radio';
  static const switch_ = 'switch_';
  static const slider = 'slider';
  static const dropdown = 'dropdown';
  static const datePicker = 'datePicker';

  // ── 反馈 ──
  static const progressBar = 'progressBar';
  static const spinner = 'spinner';
  static const skeleton = 'skeleton';
  static const toast = 'toast';
  static const alert = 'alert';
  static const emptyState = 'emptyState';

  // ── 数据展示 ──
  static const table = 'table';
  static const card = 'card';
  static const list = 'list';
  static const chip = 'chip';
  static const avatar = 'avatar';
  static const badge = 'badge';
  static const tooltip = 'tooltip';
  static const calendar = 'calendar';
  static const timeline = 'timeline';

  // ── 按钮 ──
  static const button = 'button';
  static const iconButton = 'iconButton';
  static const fab = 'fab';

  // ── 布局 ──
  static const drawer = 'drawer';
  static const modal = 'modal';
  static const header = 'header';
  static const footer = 'footer';
  /// `divider` 组件 key——与 [SemanticTokens.divider] 值相同（均为 `"divider"`）。
  ///
  /// JSON 中同一 key 只能有一种类型：字符串 = 语义 token，对象 = 组件 token。
  /// 内置 light/dark 主题将 `divider` 作为语义 token 声明；其他主题作为组件 token。
  /// 组件 token 形态下子 token `thickness` 存储 CSS 宽度值（如 `"1"`），非颜色。
  static const dividerComp = 'divider';
  static const scrollbar = 'scrollbar';

  // ── 图表 ──
  static const chart = 'chart';

  // ── 媒体 ──
  static const videoPlayer = 'videoPlayer';
  static const audioPlayer = 'audioPlayer';
  static const imageViewer = 'imageViewer';

  // ── 杂项 ──
  static const link = 'link';
  static const menu = 'menu';
  static const commandPalette = 'commandPalette';
  static const contextMenu = 'contextMenu';
  static const search = 'search';

  // ── 范式 ──
  static const spreadsheet = 'spreadsheet';
  static const document = 'document';
  static const presentation = 'presentation';
  static const workspace = 'workspace';

  /// 54 组件 key 的白名单。
  static const allowedKeys = <String>{
    // 导航 (5)
    sidebar, tab, breadcrumb, pagination, stepper,
    // 对话 (5)
    bubble, thinking, toolCall, codeBlock, blockquote,
    // 表单 (7)
    input, checkbox, radio, switch_, slider, dropdown, datePicker,
    // 反馈 (6)
    progressBar, spinner, skeleton, toast, alert, emptyState,
    // 数据展示 (9)
    table, card, list, chip, avatar, badge, tooltip, calendar, timeline,
    // 按钮 (3)
    button, iconButton, fab,
    // 布局 (6)
    drawer, modal, header, footer, dividerComp, scrollbar,
    // 图表 (1)
    chart,
    // 媒体 (3)
    videoPlayer, audioPlayer, imageViewer,
    // 杂项 (5)
    link, menu, commandPalette, contextMenu, search,
    // 范式 (4)
    spreadsheet, document, presentation, workspace,
  };

  /// key 数量。
  static int get count => allowedKeys.length;

  /// 各组件的推荐子 token 集合。
  static const subTokens = <String, Set<String>>{
    // 导航
    sidebar: {'bg', 'text', 'active', 'hover'},
    tab: {'text', 'active', 'indicator', 'hover'},
    breadcrumb: {'text', 'link', 'separator'},
    pagination: {'bg', 'active', 'text', 'hover'},
    stepper: {'done', 'active', 'pending', 'line'},
    // 对话
    bubble: {'user', 'assistant', 'text', 'timestamp'},
    thinking: {'bg', 'text', 'border'},
    toolCall: {'bg', 'text', 'border'},
    codeBlock: {'bg', 'text', 'border', 'header'},
    blockquote: {'border', 'text', 'bg'},
    // 表单
    input: {'bg', 'text', 'border', 'focus', 'placeholder', 'error'},
    checkbox: {'border', 'fill', 'check'},
    radio: {'border', 'fill'},
    switch_: {'track', 'thumb', 'trackActive'},
    slider: {'track', 'fill', 'thumb'},
    dropdown: {'bg', 'text', 'border', 'itemHover'},
    datePicker: {'header', 'selected', 'today', 'hover'},
    // 反馈
    progressBar: {'track', 'fill', 'text'},
    spinner: {'color', 'track'},
    skeleton: {'bg', 'shimmer'},
    toast: {'bg', 'text', 'border', 'success', 'error', 'warning', 'info'},
    alert: {'bg', 'text', 'border', 'icon'},
    emptyState: {'icon', 'text', 'action'},
    // 数据展示
    table: {'header', 'stripe', 'text', 'border', 'hover'},
    card: {'bg', 'border', 'shadow', 'text'},
    list: {'bg', 'hover', 'divider'},
    chip: {'bg', 'text', 'border', 'close'},
    avatar: {'bg', 'text', 'border'},
    badge: {'bg', 'text'},
    tooltip: {'bg', 'text'},
    calendar: {'header', 'selected', 'today', 'otherMonth', 'event'},
    timeline: {'line', 'dot', 'card'},
    // 按钮
    button: {'primary', 'hover', 'active', 'disabled', 'text'},
    iconButton: {'color', 'hover', 'active'},
    fab: {'bg', 'icon', 'shadow'},
    // 布局
    drawer: {'bg', 'text', 'overlay'},
    modal: {'bg', 'overlay', 'text', 'border'},
    header: {'bg', 'text', 'border'},
    footer: {'bg', 'text', 'border'},
    dividerComp: {'color', 'thickness'},
    scrollbar: {'thumb', 'track'},
    // 图表
    chart: {'colors', 'axis', 'grid', 'tooltip'},
    // 媒体
    videoPlayer: {'controls', 'progress', 'overlay'},
    audioPlayer: {'controls', 'waveform', 'progress'},
    imageViewer: {'bg', 'overlay'},
    // 杂项
    link: {'text', 'hover', 'visited'},
    menu: {'bg', 'text', 'hover', 'divider'},
    commandPalette: {'bg', 'text', 'highlight', 'border'},
    contextMenu: {'bg', 'text', 'hover', 'divider'},
    search: {'bg', 'text', 'border', 'focus', 'icon'},
    // 范式
    spreadsheet: {'header', 'grid', 'cell', 'cellSelected', 'formulaBar', 'tab'},
    document: {'bg', 'text', 'ruler', 'pageShadow', 'comment', 'selection'},
    presentation: {'bg', 'canvas', 'slideBorder', 'toolbar', 'notes'},
    workspace: {'bg', 'tabBar', 'panel', 'resizeHandle', 'empty'},
  };

  /// 校验 key 是否为已知语义 token。未知 key 返回 false。
  static bool isKnownComponent(String key) => allowedKeys.contains(key);

  /// 获取指定组件的推荐子 token。未知组件返回空集合。
  static Set<String> subTokensFor(String component) =>
      subTokens[component] ?? <String>{};
}

// ═══════ 校验 ═══════

/// 校验 hex 颜色字符串格式（#RGB / #RRGGBB / #AARRGGBB）。
bool isValidHexColor(String? value) {
  if (value == null || value.isEmpty) return false;
  return RegExp(r'^#[0-9A-Fa-f]{3}([0-9A-Fa-f]{3})?([0-9A-Fa-f]{2})?$').hasMatch(value);
}

/// 收集 [colors] 中不在 [allowedKeys] 里的未知 key。
List<String> unknownKeys(Map<String, dynamic> colors, Set<String> allowedKeys) {
  return colors.keys.where((k) => !allowedKeys.contains(k)).toList();
}
