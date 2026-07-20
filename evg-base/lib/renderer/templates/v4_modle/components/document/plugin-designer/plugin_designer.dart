/// 全流程插件创作流 —— plugin-designer 组件（按钮式设计器 v3）。
///
/// 包含:
/// - [PluginDesignerView] — 按钮驱动编排主视图（左面板 + 右实时预览）
/// - [DesignDocument] / [DesignPage] / [DesignSlot] / [DesignComponent] — 编排模型
/// - [DesignToManifest] — 设计 → manifest 编译器
/// - [PluginPreloader] — 文件监控热加载
/// - [PreviewSyncService] — 预览同步
/// - [AutoCompileService] — .py 自动编译
/// - [CompositePreviewFrame] — 真实 CompositeView 渲染预览

// 模型
export 'models/design_component.dart';
export 'models/design_document.dart';
export 'models/design_page.dart';
export 'models/design_slot.dart';

// 服务
export 'services/auto_compile_service.dart';
export 'services/config_register.dart';
export 'services/data_pluginer.dart';
export 'services/design_doc_service.dart';
export 'services/design_to_manifest.dart';
export 'services/plugin_exporter.dart';
export 'services/plugin_generator.dart';
export 'services/plugin_preloader.dart';
export 'services/plugin_state_service.dart';
export 'services/preview_sync_service.dart';

// 视图
export 'plugin_designer_slot.dart';
export 'plugin_designer_view.dart';
export 'view/component_picker.dart';
export 'view/onboarding_overlay.dart';
export 'view/page_sorter.dart';
export 'view/preview_panel.dart';
export 'view/property_panel.dart';

// Widgets
export 'widgets/composite_preview_frame.dart';
export 'widgets/plugin_icon_picker.dart';
export 'widgets/property_editor.dart';

