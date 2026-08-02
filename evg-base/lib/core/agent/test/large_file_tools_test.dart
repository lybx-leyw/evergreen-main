/// 大文件阅读工具测试：grep 上下文 / read_file 流式+1based / read_head /
/// read_tail / file_info。
///
/// 覆盖：
/// - grep 无 context（向后兼容）与有 context（分组+`>` 标记命中行）
/// - read_file offset 1-based 对齐 grep，且能流式分段读取 >100KB 大文件
/// - read_head / read_tail 只读头/尾 N 行
/// - file_info 返回大小、行数、是否二进制

library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:path/path.dart' as p;

import '../tools/grep.dart';
import '../tools/read_file.dart';
import '../tools/head_tail.dart';
import '../tools/file_info.dart';

void main() {
  late Directory tmp;
  late String ws;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lf_tools_');
    ws = tmp.path;
  });
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('GrepTool', () {
    test('无 context 仍返回命中行（向后兼容）', () async {
      File(p.join(ws, 'a.txt')).writeAsStringSync('foo\nBAR\nbaz\n');
      final out = await GrepTool(workspaceDir: ws)
          .execute({'pattern': 'BAR', 'path': 'a.txt'});
      expect(out, contains('`a.txt`:'));
      expect(out, contains('> L2: BAR')); // 命中行始终以 > 标记（即使无上下文）
    });

    test('context 返回命中行前后上下文并以 > 标记命中行', () async {
      final sb = StringBuffer();
      for (var i = 1; i <= 5; i++) sb.writeln('line$i');
      sb.writeln('MATCH_HERE');
      for (var i = 6; i <= 10; i++) sb.writeln('line$i');
      File(p.join(ws, 'b.txt')).writeAsStringSync(sb.toString());
      final out = await GrepTool(workspaceDir: ws).execute(
          {'pattern': 'MATCH_HERE', 'path': 'b.txt', 'context': 1});
      expect(out, contains('> L6: MATCH_HERE'));
      expect(out, contains('L5: line5')); // 前一行上下文
      expect(out, contains('L7: line6')); // 后一行上下文
    });

    test('context_before/context_after 可分别控制', () async {
      final sb = StringBuffer();
      for (var i = 1; i <= 10; i++) sb.writeln('n$i');
      File(p.join(ws, 'c.txt')).writeAsStringSync(sb.toString());
      final out = await GrepTool(workspaceDir: ws).execute({
        'pattern': 'n5',
        'path': 'c.txt',
        'context_before': 2,
        'context_after': 0,
      });
      expect(out, contains('> L5: n5'));
      expect(out, contains('L3: n3'));
      expect(out, contains('L4: n4'));
      expect(out, isNot(contains('L6: n6'))); // 之后无上下文
    });

    test('未命中返回提示', () async {
      File(p.join(ws, 'd.txt')).writeAsStringSync('aaa\nbbb\n');
      final out = await GrepTool(workspaceDir: ws)
          .execute({'pattern': 'zzz', 'path': 'd.txt'});
      expect(out, contains('找到匹配'));
    });
  });

  group('ReadFileTool', () {
    test('offset 为 1-based，与 grep 行号一致', () async {
      final sb = StringBuffer();
      for (var i = 1; i <= 5; i++) sb.writeln('line$i');
      File(p.join(ws, 'e.txt')).writeAsStringSync(sb.toString());
      final out = await ReadFileTool(workspaceDir: ws)
          .execute({'path': 'e.txt', 'offset': 3, 'limit': 1});
      expect(out, contains('line3'));
      expect(out, isNot(contains('line2')));
    });

    test('小文件整读仍可用', () async {
      File(p.join(ws, 'f.txt')).writeAsStringSync('one\ntwo\nthree\n');
      final out =
          await ReadFileTool(workspaceDir: ws).execute({'path': 'f.txt'});
      expect(out, contains('one'));
      expect(out, contains('three'));
    });

    test('无 offset 读 >100KB 大文件被拒', () async {
      final buf = StringBuffer();
      for (var i = 1; i <= 3000; i++) buf.writeln('LINE $i ' + 'x' * 100);
      File(p.join(ws, 'big.txt')).writeAsStringSync(buf.toString());
      final out =
          await ReadFileTool(workspaceDir: ws).execute({'path': 'big.txt'});
      expect(out, contains('文件过大'));
    });

    test('流式分段可读 >100KB 大文件任意位置', () async {
      final buf = StringBuffer();
      for (var i = 1; i <= 3000; i++) buf.writeln('LINE $i ' + 'x' * 100);
      File(p.join(ws, 'big.txt')).writeAsStringSync(buf.toString());
      final rf = ReadFileTool(workspaceDir: ws);
      final head =
          await rf.execute({'path': 'big.txt', 'offset': 1, 'limit': 1});
      expect(head, contains('LINE 1 '));
      final tail =
          await rf.execute({'path': 'big.txt', 'offset': 3000, 'limit': 1});
      expect(tail, contains('LINE 3000 '));
      // offset 超出文件行数 → 提示
      final over =
          await rf.execute({'path': 'big.txt', 'offset': 99999, 'limit': 1});
      expect(over, contains('超出文件行数'));
    });
  });

  group('ReadHead/TailTool', () {
    test('read_head 读文件头 N 行', () async {
      final sb = StringBuffer();
      for (var i = 1; i <= 20; i++) sb.writeln('row$i');
      File(p.join(ws, 'h.txt')).writeAsStringSync(sb.toString());
      final out = await ReadHeadTool(workspaceDir: ws)
          .execute({'path': 'h.txt', 'lines': 3});
      expect(out, contains('row1'));
      expect(out, contains('row3'));
      expect(out, isNot(contains('row4')));
    });

    test('read_tail 读文件尾 N 行', () async {
      final sb = StringBuffer();
      for (var i = 1; i <= 20; i++) sb.writeln('row$i');
      File(p.join(ws, 't.txt')).writeAsStringSync(sb.toString());
      final out = await ReadTailTool(workspaceDir: ws)
          .execute({'path': 't.txt', 'lines': 3});
      expect(out, contains('row18'));
      expect(out, contains('row20'));
      expect(out, isNot(contains('row17')));
    });

    test('二进制文件被拒绝', () async {
      File(p.join(ws, 'b.bin')).writeAsBytesSync([0, 1, 2, 3]);
      final out =
          await ReadHeadTool(workspaceDir: ws).execute({'path': 'b.bin'});
      expect(out, contains('二进制'));
    });
  });

  group('FileInfoTool', () {
    test('返回文本文件大小与行数', () async {
      final sb = StringBuffer();
      for (var i = 1; i <= 7; i++) sb.writeln('x$i');
      File(p.join(ws, 'info.txt')).writeAsStringSync(sb.toString());
      final out = await FileInfoTool(workspaceDir: ws)
          .execute({'path': 'info.txt'});
      expect(out, contains('文本文件'));
      expect(out, contains('7')); // 行数
      expect(out, contains('行数'));
    });

    test('识别二进制文件', () async {
      File(p.join(ws, 'b.bin')).writeAsBytesSync([0, 1, 2, 0, 3]);
      final out =
          await FileInfoTool(workspaceDir: ws).execute({'path': 'b.bin'});
      expect(out, contains('二进制'));
    });

    test('不存在的文件返回提示', () async {
      final out =
          await FileInfoTool(workspaceDir: ws).execute({'path': 'nope.txt'});
      expect(out, contains('文件不存在'));
    });
  });
}
