/// show_file4u 工具测试：路径沙箱 / 存在性 / 空参数 / 目录拒绝。
///
/// 覆盖（任务 9.2 验收）：
/// - 工作区内相对路径 OK → 返回 `[ok: ...]` 且不含 error
/// - `../` 越界拒绝 → `[error: ...不在工作区内...]`
/// - 绝对路径越界拒绝
/// - 不存在的文件 → `[error: 文件不存在: <path>]`
/// - 目录路径 → `[error: ...是一个目录...]`
/// - 空参数 / 缺 file_path → `[error: 请提供 file_path...]`
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:path/path.dart' as p;

import '../tools/show_file4u.dart';

void main() {
  late Directory tmp;
  late String ws;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('show_file4u_');
    ws = tmp.path;
  });
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  ShowFile4uTool tool() => ShowFile4uTool(workspaceDir: ws);

  group('ShowFile4uTool — 路径沙箱', () {
    test('工作区内相对路径（含子目录）→ [ok]', () async {
      Directory(p.join(ws, 'sub')).createSync(recursive: true);
      File(p.join(ws, 'sub', 'notes.md')).writeAsStringSync('# hi');
      final out = await tool().execute({'file_path': 'sub/notes.md'});
      expect(out, startsWith('[ok:'));
      expect(out, contains('sub/notes.md'));
      expect(out, isNot(contains('error')));
    });

    test('工作区根下的相对路径 → [ok]', () async {
      File(p.join(ws, 'a.txt')).writeAsStringSync('x');
      final out = await tool().execute({'file_path': 'a.txt'});
      expect(out, startsWith('[ok:'));
      expect(out, contains('a.txt'));
    });

    test('`../` 越界拒绝', () async {
      final outside = File(p.join(tmp.parent.path, 'secret.txt'));
      outside.writeAsStringSync('s');
      final out = await tool().execute({'file_path': '../secret.txt'});
      expect(out, contains('[error:'));
      expect(out, contains('不在工作区内'));
      outside.deleteSync();
    });

    test('深层 `../../..` 越界拒绝', () async {
      final out = await tool().execute({'file_path': '../../../../etc/passwd'});
      expect(out, contains('[error:'));
      expect(out, contains('不在工作区内'));
    });

    test('绝对路径越界拒绝', () async {
      final out = await tool().execute({'file_path': '/etc/hostname'});
      expect(out, contains('[error:'));
      expect(out, contains('不在工作区内'));
    });

    test('Windows 反斜杠越界同样拒绝', () async {
      final out = await tool().execute({'file_path': r'..\..\secret'});
      expect(out, contains('[error:'));
      expect(out, contains('不在工作区内'));
    });
  });

  group('ShowFile4uTool — 存在性', () {
    test('不存在的文件 → [error: 文件不存在]', () async {
      final out = await tool().execute({'file_path': 'ghost.md'});
      expect(out, contains('[error:'));
      expect(out, contains('文件不存在: ghost.md'));
    });

    test('目录路径 → [error: 是一个目录]', () async {
      Directory(p.join(ws, 'folder')).createSync(recursive: true);
      final out = await tool().execute({'file_path': 'folder'});
      expect(out, contains('[error:'));
      expect(out, contains('是一个目录'));
    });
  });

  group('ShowFile4uTool — 参数', () {
    test('空参数 → [error: 请提供 file_path]', () async {
      final out = await tool().execute({});
      expect(out, contains('[error:'));
      expect(out, contains('请提供 file_path'));
    });

    test('file_path 为空白字符串 → 同空参数', () async {
      final out = await tool().execute({'file_path': '   '});
      expect(out, contains('[error:'));
      expect(out, contains('请提供 file_path'));
    });
  });
}
