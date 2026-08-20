import 'dart:io';

import 'package:evergreen_base/core/agent/ref/fileref/search.dart' as fileref;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('search matches basename and excludes vendor dirs', () async {
    final tmp = Directory.systemTemp.createTempSync('fileref-');
    try {
      Directory(p.join(tmp.path, 'src')).createSync();
      File(p.join(tmp.path, 'src', 'plan.dart')).writeAsStringSync('');
      File(p.join(tmp.path, 'node_modules', 'x.js')).createSync(recursive: true);
      final hits = fileref.search(tmp.path, 'plan', 10);
      expect(hits.map((h) => h.path), contains('src/plan.dart'));
      expect(hits.map((h) => h.path), isNot(contains('node_modules/x.js')));
    } finally {
      tmp.deleteSync(recursive: true);
    }
  });

  test('short query rejected', () {
    expect(fileref.search('.', 'a', 10), isEmpty);
  });
}
