/// Palace 结构化教训模型。
///
/// 教训是经过提炼的、可演进的认知原则。从事件中提取草稿（version=0），
/// 用户确认后激活（version>=1），每次修订生成新版本并保留完整历史。
library;

import 'package:uuid/uuid.dart';

/// 一条结构化教训——可演进的行为/认知原则。
class StructuredLesson {
  /// UUID v4 唯一标识。
  final String id;

  /// 核心原则（一句话概括）。
  final String corePrinciple;

  /// 详细阐述。
  final String elaboration;

  /// 溯源链——指向产生此教训的原始意识事件 ID。
  final List<String> sourceEventIds;

  /// 此教训在什么条件下适用。
  final List<ApplicabilityCondition> conditions;

  /// 反例记录——在哪些情况下此教训不成立。
  final List<CounterExample> counterExamples;

  /// 版本号（0=AI 草稿，1=用户确认，2+=修订）。
  final int version;

  /// 修订历史（按时间升序）。
  final List<LessonRevision> revisionHistory;

  const StructuredLesson({
    required this.id,
    required this.corePrinciple,
    required this.elaboration,
    this.sourceEventIds = const [],
    this.conditions = const [],
    this.counterExamples = const [],
    this.version = 0,
    this.revisionHistory = const [],
  });

  static final _uuid = const Uuid();

  /// 创建 AI 生成的草稿教训（version=0）。
  factory StructuredLesson.draft({
    required String corePrinciple,
    required String elaboration,
    List<String> sourceEventIds = const [],
  }) {
    return StructuredLesson(
      id: _uuid.v4(),
      corePrinciple: corePrinciple,
      elaboration: elaboration,
      sourceEventIds: sourceEventIds,
      version: 0,
    );
  }

  /// 返回此教训的显示标题。
  String get title => corePrinciple.length > 80
      ? '${corePrinciple.substring(0, 80)}...'
      : corePrinciple;

  /// 草稿是否已被用户确认。
  bool get isConfirmed => version >= 1;

  /// 确认草稿 → version 0→1。
  StructuredLesson confirm() {
    final revision = LessonRevision(
      version: 1,
      revisedAt: DateTime.now(),
      changeDescription: '用户确认此教训',
    );
    return StructuredLesson(
      id: id,
      corePrinciple: corePrinciple,
      elaboration: elaboration,
      sourceEventIds: sourceEventIds,
      conditions: conditions,
      counterExamples: counterExamples,
      version: 1,
      revisionHistory: [...revisionHistory, revision],
    );
  }

  /// 修订教训——生成新版本。
  StructuredLesson revise({
    String? newPrinciple,
    String? newElaboration,
    String? changeDescription,
  }) {
    final newVersion = version + 1;
    final revision = LessonRevision(
      version: newVersion,
      revisedAt: DateTime.now(),
      changeDescription: changeDescription ?? '用户修订',
      previousCorePrinciple: newPrinciple != null ? corePrinciple : null,
    );
    return StructuredLesson(
      id: id,
      corePrinciple: newPrinciple ?? corePrinciple,
      elaboration: newElaboration ?? elaboration,
      sourceEventIds: sourceEventIds,
      conditions: conditions,
      counterExamples: counterExamples,
      version: newVersion,
      revisionHistory: [...revisionHistory, revision],
    );
  }

  /// 添加适用条件。
  StructuredLesson addCondition(ApplicabilityCondition condition) {
    return StructuredLesson(
      id: id,
      corePrinciple: corePrinciple,
      elaboration: elaboration,
      sourceEventIds: sourceEventIds,
      conditions: [...conditions, condition],
      counterExamples: counterExamples,
      version: version,
      revisionHistory: revisionHistory,
    );
  }

  /// 添加反例。
  StructuredLesson addCounterExample(CounterExample example) {
    return StructuredLesson(
      id: id,
      corePrinciple: corePrinciple,
      elaboration: elaboration,
      sourceEventIds: sourceEventIds,
      conditions: conditions,
      counterExamples: [...counterExamples, example],
      version: version,
      revisionHistory: revisionHistory,
    );
  }

  @override
  String toString() => 'StructuredLesson($id, v$version, "$title")';
}

/// 适用条件——"当……时，此教训成立"。
class ApplicabilityCondition {
  /// 条件描述（如"当你需要深度思考时"）。
  final String condition;

  /// 置信度 0.0 ~ 1.0。
  final double confidence;

  /// 支持此条件的事件 ID 列表。
  final List<String> supportingEventIds;

  const ApplicabilityCondition({
    required this.condition,
    this.confidence = 1.0,
    this.supportingEventIds = const [],
  });
}

/// 反例——"但在……情况下，此教训不成立"。
class CounterExample {
  /// 反例描述。
  final String description;

  /// 来源事件 ID（可选）。
  final String? sourceEventId;

  /// 记录时间。
  final DateTime recordedAt;

  const CounterExample({
    required this.description,
    this.sourceEventId,
    required this.recordedAt,
  });
}

/// 教训修订记录——一条版本变更。
class LessonRevision {
  /// 修订后的版本号。
  final int version;

  /// 修订时间。
  final DateTime revisedAt;

  /// 修订原因/描述。
  final String changeDescription;

  /// 如果核心原则被修改，记录修改前的文本。
  final String? previousCorePrinciple;

  const LessonRevision({
    required this.version,
    required this.revisedAt,
    required this.changeDescription,
    this.previousCorePrinciple,
  });
}
