/// 多画板数据层（Phase 2 · A21-A24）。
///
/// - [ScraperBoard]：画板模型（沙盒 = 独立任务）
/// - [BoardStore]：持久化（checkpoint 式原子写：temp + rename，重启恢复）
///
/// 隔离保证（A21）：每个画板是独立任务，日志/快照/会话/产物引用绝不交叉；
/// 同一画板内日志单快照 + 产物保留。
library scraper_board;

import 'dart:convert';
import 'dart:io';

// ═══════ 画板模型 ═══════

/// 画板模式（A23：画板内选模式；探索模式 Phase 4 落地）。
enum ScraperBoardMode {
  /// 定向抓取（现有流程）。
  capture,

  /// AI 探索（Phase 4）。
  explore,
}

/// 画板模型——一个独立任务的沙盒。
class ScraperBoard {
  final String id; // 唯一标识（uuid/时间戳）
  String name; // 画板名（如 "课程抓取"）
  ScraperBoardMode mode; // 模式

  /// 关联的会话 id 列表（双向绑定：画板 → 会话，一个画板可多个会话）。
  ///
  /// 空列表 = 孤儿画板（无绑定会话），加载时被过滤不显示。
  List<String> sessionIds;

  String? snapshotRef; // 日志快照引用（快照文件路径）
  final DateTime createdAt;
  DateTime updatedAt;

  ScraperBoard({
    required this.id,
    required this.name,
    this.mode = ScraperBoardMode.capture,
    List<String>? sessionIds,
    this.snapshotRef,
    required this.createdAt,
    required this.updatedAt,
  }) : sessionIds = sessionIds ?? [];

  /// 新建画板（自动生成 id / 时间戳）。
  factory ScraperBoard.create(String name,
      {ScraperBoardMode mode = ScraperBoardMode.capture,
      List<String>? sessionIds}) {
    final now = DateTime.now();
    return ScraperBoard(
      id: 'board_${_nextSeq()}',
      name: name,
      mode: mode,
      sessionIds: sessionIds,
      createdAt: now,
      updatedAt: now,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'mode': mode.name,
        if (sessionIds.isNotEmpty) 'sessionIds': sessionIds,
        if (snapshotRef != null) 'snapshotRef': snapshotRef,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory ScraperBoard.fromJson(Map<String, dynamic> json) {
    final ids = (json['sessionIds'] as List<dynamic>?)
            ?.whereType<String>()
            .toList() ??
        [];
    // 兼容旧单值 sessionId 字段（若有则并入）
    final legacyId = json['sessionId'] as String?;
    if (legacyId != null && legacyId.isNotEmpty && !ids.contains(legacyId)) {
      ids.add(legacyId);
    }
    return ScraperBoard(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '未命名画板',
      mode: ScraperBoardMode.values.asNameMap()[json['mode']] ??
          ScraperBoardMode.capture,
      sessionIds: ids,
      snapshotRef: json['snapshotRef'] as String?,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
              DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
              DateTime.now(),
    );
  }
}

int _boardSeq = 0;

/// 进程内递增序号（保证同进程内 id 唯一）。
String _nextSeq() {
  _boardSeq++;
  return '${DateTime.now().millisecondsSinceEpoch}_${_boardSeq.toString().padLeft(4, '0')}';
}

// ═══════ BoardStore ═══════

/// 画板持久化存储——checkpoint 式原子写（temp + rename）。
///
/// 布局：`<workspaceDir>/boards.json`（画板元数据列表）。
/// 每个画板的日志快照/会话按画板 id 独立文件（`<workspaceDir>/boards/<id>/`），
/// 保证任务绝不交叉（A21）。
class BoardStore {
  final String workspaceDir;
  final String _path;
  final String _boardsDir;

  BoardStore({required this.workspaceDir})
      : _path = '$workspaceDir/boards.json',
        _boardsDir = '$workspaceDir/boards';

  String get boardsPath => _path;
  String get boardsDir => _boardsDir;

  /// 画板专属目录（快照/会话分文件用）。
  String boardDir(String id) => '$_boardsDir/$id';

  /// 画板快照文件路径。
  String boardSnapshotPath(String id) => '${boardDir(id)}/snapshot.json';

  /// 画板会话文件路径（`<board>/session.json`，与 ScraperAIPanel 一致）。
  String boardSessionPath(String id) => '${boardDir(id)}/session.json';

  /// 读取某画板绑定的会话 id 列表（双向绑定：画板 → 会话）。
  ///
  /// 从 `<board>/session.json` 提取每条会话的 `id` 与 `boardId`；
  /// `boardId` 缺失或与画板不符的会话视为孤儿，不返回其 id。
  /// 文件缺失/损坏 → 空列表。
  List<String> loadBoardSessionIds(String boardId) {
    final file = File(boardSessionPath(boardId));
    if (!file.existsSync()) return [];
    try {
      final json = jsonDecode(file.readAsStringSync()) as List<dynamic>;
      return json
          .whereType<Map<String, dynamic>>()
          .where((s) {
            final b = s['boardId'];
            return b is String && b.isNotEmpty && b == boardId;
          })
          .map((s) => s['id'] as String? ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 加载全部画板（重启恢复 A24）。文件缺失/损坏 → 空列表（不崩溃）。
  List<ScraperBoard> load() {
    final file = File(_path);
    if (!file.existsSync()) return [];
    try {
      final json = jsonDecode(file.readAsStringSync()) as List<dynamic>;
      return json
          .whereType<Map<String, dynamic>>()
          .map(ScraperBoard.fromJson)
          .toList();
    } catch (e) {
      // 损坏：备份后返回空，避免反复崩溃
      try {
        file.copySync('$_path.corrupt_${DateTime.now().millisecondsSinceEpoch}');
      } catch (_) {}
      return [];
    }
  }

  /// 保存全部画板（原子写：temp + rename，读者只见旧或完整新文件）。
  Future<void> save(List<ScraperBoard> boards) async {
    final dir = Directory(_boardsDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final json = const JsonEncoder.withIndent('  ').convert(
      boards.map((b) => b.toJson()).toList(),
    );
    await _atomicWrite(_path, json);
  }

  /// 持久化单个画板的日志快照（A18/A21：快照按画板隔离）。
  Future<void> saveSnapshot(String boardId, List<Map<String, dynamic>> logs) async {
    final dir = Directory(boardDir(boardId));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final json = const JsonEncoder.withIndent('  ')
        .convert({'logs': logs, 'savedAt': DateTime.now().toIso8601String()});
    await _atomicWrite(boardSnapshotPath(boardId), json);
  }

  /// 读取画板快照。无/损坏 → 空列表。
  List<Map<String, dynamic>> loadSnapshot(String boardId) {
    final file = File(boardSnapshotPath(boardId));
    if (!file.existsSync()) return [];
    try {
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      return (json['logs'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 删除画板数据（含快照目录）。
  void deleteBoard(String id) {
    final dir = Directory(boardDir(id));
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }

  /// 原子写：写临时文件 → rename 覆盖（checkpoint 语义）。
  ///
  /// 启动/保存时清理同路径的过期 .tmp（上次崩溃残留），避免堆积。
  Future<void> _atomicWrite(String path, String content) async {
    final tmp = '$path.tmp';
    final tmpFile = File(tmp);
    // 清理上次崩溃可能残留的 tmp（若存在）
    if (tmpFile.existsSync()) {
      try {
        await tmpFile.delete();
      } catch (_) {}
    }
    await tmpFile.writeAsString(content, flush: true);
    // rename 覆盖：读者只见旧文件或完整新文件
    final target = File(path);
    if (target.existsSync()) {
      // Windows rename 不能覆盖已存在文件 → 先删旧再 rename
      await target.delete();
    }
    await tmpFile.rename(path);
  }
}
