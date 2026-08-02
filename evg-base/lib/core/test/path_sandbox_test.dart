/// 路径沙箱测试——覆盖 confine 返回绝对路径、沙箱内文件可被发现、越界拒绝。
///
/// 回归背景：`_canonical` 曾丢弃 POSIX 绝对路径的前导 `/`，导致 Linux/
/// Android 上 confine() 返回相对路径，被解析到进程 cwd → 工具报"路径不存在"
/// （Windows 上因盘符保持绝对而未暴露）。
library;

import 'dart:io';

import 'package:test/test.dart';

import '../utils/path_sandbox.dart';

void main() {
  group('PathSandbox', () {
    test('confine 返回绝对路径，沙箱内文件可被发现', () {
      final tmp = Directory.systemTemp.createTempSync('sandbox_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final ws = tmp.path;

      // 在沙箱内建一个真实文件
      final target = File('$ws${Platform.pathSeparator}a.txt')
        ..writeAsStringSync('x');

      final box = PathSandbox(ws);
      final safe = box.confine('a.txt');

      expect(safe, isNotNull);
      // 关键断言：必须是绝对路径（回归：POSIX 上曾丢失前导 / 变成相对路径）
      expect(File(safe!).isAbsolute, isTrue);
      // 相对路径解析到沙箱根后，确实能找到刚创建的文件
      expect(FileSystemEntity.typeSync(safe), FileSystemEntityType.file);
      expect(File(safe).existsSync(), isTrue);
      expect(File(safe).path, target.path);
    });

    test('相对路径与绝对路径均被限定在沙箱内', () {
      final tmp = Directory.systemTemp.createTempSync('sandbox_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final ws = tmp.path;

      final box = PathSandbox(ws);
      final nested = box.confine('sub${Platform.pathSeparator}b.txt');
      expect(nested, isNotNull);
      expect(File(nested!).isAbsolute, isTrue);
      expect(
        pContains(nested, ws),
        isTrue,
        reason: '返回的路径必须位于沙箱根目录内',
      );
    });

    test('越界路径返回 null', () {
      final tmp = Directory.systemTemp.createTempSync('sandbox_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final ws = tmp.path;

      final box = PathSandbox(ws);
      expect(box.confine('..'), isNull);
      expect(box.confine('..${Platform.pathSeparator}..'), isNull);
      final absEsc = ws.endsWith(Platform.pathSeparator)
          ? '${ws}..${Platform.pathSeparator}escape.txt'
          : '$ws${Platform.pathSeparator}..${Platform.pathSeparator}escape.txt';
      expect(box.confine(absEsc), isNull);
    });
  });
}

/// 判断 [inner] 是否位于 [outer] 目录内（按分隔符前缀判断，处理跨平台）。
bool pContains(String inner, String outer) {
  final norm = (String s) =>
      s.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
  final i = norm(inner);
  final o = norm(outer);
  return i == o || i.startsWith('$o/');
}
