/// Palace Core — 个人世界宫殿平台层。
///
/// ## 模块
/// - models/ — 数据模型（事件、情境快照、结构化教训、回响调度）
/// - storage/ — 文件系统存储（EventStore + 三重索引 + 路径管理）
/// - capture/ — 事件采集（情境采集器 + 快速捕捉服务）
/// - refinery/ — AI 分析（教训提取、追问生成、自动标签）
/// - tools/ — Agent 工具（capture_to_palace）
library palace;

export 'models/consciousness_event.dart';
export 'models/context_snapshot.dart';
export 'models/structured_lesson.dart';
export 'models/echo_schedule.dart';
export 'storage/event_store.dart';
export 'storage/palace_paths.dart';
export 'capture/context_capturer.dart';
export 'capture/quick_capture_service.dart';
export 'refinery/lesson_extractor.dart';
export 'refinery/question_generator.dart';
export 'refinery/auto_tagger.dart';
export 'tools/capture_to_palace_tool.dart';
