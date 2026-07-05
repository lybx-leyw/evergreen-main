/// 计划持久化存储 — 参照 SessionStore 模式。
///
/// 每个计划存为独立 JSON 文件在 plan_cache/plans/ 目录。
library;

import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/plan.dart';
import '../../../core/log.dart';

class PlanStore {
  final String _dir;

  PlanStore._(this._dir);

  static Future<PlanStore> create({String? storagePath}) async {
    final dirPath = storagePath ??
        p.join((await getApplicationSupportDirectory()).path, 'plan_cache', 'plans');
    final dir = Directory(dirPath);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return PlanStore._(dir.path);
  }

  String _path(String id) => p.join(_dir, '$id.json');

  Future<void> save(Plan plan) async {
    try {
      final file = File(_path(plan.id));
      await file.writeAsString(jsonEncode(plan.toJson()));
    } catch (e) {
      Log().warn('PlanStore save failed', error: e);
    }
  }

  Plan? load(String id) {
    try {
      final file = File(_path(id));
      if (!file.existsSync()) return null;
      return Plan.fromJson(jsonDecode(file.readAsStringSync()) as Map<String, dynamic>);
    } catch (e) {
      Log().warn('PlanStore load failed', error: e);
      return null;
    }
  }

  List<Plan> listAll() {
    try {
      final dir = Directory(_dir);
      if (!dir.existsSync()) return [];
      return dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json')).map((f) {
        try {
          return Plan.fromJson(jsonDecode(f.readAsStringSync()) as Map<String, dynamic>);
        } catch (_) {
          return null;
        }
      }).whereType<Plan>().toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } catch (e) {
      Log().warn('PlanStore listAll failed', error: e);
      return [];
    }
  }

  Future<void> delete(String id) async {
    try {
      final file = File(_path(id));
      if (file.existsSync()) await file.delete();
    } catch (e) {
      Log().warn('PlanStore delete failed', error: e);
    }
  }
}
