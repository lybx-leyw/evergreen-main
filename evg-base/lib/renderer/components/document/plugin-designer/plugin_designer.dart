/// 全流程插件创作流 —— plugin-designer 组件。
///
/// 包含:
/// - [PluginDesignerView] — 三栏编排主视图
/// - [DesignDocument] / [DesignPage] / [DesignSlot] / [DesignComponent] — 编排模型
/// - [DesignToManifest] — 设计 → manifest 编译器
/// - [PluginPreloader] — 文件监控热加载
/// - [PreviewSyncService] — 预览同步
/// - [AutoCompileService] — .py 自动编译
/// - [PreviewPanel] — 实时预览面板

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
export 'view/canvas_area.dart';
export 'view/component_picker.dart';
export 'view/onboarding_overlay.dart';
export 'view/page_sorter.dart';
export 'view/preview_panel.dart';
export 'view/property_panel.dart';
export 'view/slot_painter.dart';

// Widgets
export 'widgets/draggable_component.dart';
export 'widgets/plugin_icon_picker.dart';
export 'widgets/property_editor.dart';
export 'widgets/slot_frame.dart';

