/// 主题 Token 规范——五层画布 + 54 组件 token 定义。
///
/// # 五层画布
///
/// | 层 | 归属 | 画什么 |
/// |----|------|--------|
/// | `AppTokens` | App 壳 | sidebar, header, footer, blank, commandPalette |
/// | `ModuleTokens` | 模块 chrome | chrome |
/// | `PageTokens` | 页面级 | tabBar, background |
/// | `SlotTokens` | 插槽框 | header, background, border |
/// | `ComponentTokens` | 54 组件 | button, table, card, bubble... |
///
/// # 规则
///
/// - 各层正交：互不覆盖。App 画 sidebar，Slot 画框，Component 画内容。
/// - theme.json 必须完整声明所有子 token，不允许 fallback 默认值。
library;

// ═══════ App 层 ═══════

/// App 壳层 Token 规范——sidebar / header / footer / blank / commandPalette。
class AppTokens {
  AppTokens._();

  // ── 组件 key ──
  static const sidebar = 'sidebar';
  static const header = 'header';
  static const footer = 'footer';
  static const blank = 'blank';
  static const commandPalette = 'commandPalette';

  /// App 层全部组件 key。
  static const allowedKeys = <String>{
    sidebar, header, footer, blank, commandPalette,
  };

  /// App 层各组件子 token 规范。
  static const subTokens = <String, Set<String>>{
    sidebar: {'bg', 'text', 'active', 'hover', 'divider'},
    header: {'bg', 'text', 'border'},
    footer: {'bg', 'text', 'border'},
    blank: {'bg'},
    commandPalette: {'bg', 'text', 'highlight', 'border'},
  };

  static int get count => allowedKeys.length;
}

// ═══════ Module 层 ═══════

/// 模块 Chrome 层 Token 规范——模块级装饰。
class ModuleTokens {
  ModuleTokens._();

  static const chrome = 'chrome';

  static const allowedKeys = <String>{chrome};

  static const subTokens = <String, Set<String>>{
    chrome: {'bg', 'border'},
  };

  static int get count => allowedKeys.length;
}

// ═══════ Page 层 ═══════

/// 页面层 Token 规范——tabBar + 页面背景。
class PageTokens {
  PageTokens._();

  static const tabBar = 'tabBar';
  static const background = 'background';

  static const allowedKeys = <String>{tabBar, background};

  static const subTokens = <String, Set<String>>{
    tabBar: {'bg', 'text', 'active', 'indicator', 'hover', 'border'},
    background: {'color'},
  };

  static int get count => allowedKeys.length;
}

// ═══════ Slot 层 ═══════

/// 插槽框层 Token 规范——header / background / border。
class SlotTokens {
  SlotTokens._();

  static const header = 'header';
  static const background = 'background';
  static const border = 'border';

  static const allowedKeys = <String>{header, background, border};

  static const subTokens = <String, Set<String>>{
    header: {'bg', 'text', 'border'},
    background: {'color'},
    border: {'color', 'width'},
  };

  static int get count => allowedKeys.length;
}

// ═══════ Component 层（54 组件） ═══════

/// 54 组件 token 的规范 key + 各组件子 token。
class ComponentTokens {
  ComponentTokens._();

  // ── 导航 (5) ──
  static const sidebar = 'sidebar';
  static const tab = 'tab';
  static const breadcrumb = 'breadcrumb';
  static const pagination = 'pagination';
  static const stepper = 'stepper';

  // ── 对话 (5) ──
  static const bubble = 'bubble';
  static const thinking = 'thinking';
  static const toolCall = 'toolCall';
  static const codeBlock = 'codeBlock';
  static const blockquote = 'blockquote';

  // ── 表单 (7) ──
  static const input = 'input';
  static const checkbox = 'checkbox';
  static const radio = 'radio';
  static const switch_ = 'switch_';
  static const slider = 'slider';
  static const dropdown = 'dropdown';
  static const datePicker = 'datePicker';

  // ── 反馈 (6) ──
  static const progressBar = 'progressBar';
  static const spinner = 'spinner';
  static const skeleton = 'skeleton';
  static const toast = 'toast';
  static const alert = 'alert';
  static const emptyState = 'emptyState';

  // ── 数据展示 (9) ──
  static const table = 'table';
  static const card = 'card';
  static const list = 'list';
  static const chip = 'chip';
  static const avatar = 'avatar';
  static const badge = 'badge';
  static const tooltip = 'tooltip';
  static const calendar = 'calendar';
  static const timeline = 'timeline';

  // ── 按钮 (3) ──
  static const button = 'button';
  static const iconButton = 'iconButton';
  static const fab = 'fab';

  // ── 布局 (6) ──
  static const drawer = 'drawer';
  static const modal = 'modal';
  static const header = 'header';
  static const footer = 'footer';
  static const dividerComp = 'divider';
  static const scrollbar = 'scrollbar';

  // ── 图表 (1) ──
  static const chart = 'chart';

  // ── 媒体 (3) ──
  static const videoPlayer = 'videoPlayer';
  static const audioPlayer = 'audioPlayer';
  static const imageViewer = 'imageViewer';

  // ── 杂项 (5) ──
  static const link = 'link';
  static const menu = 'menu';
  static const commandPalette = 'commandPalette';
  static const contextMenu = 'contextMenu';
  static const search = 'search';

  // ── 范式 (4) ──
  static const spreadsheet = 'spreadsheet';
  static const document = 'document';
  static const presentation = 'presentation';
  static const workspace = 'workspace';

  /// 54 组件 key 的白名单。
  static const allowedKeys = <String>{
    sidebar, tab, breadcrumb, pagination, stepper,
    bubble, thinking, toolCall, codeBlock, blockquote,
    input, checkbox, radio, switch_, slider, dropdown, datePicker,
    progressBar, spinner, skeleton, toast, alert, emptyState,
    table, card, list, chip, avatar, badge, tooltip, calendar, timeline,
    button, iconButton, fab,
    drawer, modal, header, footer, dividerComp, scrollbar,
    chart,
    videoPlayer, audioPlayer, imageViewer,
    link, menu, commandPalette, contextMenu, search,
    spreadsheet, document, presentation, workspace,
  };

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

  static int get count => allowedKeys.length;

  static bool isKnownComponent(String key) => allowedKeys.contains(key);

  static Set<String> subTokensFor(String component) =>
      subTokens[component] ?? <String>{};
}

// ═══════ 校验 ═══════

/// 校验 hex 颜色字符串格式（#RGB / #RRGGBB / #AARRGGBB）。
bool isValidHexColor(String? value) {
  if (value == null || value.isEmpty) return false;
  return RegExp(
    r'^#[0-9A-Fa-f]{3}([0-9A-Fa-f]{3})?([0-9A-Fa-f]{2})?$',
  ).hasMatch(value);
}

/// 收集 [colors] 中不在 [allowedKeys] 里的未知 key。
List<String> unknownKeys(
  Map<String, dynamic> colors,
  Set<String> allowedKeys,
) {
  return colors.keys.where((k) => !allowedKeys.contains(k)).toList();
}
