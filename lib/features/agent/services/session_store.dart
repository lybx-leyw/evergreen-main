import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../../core/agent/agent/session.dart';
import '../../../core/log.dart';

/// Session 持久化——JSON 文件存储。
class SessionStore {
  late final String _dir;

  SessionStore._(this._dir);

  static Future<SessionStore> create() async {
    final appDir = await getApplicationSupportDirectory();
    final dir = p.join(appDir.path, 'agent_sessions');
    await Directory(dir).create(recursive: true);
    return SessionStore._(dir);
  }

  String _path(String id) => p.join(_dir, '$id.json');

  /// 保存会话。
  Future<void> save(Session session) async {
    try {
      await File(_path(session.id))
          .writeAsString(jsonEncode(session.toJson()));
    } catch (e) {
      Log().warn('SessionStore save failed', error: e);
    }
  }

  /// 加载单个会话。
  Session? load(String id) {
    try {
      final file = File(_path(id));
      if (!file.existsSync()) return null;
      final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      return Session.fromJson(data);
    } catch (e) {
      Log().warn('SessionStore load failed', error: e);
      return null;
    }
  }

  /// 列出所有会话（按更新时间倒序）。
  List<Session> listAll() {
    try {
      final dir = Directory(_dir);
      if (!dir.existsSync()) return [];
      return dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .map((f) {
        try {
          final data = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
          return Session.fromJson(data);
        } catch (_) {
          return null;
        }
      })
          .whereType<Session>()
          .toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } catch (e) {
      Log().warn('SessionStore listAll failed', error: e);
      return [];
    }
  }

  /// 删除会话。
  Future<void> delete(String id) async {
    try {
      final file = File(_path(id));
      if (await file.exists()) await file.delete();
    } catch (e) {
      Log().warn('SessionStore delete failed', error: e);
    }
  }
}
