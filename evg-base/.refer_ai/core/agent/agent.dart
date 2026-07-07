/// Agent Runtime — Greenix 全量 Dart 复刻。
///
/// ## 模块
/// - message.dart — 对话消息、工具调用、Schema 数据模型
/// - event.dart — 17 种类型化事件 + Sink
/// - tool.dart — Tool 接口 + Registry
/// - provider.dart — LLM Provider 接口 + DeepSeek 实现
/// - agent/ — Agent Loop + Session + Compose
/// - controller/ — 传输无关的会话驱动器
/// - memory/ — 四类记忆 + 文件存储 + MEMORY.md 索引
/// - skill/ — 技能加载器 + 索引 + 内置技能
/// - output_style/ — 输出风格系统（explanatory/learning/concise/socratic）
/// - evidence/ — 工具调用证据分类账本
/// - compact/ — 上下文压实（三档阈值）
library agent;

export 'message.dart';
export 'event.dart';
export 'tool.dart';
export 'provider.dart';
export 'agent/agent.dart';
export 'agent/session.dart';
export 'agent/compose.dart';
export 'agent/gate.dart';
export 'agent/hooks.dart';
export 'controller/controller.dart';
export 'memory/memory.dart';
export 'skill/skill.dart';
export 'output_style/style.dart';
export 'evidence/evidence.dart';
export 'compact/compact.dart';
export 'tools/zju_data_source.dart';
export 'tools/zju_courses.dart';
export 'tools/zju_scores.dart';
export 'tools/zju_classroom.dart';
export 'tools/zju_ecard.dart';
export 'tools/zju_todos.dart';
export 'tools/zju_exams.dart';
