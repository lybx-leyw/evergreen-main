/// importToWorkspace 测试（Task 四决策 4.1）。
///
/// 覆盖：
/// - 文本文件复制成功 → 目标存在、内容一致、相对路径为文件名
/// - 二进制文件（含 NUL 字节）字节拷贝一致
/// - 同名冲突 → 时间戳/序号后缀，绝不覆盖原文件
/// - 连续两次导入同名 → 生成两个不同文件
/// - 源文件不存在 → fail
/// - 无效文件名 → fail
/// - 源文件已在工作区（源 == 目标）→ ok 且不重复复制
/// - 工作区目录不存在时自动创建
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:path/path.dart' as p;

import '../tools/workspace_import.dart';

void main() {
  late Directory tmp;
  late String ws;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('workspace_import_');
    ws = p.join(tmp.path, 'ws');
    Directory(ws).createSync(recursive: true);
  });
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('文本文件复制成功', () async {
    final src = File(p.join(tmp.path, 'note.md'));
    src.writeAsStringSync('# hello');
    final r = await importToWorkspace(sourcePath: src.path, workspaceDir: ws);
    expect(r.ok, isTrue);
    expect(r.error, isNull);
    expect(r.relativePath, 'note.md');
    expect(r.absolutePath, p.join(ws, 'note.md'));
    expect(File(r.absolutePath!).readAsStringSync(), '# hello');
  });

  test('二进制文件字节拷贝一致（含 NUL）', () async {
    final src = File(p.join(tmp.path, 'pic.png'));
    final bytes = List<int>.generate(256, (i) => i); // 0..255 含 NUL
    src.writeAsBytesSync(bytes);
    final r = await importToWorkspace(sourcePath: src.path, workspaceDir: ws);
    expect(r.ok, isTrue);
    expect(File(r.absolutePath!).readAsBytesSync(), bytes);
  });

  test('同名冲突 → 追加时间戳/序号后缀，不覆盖原文件', () async {
    File(p.join(ws, 'a.txt')).writeAsStringSync('original');
    final src = File(p.join(tmp.path, 'a.txt'));
    src.writeAsStringSync('new');
    final r = await importToWorkspace(sourcePath: src.path, workspaceDir: ws);
    expect(r.ok, isTrue);
    expect(r.relativePath, isNot('a.txt'));
    expect(r.relativePath, startsWith('a_'));
    expect(r.relativePath, endsWith('.txt'));
    expect(File(p.join(ws, 'a.txt')).readAsStringSync(), 'original');
    expect(File(r.absolutePath!).readAsStringSync(), 'new');
  });

  test('连续两次导入同名 → 生成两个不同文件', () async {
    final src = File(p.join(tmp.path, 'b.bin'));
    src.writeAsBytesSync([1, 2, 3]);
    final r1 = await importToWorkspace(sourcePath: src.path, workspaceDir: ws);
    final r2 = await importToWorkspace(sourcePath: src.path, workspaceDir: ws);
    expect(r1.ok, isTrue);
    expect(r2.ok, isTrue);
    expect(r1.relativePath, isNot(r2.relativePath));
    expect(File(r1.absolutePath!).existsSync(), isTrue);
    expect(File(r2.absolutePath!).existsSync(), isTrue);
  });

  test('源文件不存在 → fail', () async {
    final r = await importToWorkspace(
        sourcePath: p.join(tmp.path, 'missing.txt'), workspaceDir: ws);
    expect(r.ok, isFalse);
    expect(r.relativePath, isNull);
    expect(r.error, contains('源文件不存在'));
  });

  test('源文件是目录（如根目录）→ fail', () async {
    final r = await importToWorkspace(sourcePath: '/', workspaceDir: ws);
    expect(r.ok, isFalse);
    expect(r.error, contains('目录'));
  });

  test('源文件已在工作区（源 == 目标）→ ok 且不重复复制', () async {
    final inWs = File(p.join(ws, 'self.txt'))..writeAsStringSync('x');
    final r = await importToWorkspace(sourcePath: inWs.path, workspaceDir: ws);
    expect(r.ok, isTrue);
    expect(r.relativePath, 'self.txt');
    // 未被改名/复制成副本
    expect(File(p.join(ws, 'self.txt')).readAsStringSync(), 'x');
    final files = Directory(ws)
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .toList();
    expect(files, ['self.txt']);
  });

  test('工作区目录不存在时自动创建', () async {
    final ws2 = p.join(tmp.path, 'ws2');
    final src = File(p.join(tmp.path, 'c.txt'))..writeAsStringSync('c');
    final r = await importToWorkspace(sourcePath: src.path, workspaceDir: ws2);
    expect(r.ok, isTrue);
    expect(Directory(ws2).existsSync(), isTrue);
    expect(File(p.join(ws2, 'c.txt')).readAsStringSync(), 'c');
  });
}
