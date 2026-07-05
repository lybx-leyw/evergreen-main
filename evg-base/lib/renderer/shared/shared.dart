/// 组合视图 + 调度基础设施——将原子 widget 组合为完整 UI 范式视图。
library shared;

// ── 基础设施 ──
export 'renderer_providers.dart';
export 'theme_provider.dart';

// ── 布局工具（从旧 shared/ 迁移） ──
export 'adaptive_layout.dart';
export 'responsive_scroll_view.dart';

// ── 布局引擎 ──
export 'layout_engine.dart';
export 'grid_layout.dart';
export 'panel_layout.dart';
export 'drawer_host.dart';

// ── 交互系统 ──
export 'interaction_wrapper.dart';

// ── 调度 + 页面 ──
export 'module_dispatch.dart';
export 'module_page.dart';

// ── 7 个范式视图 ──
export 'default_view.dart';
export 'chat_view.dart';
export 'spreadsheet_view.dart';
export 'document_view.dart';
export 'presentation_view.dart';
export 'dashboard_view.dart';
export 'editor_view.dart';

// ── 表单视图 ──
export 'form_view.dart';

// ── Sprint 2: 应用页面 ──
export 'market_view.dart';
export 'plugin_detail_view.dart';
export 'my_plugins_view.dart';
export 'settings_view.dart';
export 'permission_management_view.dart';
