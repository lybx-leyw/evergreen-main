/// Palace Feature — 个人世界宫殿 UI 层。
///
/// ## 模块
/// - providers/ — Riverpod 状态管理
/// - screens/ — 主页面
/// - dialogs/ — 捕捉弹窗
/// - widgets/ — 可复用 UI 组件
library palace_feature;

export 'providers/palace_event_store_provider.dart';
export 'providers/palace_events_provider.dart';
export 'providers/palace_capture_provider.dart';
export 'providers/palace_lessons_provider.dart';
export 'providers/palace_tags_provider.dart';
export 'providers/palace_filter_provider.dart';
export 'screens/palace_screen.dart';
export 'dialogs/capture_dialog.dart';
export 'widgets/event_tree_view.dart';
export 'widgets/event_card.dart';
export 'widgets/event_detail_panel.dart';
export 'widgets/emotion_selector.dart';
export 'widgets/tag_chip_bar.dart';
export 'widgets/type_filter_bar.dart';
