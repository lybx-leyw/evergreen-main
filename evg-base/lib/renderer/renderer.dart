/// renderer/ 顶层 barrel
///
/// 结构（slot/ 与组件域已随 v4_modle 收敛到模板内部）：
///   app/        — App 层（顶层壳、全局主题服务）
///   module/     — 模块层（ModuleDispatch、ModulePage）
///   page/       — 页面层（布局引擎、独立页面）
///   components/ — 共享组件（shared/ 组合基础设施 + widgets/ 原子组件）
///   templates/  — 模板（modle）渲染器与注册表；slot 分派与
///                 文档/数据/交互/创意/学习/控制组件域位于
///                 `templates/v4_modle/slot/` 与 `templates/v4_modle/components/`
library;

export 'app/app.dart';
export 'module/module.dart';
export 'page/page.dart';
export 'components/shared/shared.dart';
export 'components/shared/stream_source.dart';
export 'components/shared/stream_playback.dart';
export 'components/shared/file_export_names.dart';
export 'components/shared/file_export.dart';
export 'components/shared/file_export_bar.dart';
export 'components/shared/workspace_download_names.dart';
export 'components/shared/workspace_file_download.dart';
export 'templates/v4_modle/slot/slot.dart';
export 'templates/v4_modle/components/document/document.dart';
export 'templates/v4_modle/components/data/data.dart';
export 'templates/v4_modle/components/interaction/interaction.dart';
export 'templates/v4_modle/components/creative/creative.dart';
export 'templates/v4_modle/components/learning/learning.dart';
export 'templates/v4_modle/components/controls/controls.dart';
