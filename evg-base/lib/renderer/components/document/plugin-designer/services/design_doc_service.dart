/// 设计文档持久化服务 —— 设计文档的读取/保存/自动备份。
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/design_document.dart';

/// 设计文档持久化服务。
///
/// 文件命名：`plugins/<pluginId>/design/design_doc.json`
class DesignDocService {
  final String _pluginsDir;

  DesignDocService(this._pluginsDir);

  /// 获取设计文档保存路径。
  String _docPath(String pluginId) {
    return p.join(_pluginsDir, pluginId, 'design', 'design_doc.json');
  }

  /// 保存设计文档。
  Future<void> save(DesignDocument doc) async {
    final file = File(_docPath(doc.pluginId));
    final dir = file.parent;
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final json = jsonEncode(doc.toJson());
    await file.writeAsString(json);
  }

  /// 读取设计文档。
  Future<DesignDocument?> load(String pluginId) async {
    final file = File(_docPath(pluginId));
    if (!await file.exists()) return null;
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is Map<String, dynamic>) {
        return DesignDocument.fromJson(json);
      }
    } catch (_) {
      // 文件损坏，返回 null
    }
    return null;
  }

  /// 删除设计文档。
  Future<void> delete(String pluginId) async {
    final file = File(_docPath(pluginId));
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// 列出所有已保存的设计文档的插件 ID。
  Future<List<String>> listPluginIds() async {
    final dir = Directory(_pluginsDir);
    if (!await dir.exists()) return [];
    final ids = <String>[];
    await for (final entity in dir.list()) {
      if (entity is Directory) {
        final docFile =
            File(p.join(entity.path, 'design', 'design_doc.json'));
        if (await docFile.exists()) {
          ids.add(p.basename(entity.path));
        }
      }
    }
    return ids;
  }

  /// 检查设计文档是否存在。
  Future<bool> exists(String pluginId) async {
    return await File(_docPath(pluginId)).exists();
  }
}
