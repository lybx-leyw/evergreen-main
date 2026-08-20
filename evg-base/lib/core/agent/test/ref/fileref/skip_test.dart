/// Port of reasonix/internal/fileref/skip_test.go.
library;

import 'dart:io';

import 'package:evergreen_base/core/agent/ref/fileref/search.dart' as fileref;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('skip entry hides build output directories', () {
    for (final name in [
      'target',
      'build',
      'dist',
      '__pycache__',
      '.venv',
      'node_modules',
    ]) {
      expect(fileref.skipEntry(name, name, true), isTrue,
          reason: '$name is a build output and must stay out of file pickers');
    }
  });

  test('skip entry keeps source directories', () {
    for (final name in ['src', 'internal', 'docs', 'targets', 'buildkite']) {
      expect(fileref.skipEntry(name, name, true), isFalse,
          reason: '$name is not a build output and must remain browsable');
    }
  });

  test('skip entry ignores build names on files', () {
    expect(fileref.skipEntry('cmd/build', 'build', false), isFalse);
  });

  test('search skips generated class files', () {
    final root = Directory.systemTemp.createTempSync('fileref-skip-');
    addTearDown(() => root.deleteSync(recursive: true));
    File(p.join(root.path, 'src', 'main', 'java', 'App.java'))
        .createSync(recursive: true);
    File(p.join(root.path, 'target', 'classes', 'App.class'))
        .createSync(recursive: true);

    final got =
        fileref.search(root.path, 'app', 50).map((h) => h.path).toList();
    expect(got, isNot(contains('target/classes/App.class')));
    expect(got, isNotEmpty);
  });
}
