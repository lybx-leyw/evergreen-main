/// Port of reasonix/internal/shellparse/bash_test.go.
///
/// The Go implementation uses a full Bash parser; this Dart port uses a
/// conservative static scanner. Test cases are translated directly, with the
/// same observable contracts.
library;

import 'package:evergreen_base/core/agent/ref/shellparse/bash.dart'
    as shellparse;
import 'package:test/test.dart';

void main() {
  test('static fields', () {
    final cases = <String, List<String>>{
      'git status --short': ['git', 'status', '--short'],
      r'''grep 'a|b' "file name.txt"''': ['grep', 'a|b', 'file name.txt'],
      r'''find . -name scratch \-delete''': [
        'find',
        '.',
        '-name',
        'scratch',
        '-delete'
      ],
    };
    for (final entry in cases.entries) {
      final (got, malformed) = shellparse.staticFields(entry.key);
      expect(malformed, isEmpty, reason: entry.key);
      expect(got, entry.value, reason: entry.key);
    }
    for (final command in [
      'git log >/dev/null',
      'git status && rm -rf /tmp/x',
      'git diff \$REV',
      'echo \$(touch out)',
      'GIT_EXTERNAL_DIFF=cat git diff',
      "echo 'unterminated",
    ]) {
      final (_, malformed) = shellparse.staticFields(command);
      expect(malformed, isNotEmpty, reason: command);
    }
  });

  test('parse static command policy', () {
    final got = shellparse.parseStaticCommand(
        "FOO=bar MESSAGE='hello world' go test ./...",
        const shellparse.StaticCommandPolicy(allowEnvAssignments: true));
    expect(got.env, ['FOO=bar', 'MESSAGE=hello world']);
    expect(got.argv, ['go', 'test', './...']);

    expect(
      () => shellparse.parseStaticCommand(
          'FOO=bar go test', const shellparse.StaticCommandPolicy()),
      throwsA(isA<shellparse.StaticRejectError>()),
    );
    expect(
      () => shellparse.parseStaticCommand('FOO=\$(whoami) go test',
          const shellparse.StaticCommandPolicy(allowEnvAssignments: true)),
      throwsA(isA<shellparse.StaticRejectError>()),
    );
    expect(
      () => shellparse.parseStaticCommand('go test ./... >out.txt',
          const shellparse.StaticCommandPolicy(allowEnvAssignments: true)),
      throwsA(isA<shellparse.StaticRejectError>()),
    );

    final merged = shellparse.parseStaticCommand('go test ./... 2>&1',
        const shellparse.StaticCommandPolicy(allowStderrToStdout: true));
    expect(merged.mergeStderr, isTrue);
    expect(merged.argv, ['go', 'test', './...']);

    expect(
      () => shellparse.parseStaticCommand('go test ./... 2>err.txt',
          const shellparse.StaticCommandPolicy(allowStderrToStdout: true)),
      throwsA(isA<shellparse.StaticRejectError>()),
    );

    expect(
        shellparse.staticFields('FOO=bar go test').$2, 'shell control syntax');
    expect(shellparse.staticFields('go test 2>&1').$2, 'shell control syntax');
  });

  test('contains unquoted glob', () {
    expect(shellparse.containsUnquotedGlob('rg TODO *.go'), isTrue);
    expect(shellparse.containsUnquotedGlob('rg TODO file?.go'), isTrue);
    expect(shellparse.containsUnquotedGlob('rg TODO [ab].go'), isTrue);
    expect(shellparse.containsUnquotedGlob(r'rg TODO "*.go"'), isFalse);
    expect(shellparse.containsUnquotedGlob(r"rg TODO '*.go'"), isFalse);
    expect(shellparse.containsUnquotedGlob(r'rg TODO \*.go'), isFalse);
    expect(shellparse.containsUnquotedGlob('git status --short'), isFalse);
  });

  test('analyze approval features marks non-static arguments as expansion', () {
    expect(
      shellparse.analyzeApprovalFeatures(r"printf '%s\n' {a,b}").$1.expansion,
      isTrue,
    );
    expect(
      shellparse.analyzeApprovalFeatures(r"printf '%s\n' @(a|b)").$1.expansion,
      isTrue,
    );
    expect(
      shellparse
          .analyzeApprovalFeatures(r"""printf '%s\n' "{a,b}" """)
          .$1
          .expansion,
      isFalse,
    );
    expect(
      shellparse
          .analyzeApprovalFeatures(r"""printf '%s\n' \{a,b\}""")
          .$1
          .expansion,
      isFalse,
    );
  });

  test('contains shell syntax', () {
    for (final command in [
      'git status && rm -rf /',
      'cat a | tee b',
      'git status > out.txt',
      'echo \$(rm x)',
      'echo \$HOME',
      'echo `whoami`',
      'sleep 1 &',
    ]) {
      expect(shellparse.containsShellSyntax(command), isTrue, reason: command);
    }
    for (final command in [
      'git status',
      r"grep 'a|b' file",
      r'''printf "%s\n" "a && b"''',
      r'''find . -name scratch \-delete''',
    ]) {
      expect(shellparse.containsShellSyntax(command), isFalse, reason: command);
    }
  });

  test('split top level', () {
    final cases = <String, (List<String>, bool, bool)>{
      'git status': (['git status'], false, true),
      'git add . && git commit -m "wip" && git push': (
        ['git add .', 'git commit -m "wip"', 'git push'],
        true,
        true,
      ),
      'cd /tmp; ls -la': (['cd /tmp', 'ls -la'], true, true),
      'git log --oneline | head -20': (
        ['git log --oneline', 'head -20'],
        true,
        true,
      ),
      'sleep 1 & echo done': (['sleep 1', 'echo done'], true, true),
      r"echo 'a && b' && ls": (["echo 'a && b'", 'ls'], true, true),
      'echo \$(git rev-parse HEAD; date) && ls': (
        ['echo \$(git rev-parse HEAD; date)', 'ls'],
        true,
        true,
      ),
      'diff <(git log -1 | head) <(git show HEAD | head) && ls': (
        [
          'diff <(git log -1 | head) <(git show HEAD | head)',
          'ls',
        ],
        true,
        true,
      ),
      '# comment\nshuf -i 1-30 -n 10 | sort -rn': (
        ['shuf -i 1-30 -n 10', 'sort -rn'],
        true,
        true,
      ),
      'cat <<EOF && ls\nline1\nEOF': (const [], false, false),
      'if true; then ls; fi && pwd': (const [], false, false),
    };
    for (final entry in cases.entries) {
      final (got, split, ok) = shellparse.splitTopLevel(entry.key);
      expect(ok, entry.value.$3, reason: entry.key);
      if (!ok) continue;
      expect(split, entry.value.$2, reason: entry.key);
      expect(got, entry.value.$1, reason: entry.key);
    }
  });

  test('has here doc', () {
    expect(
      shellparse
          .hasHereDoc("cat <<'EOF'\nnohup sleep 60 >/dev/null 2>&1 &\nEOF"),
      isTrue,
    );
  });
}
