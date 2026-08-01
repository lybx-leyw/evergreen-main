/// 主题草稿存储——greenix 工作区 JSON 持久化。
///
/// 草稿目录：`{greenixWorkspace}/theme-creator/drafts/<id>.json`
/// （greenixWorkspaceDir，与 scraper/html-creator 工作区同体系）。
/// 纯 Dart，无 Flutter 依赖（便于单测）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:evergreen_base/core/utils/greenix_path.dart';

import '../models/theme_draft.dart';

/// 主题草稿存储。
class ThemeDraftStore {
  /// 草稿根目录（可注入便于测试）。
  final String rootDir;

  ThemeDraftStore({String? rootDir})
      : rootDir = rootDir ?? greenixWorkspaceDir('theme-creator/drafts');

  Directory get _dir => Directory(rootDir);

  /// 列出全部草稿（按文件名排序，稳定）。
  List<ThemeDraft> list() {
    if (!_dir.existsSync()) return [];
    final drafts = <ThemeDraft>[];
    for (final f in _dir.listSync().whereType<File>()) {
      if (!f.path.endsWith('.json')) continue;
      final d = _read(f);
      if (d != null) drafts.add(d);
    }
    drafts.sort((a, b) => a.id.compareTo(b.id));
    return drafts;
  }

  /// 加载单个草稿；不存在/损坏返回 null。
  ThemeDraft? load(String id) {
    final f = _fileFor(id);
    if (!f.existsSync()) return null;
    return _read(f);
  }

  /// 保存草稿（覆盖）。
  void save(ThemeDraft draft) {
    _dir.createSync(recursive: true);
    _fileFor(draft.id).writeAsStringSync(
      jsonEncode(draft.toJson()),
      flush: true,
    );
  }

  /// 删除草稿。
  void delete(String id) {
    final f = _fileFor(id);
    if (f.existsSync()) f.deleteSync();
  }

  File _fileFor(String id) => File(p.join(_dir.path, '$id.json'));

  ThemeDraft? _read(File f) {
    try {
      final json = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      return ThemeDraft.fromJson(json);
    } catch (e) {
      stderr.writeln('[ThemeDraftStore] 读取草稿失败 ${f.path}: $e');
      return null;
    }
  }
}
