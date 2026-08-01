import 'dart:io';

import 'package:evergreen_base/core/agent/tools/grep.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  late GrepTool tool;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('grep_test_');
    tool = GrepTool(workspaceDir: tmp.path);
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('基本正则匹配返回命中行', () async {
    File('${tmp.path}/a.log').writeAsStringSync(
      'line1 ok\nline2 error occurred\nline3 warning\n',
    );
    final out = await tool.execute({'pattern': 'error'});
    expect(out, contains('> L2: line2 error occurred'));
    expect(out, contains('命中 1 处'));
  });

  test('file_filter 只搜匹配 glob 的文件', () async {
    File('${tmp.path}/data.json').writeAsStringSync('error in json\n');
    File('${tmp.path}/note.txt').writeAsStringSync('error in txt\n');
    final out = await tool.execute({
      'pattern': 'error',
      'file_filter': '*.json',
    });
    expect(out, contains('data.json'));
    expect(out, isNot(contains('note.txt')));
  });

  test('path 指定具体文件只搜该文件', () async {
    File('${tmp.path}/target.txt').writeAsStringSync('match here\n');
    File('${tmp.path}/other.txt').writeAsStringSync('match here too\n');
    final out = await tool.execute({
      'pattern': 'match',
      'path': 'target.txt',
    });
    expect(out, contains('target.txt'));
    expect(out, isNot(contains('other.txt')));
  });

  test('越界路径被拒绝', () async {
    final out = await tool.execute({
      'pattern': 'x',
      'path': '../../escape',
    });
    expect(out, contains('[越界拒绝]'));
  });

  test('max_matches 截断并提示上限', () async {
    final buf = StringBuffer();
    for (var i = 0; i < 10; i++) {
      buf.writeln('row $i: error code $i');
    }
    File('${tmp.path}/big.txt').writeAsStringSync(buf.toString());
    final out = await tool.execute({
      'pattern': 'error',
      'max_matches': 3,
    });
    expect(out, contains('命中 3 处'));
    expect(out, contains('已达 max_matches=3 上限'));
  });

  test('二进制文件被跳过不报错', () async {
    File('${tmp.path}/bin.dat').writeAsBytesSync(
      [0xFF, 0xFE, 0x00, 0x01, 0x02, 0x03],
    );
    final out = await tool.execute({'pattern': 'x'});
    expect(out, contains('找到匹配'));
    expect(out, contains('二进制文件'));
  });

  test('超单文件上限的文件被跳过并提示', () async {
    // 用极小 maxFileBytes 触发大文件跳过逻辑
    final smallTool = GrepTool(workspaceDir: tmp.path, maxFileBytes: 10);
    File('${tmp.path}/huge.txt').writeAsStringSync('a' * 100);
    final out = await smallTool.execute({'pattern': 'a'});
    expect(out, contains('大文件'));
  });

  test('非法正则返回错误提示', () async {
    final out = await tool.execute({'pattern': '('});
    expect(out, contains('[grep 错误]'));
  });

  test('缺少 pattern 返回提示', () async {
    final out = await tool.execute({});
    expect(out, contains('请提供 pattern'));
  });
}
