import 'dart:convert';
import 'dart:io';

import 'package:evergreen_base/core/agent/ref/fileutil/atomicwrite.dart' as atomic;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('atomicWriteFile writes data', () async {
    final tmp = Directory.systemTemp.createTempSync('atomic-');
    try {
      final path = p.join(tmp.path, 'out.txt');
      await atomic.atomicWriteFile(path, utf8.encode('hello'), 0o644);
      expect(File(path).readAsStringSync(), 'hello');
    } finally {
      tmp.deleteSync(recursive: true);
    }
  });

  test('claimRename renames atomically', () async {
    final tmp = Directory.systemTemp.createTempSync('atomic-');
    try {
      final src = p.join(tmp.path, 'a.txt');
      final dst = p.join(tmp.path, 'b.txt');
      File(src).writeAsStringSync('x');
      await atomic.claimRename(src, dst);
      expect(File(dst).readAsStringSync(), 'x');
      expect(File(src).existsSync(), isFalse);
    } finally {
      tmp.deleteSync(recursive: true);
    }
  });
}
