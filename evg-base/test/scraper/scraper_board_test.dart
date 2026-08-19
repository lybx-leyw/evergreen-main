// scraper_board 多画板数据层测试（Phase 2 · A21-A24）。
//
// 覆盖：
// 1. 画板模型：create 自动 id/时间戳、toJson/fromJson 往返、mode
// 2. BoardStore：save/load 往返（重启恢复 A24）
// 3. 原子写：temp + rename（写后无 .tmp 残留）
// 4. 快照隔离：saveSnapshot/loadSnapshot 按画板分文件（A21 任务绝不交叉）
// 5. 损坏容错：load 遇损坏返回空 + 备份
import 'dart:convert';
import 'dart:io';

import 'package:evergreen_base/renderer/templates/scraper_modle/board/scraper_board.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmpDir;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('board_test_');
  });

  tearDown(() {
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
  });

  group('ScraperBoard 模型', () {
    test('create 自动生成 id 与时间戳', () {
      final b = ScraperBoard.create('课程抓取');
      expect(b.id, startsWith('board_'));
      expect(b.name, '课程抓取');
      expect(b.mode, ScraperBoardMode.capture);
      expect(b.createdAt.isBefore(DateTime.now()), isTrue);
      expect(b.updatedAt.isBefore(DateTime.now()), isTrue);
    });

    test('连续 create 的 id 不重复', () {
      final ids = {for (var i = 0; i < 50; i++) ScraperBoard.create('b$i').id};
      expect(ids.length, 50);
    });

    test('toJson/fromJson 往返（含 sessionIds 多会话）', () {
      final b = ScraperBoard.create('成绩查询', sessionIds: ['sess_1', 'sess_2'])
        ..snapshotRef = 'snap_1';
      final restored = ScraperBoard.fromJson(b.toJson());
      expect(restored.id, b.id);
      expect(restored.name, b.name);
      expect(restored.mode, b.mode);
      expect(restored.sessionIds, ['sess_1', 'sess_2']);
      expect(restored.snapshotRef, 'snap_1');
    });

    test('fromJson 兼容旧单值 sessionId 字段', () {
      final b = ScraperBoard.fromJson({
        'id': 'board_x',
        'name': '旧画板',
        'mode': 'capture',
        'sessionId': 'sess_legacy',
        'createdAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      });
      expect(b.sessionIds, ['sess_legacy']);
    });

    test('mode 可设为 explore（Phase 4 预留）', () {
      final b = ScraperBoard.create('探索', mode: ScraperBoardMode.explore);
      expect(b.mode, ScraperBoardMode.explore);
      expect(ScraperBoard.fromJson(b.toJson()).mode, ScraperBoardMode.explore);
    });
  });

  group('BoardStore 持久化', () {
    test('save/load 往返（重启恢复 A24）', () async {
      final store = BoardStore(workspaceDir: tmpDir.path);
      final boards = [
        ScraperBoard.create('画板A'),
        ScraperBoard.create('画板B', mode: ScraperBoardMode.explore),
      ];
      await store.save(boards);
      final loaded = store.load();
      expect(loaded.length, 2);
      expect(loaded[0].name, '画板A');
      expect(loaded[1].mode, ScraperBoardMode.explore);
      expect(loaded[0].id, boards[0].id);
    });

    test('无文件时 load 返回空列表', () {
      final store = BoardStore(workspaceDir: tmpDir.path);
      expect(store.load(), isEmpty);
    });

    test('原子写：保存后无 .tmp 残留', () async {
      final store = BoardStore(workspaceDir: tmpDir.path);
      await store.save([ScraperBoard.create('A')]);
      final tmps = tmpDir.listSync().where((e) => e.path.endsWith('.tmp'));
      expect(tmps, isEmpty);
      // 再次保存（覆盖路径）
      await store.save([
        ScraperBoard.create('A'),
        ScraperBoard.create('B'),
      ]);
      expect(File(store.boardsPath).existsSync(), isTrue);
      expect(tmpDir.listSync().where((e) => e.path.endsWith('.tmp')), isEmpty);
    });

    test('损坏文件 → load 返回空并备份', () {
      final store = BoardStore(workspaceDir: tmpDir.path);
      File(store.boardsPath).writeAsStringSync('{not valid json');
      final loaded = store.load();
      expect(loaded, isEmpty);
      // 有 .corrupt_ 备份
      final backups = tmpDir
          .listSync()
          .where((e) => e.path.contains('.corrupt_'));
      expect(backups, isNotEmpty);
    });

    test('loadBoardSessionIds：返回绑定该画板的会话 id，过滤孤儿', () async {
      final store = BoardStore(workspaceDir: tmpDir.path);
      final boardId = 'board_1';
      // 写 session.json：1 条绑定、1 条无 boardId（孤儿）、1 条绑定别的画板（孤儿）
      final dir = Directory(store.boardDir(boardId));
      dir.createSync(recursive: true);
      await File(store.boardSessionPath(boardId)).writeAsString(jsonEncode([
        {'id': 'sess_ok', 'name': 'a', 'boardId': boardId},
        {'id': 'sess_orphan_no_board', 'name': 'b'},
        {'id': 'sess_orphan_wrong', 'name': 'c', 'boardId': 'board_other'},
      ]));
      final ids = store.loadBoardSessionIds(boardId);
      expect(ids, ['sess_ok']);
    });

    test('loadBoardSessionIds：文件缺失 → 空列表（孤儿画板判据）', () {
      final store = BoardStore(workspaceDir: tmpDir.path);
      expect(store.loadBoardSessionIds('nonexistent'), isEmpty);
    });
  });

  group('快照隔离（A21）', () {
    test('不同画板快照互不交叉', () async {
      final store = BoardStore(workspaceDir: tmpDir.path);
      final b1 = ScraperBoard.create('画板1');
      final b2 = ScraperBoard.create('画板2');
      await store.saveSnapshot(b1.id, [
        {'method': 'GET', 'url': 'https://a.com/1'},
      ]);
      await store.saveSnapshot(b2.id, [
        {'method': 'GET', 'url': 'https://b.com/2'},
      ]);
      // 各读各的
      expect(store.loadSnapshot(b1.id).length, 1);
      expect(store.loadSnapshot(b1.id)[0]['url'], 'https://a.com/1');
      expect(store.loadSnapshot(b2.id)[0]['url'], 'https://b.com/2');
      // 文件路径按画板隔离
      expect(store.boardSnapshotPath(b1.id),
          isNot(store.boardSnapshotPath(b2.id)));
    });

    test('无快照 → 空列表', () {
      final store = BoardStore(workspaceDir: tmpDir.path);
      expect(store.loadSnapshot('nonexistent'), isEmpty);
    });

    test('deleteBoard 删除画板快照目录', () async {
      final store = BoardStore(workspaceDir: tmpDir.path);
      final b = ScraperBoard.create('待删');
      await store.saveSnapshot(b.id, [{'method': 'GET', 'url': 'x'}]);
      expect(Directory(store.boardDir(b.id)).existsSync(), isTrue);
      store.deleteBoard(b.id);
      expect(Directory(store.boardDir(b.id)).existsSync(), isFalse);
      expect(store.loadSnapshot(b.id), isEmpty);
    });
  });
}
