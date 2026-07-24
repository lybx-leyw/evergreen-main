/// 书本持久化服务 — JSON 文件读写。
///
/// 存储位置：`.greenix/paper_reading/`
/// - innovation_notebook.json
/// - survey_notebook.json
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../paper_reading_models.dart';

class BookPersistence {
  static final _baseDir = Directory(
    '${Directory.current.path}/.greenix/paper_reading');

  static Directory get _dir => _baseDir;

  /// 确保存储目录存在。
  static Future<void> ensureDir() async {
    if (!await _dir.exists()) {
      await _dir.create(recursive: true);
    }
  }

  /// 保存笔记本数据。
  static Future<void> saveNotebook(NotebookData data) async {
    await ensureDir();
    final fileName = data.type == NotebookType.innovation
        ? 'innovation_notebook.json'
        : 'survey_notebook.json';
    final file = File('${_dir.path}/$fileName');
    await file.writeAsString(jsonEncode(data.toJson()));
  }

  /// 加载笔记本数据。不存在则返回空笔记本。
  static Future<NotebookData> loadNotebook(NotebookType type) async {
    await ensureDir();
    final fileName = type == NotebookType.innovation
        ? 'innovation_notebook.json'
        : 'survey_notebook.json';
    final file = File('${_dir.path}/$fileName');

    if (!await file.exists()) {
      return NotebookData(type: type);
    }

    try {
      final json = jsonDecode(await file.readAsString());
      return NotebookData.fromJson(json as Map<String, dynamic>);
    } catch (e) {
      debugPrint('[BookPersistence] parse error: $e');
      return NotebookData(type: type);
    }
  }
}
