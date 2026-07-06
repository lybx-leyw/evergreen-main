/// FileSessionStore — SessionStoreInterface 的 JSON 文件实现。
///
/// 存储路径: `.greenix/sessions/{id}.json`
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as p;

import 'package:evergreen_base/core/agent/agent.dart' as agent;
import 'package:evergreen_base/core/agent/session_manager.dart';

/// 基于 JSON 文件的 Session 持久化存储。
class FileSessionStore implements SessionStoreInterface {
  final String _dir;

  FileSessionStore(this._dir) {
    Directory(_dir).createSync(recursive: true);
  }

  String _path(String id) => p.join(_dir, '$id.json');

  @override
  Future<void> save(agent.Session session) async {
    try {
      final file = File(_path(session.id));
      final json = jsonEncode(session.toJson());
      debugPrint('[FileSessionStore] save id=${session.id} msgs=${session.messages.length} path=${file.path}');
      await file.writeAsString(json);
      debugPrint('[FileSessionStore] save OK for id=${session.id}');
    } catch (e, st) {
      debugPrint('[FileSessionStore] save FAILED for id=${session.id}: $e\n$st');
      stderr.writeln('[FileSessionStore] save failed: $e');
    }
  }

  @override
  agent.Session? load(String id) {
    try {
      final file = File(_path(id));
      if (!file.existsSync()) return null;
      final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      return agent.Session.fromJson(data);
    } catch (e) {
      stderr.writeln('[FileSessionStore] load failed: $e');
      return null;
    }
  }

  @override
  Future<void> delete(String id) async {
    try {
      final file = File(_path(id));
      if (await file.exists()) await file.delete();
    } catch (e) {
      stderr.writeln('[FileSessionStore] delete failed: $e');
    }
  }

  @override
  List<agent.Session> listAll() {
    try {
      final dir = Directory(_dir);
      if (!dir.existsSync()) return [];
      final sessions = <agent.Session>[];
      for (final entity in dir.listSync()) {
        if (entity is! File || !entity.path.endsWith('.json')) continue;
        try {
          final data = jsonDecode(entity.readAsStringSync()) as Map<String, dynamic>;
          final session = agent.Session.fromJson(data);
          if (session.id.isNotEmpty) sessions.add(session);
        } catch (_) {
          // 跳过损坏的文件
        }
      }
      sessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return sessions;
    } catch (e) {
      stderr.writeln('[FileSessionStore] listAll failed: $e');
      return [];
    }
  }
}
