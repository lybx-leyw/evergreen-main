/// Palace 路径管理 —— `.greenix/palace/` 下的所有目录和文件路径。
///
/// 桌面端：基础目录为当前工作目录下的 `.greenix`。
/// Android/iOS：基础目录为 `<app documents>/.greenix`（由 `greenix_path.dart` 管理）。
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../../utils/greenix_path.dart' show greenixMemoriesDir;

/// Palace 数据存储的根目录——从 greenixMemoriesDir 反推 .greenix 基础路径。
String get _palaceBaseDir => p.join(p.dirname(greenixMemoriesDir), 'palace');

/// 事件文件目录（按年月分目录）。
String get palaceEventsDir => p.join(_palaceBaseDir, 'events');

/// 教训文件目录。
String get palaceLessonsDir => p.join(_palaceBaseDir, 'lessons');

/// 事件索引文件。
String get eventsByDateIndex => p.join(palaceEventsDir, 'EVENTS_BY_DATE.md');
String get eventsByTypeIndex => p.join(palaceEventsDir, 'EVENTS_BY_TYPE.md');
String get eventsByTagIndex  => p.join(palaceEventsDir, 'EVENTS_BY_TAG.md');

/// 教训索引文件。
String get lessonsIndex => p.join(palaceLessonsDir, 'LESSONS.md');

/// 给定事件 ID 和时间，返回事件文件路径。
/// 格式：`events/{YYYY}/{MM}/{id}.md`
String eventFilePath(String id, DateTime capturedAt) {
  final year = capturedAt.year.toString();
  final month = capturedAt.month.toString().padLeft(2, '0');
  return p.join(palaceEventsDir, year, month, '$id.md');
}

/// 给定教训 ID，返回教训文件路径。
/// 格式：`lessons/{id}.md`
String lessonFilePath(String id) {
  return p.join(palaceLessonsDir, '$id.md');
}

/// 确保所有 Palace 目录存在（首次使用时调用）。
void ensurePalaceDirs() {
  Directory(palaceEventsDir).createSync(recursive: true);
  Directory(palaceLessonsDir).createSync(recursive: true);
}
