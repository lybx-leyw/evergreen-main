/// renderer/ 顶层 barrel
///
/// 六层架构：
///   app/        — App 层（顶层壳、全局主题服务）
///   module/     — 模块层（ModuleDispatch、ModulePage）
///   page/       — 页面层（CompositeView、布局引擎、独立页面）
///   slot/       — Slot 层（SlotDispatch、SlotScale）
///   components/ — 组件层（43 具名组件 + 20 placeholder，按 7 功能域分组）
///   html/       — HTML 渲染（dispatch map，渲染函数散落在各组件文件夹）
library;

export 'app/app.dart';
export 'module/module.dart';
export 'page/page.dart';
export 'slot/slot.dart';
export 'components/shared/shared.dart';
export 'components/document/document.dart';
export 'components/data/data.dart';
export 'components/interaction/interaction.dart';
export 'components/creative/creative.dart';
export 'components/learning/learning.dart';
export 'components/controls/controls.dart';
