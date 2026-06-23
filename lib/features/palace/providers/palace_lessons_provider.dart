/// Palace 教训列表 Provider。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/palace/models/structured_lesson.dart';

/// 教训列表 Notifier。
class PalaceLessonsNotifier extends StateNotifier<List<StructuredLesson>> {
  PalaceLessonsNotifier() : super([]);

  /// 刷新列表（从磁盘加载所有教训）。
  void refresh() {
    // 目前教训存储在内存中（后续接入文件存储）
    // 此处保留接口——Phase 1 的教训随事件存储，不独立持久化
  }

  /// 添加一条教训（来自 CaptureResult）。
  void addLesson(StructuredLesson lesson) {
    state = [...state, lesson];
  }

  /// 更新教训（如确认草稿）。
  void updateLesson(StructuredLesson updated) {
    state = [
      for (final l in state)
        if (l.id == updated.id) updated else l,
    ];
  }

  /// 删除教训。
  void removeLesson(String id) {
    state = state.where((l) => l.id != id).toList();
  }

  /// 确认草稿 → 正式。
  void confirm(String lessonId) {
    state = [
      for (final l in state)
        if (l.id == lessonId)
          l.confirm()
        else
          l,
    ];
  }
}

final palaceLessonsProvider =
    StateNotifierProvider<PalaceLessonsNotifier, List<StructuredLesson>>((ref) {
  return PalaceLessonsNotifier();
});
