/// Port of reasonix/internal/secrets/redact_test.go.
///
/// Translation notes:
/// - Go's `t.Setenv` cannot be reproduced portably in Dart's `Platform`
///   environment, so ProcessEnv tests are translated as `filterEnv` /
///   `registerCredentialEnvKeys` unit tests plus the public `processEnv`
///   contract documented in the implementation.
/// - The concurrent regexp-backtracking test is represented by repeated
///   idempotence checks on a large transcript.
library;

import 'package:evergreen_base/core/agent/ref/provider/message.dart'
    as provider;
import 'package:evergreen_base/core/agent/ref/secrets/redact.dart' as secrets;
import 'package:test/test.dart';

void main() {
  test('redact masks common secret shapes', () {
    const input = 'DEEPSEEK_API_KEY=sk-real-secret-value-123456\n'
        'Authorization: Bearer ghp_abcdefghijklmnopqrstuvwxyz\n'
        'token xoxb-123456789012-abcdefabcdef\n'
        'jwt eyJabc.def.ghi';
    final got = secrets.redact(input);
    for (final leaked in [
      'sk-real-secret-value-123456',
      'ghp_abcdefghijklmnopqrstuvwxyz',
      'xoxb-123456789012-abcdefabcdef',
      'eyJabc.def.ghi',
    ]) {
      expect(got, isNot(contains(leaked)));
    }
    expect(got, contains('DEEPSEEK_API_KEY=sk-rea'));
    expect(got, contains('Authorization: Bearer [redacted]'));
  });

  test('redact is idempotent on a large transcript', () {
    const secret = 'sk-real-secret-value-1234567890';
    final input = List.generate(
        2000,
        (i) => 'message $i payload=${'x' * (i % 31)} DEEPSEEK_API_KEY=$secret '
            'Authorization: Bearer $secret').join('\n');
    final once = secrets.redact(input);
    expect(once, isNot(contains(secret)));
    expect(secrets.redact(once), once);
  });

  test('redact masks JSON quoted keys', () {
    const input =
        'http 401: {"access_token":"sk-live-secret","x-api-key":"header-secret","password":"pw-secret"}';
    final got = secrets.redact(input);
    for (final leaked in ['sk-live-secret', 'header-secret', 'pw-secret']) {
      expect(got, isNot(contains(leaked)));
    }
    expect(got, contains('"access_token":"'));
    expect(got, contains('http 401'));
    expect(secrets.redact(got), got);
  });

  test('redact masks cookie header values', () {
    const input =
        'Cookie: session=cookie-secret\nSet-Cookie: sid=abc123def456; Path=/; HttpOnly';
    final got = secrets.redact(input);
    for (final leaked in ['cookie-secret', 'abc123def456']) {
      expect(got, isNot(contains(leaked)));
    }
    expect(got, contains('Cookie: session=[redacted]'));
    expect(got, contains('Set-Cookie: sid=[redacted]'));
    expect(got, contains('HttpOnly'));
    expect(secrets.redact(got), got);
  });

  test('redact masks non-bearer authorization schemes', () {
    const input = 'Authorization: Basic dXNlcjpwYXNzd29yZA==\n'
        'Proxy-Authorization: Digest username-hash-abcdef0123456789\n'
        'Authorization: dXNlcjpwYXNzd29yZC1yYXc=';
    final got = secrets.redact(input);
    for (final leaked in [
      'dXNlcjpwYXNzd29yZA==',
      'username-hash-abcdef0123456789',
      'dXNlcjpwYXNzd29yZC1yYXc=',
    ]) {
      expect(got, isNot(contains(leaked)));
    }
    expect(got, contains('Authorization: Basic [redacted]'));
    expect(got, contains('Digest [redacted]'));
    expect(got, contains('Authorization: [redacted]'));
    expect(secrets.redact(got), got);
  });

  test('redact masks URL user info', () {
    const input =
        'proxy request failed: https://proxy-user:pa@ss@proxy.example.com:8443/connect';
    final got = secrets.redact(input);
    for (final leaked in ['proxy-user', 'pa', 'ss']) {
      expect(got, isNot(contains(leaked)));
    }
    expect(got, contains('https://[redacted]@proxy.example.com:8443/connect'));
    expect(got, contains('proxy request failed'));
    expect(secrets.redact(got), got);
  });

  test('redact credentials for external errors', () {
    final cases = <String, List<String>>{
      'provider rejected api key: relaykey_abcdefghijklmn': [
        'relaykey_abcdefghijklmn'
      ],
      'provider rejected token ****ae54': ['ae54'],
      'upstream returned Authorization: Bearer abcdef0123456789abcdef': [
        'abcdef0123456789abcdef'
      ],
      'dial https://proxy-user:pa@ss@proxy.example.com:8443: refused': [
        'proxy-user',
        'pa',
        'ss',
      ],
      'provider rejected DEEPSEEK_API_KEY=sk-real-secret-value-123456': [
        'sk-real-secret-value-123456'
      ],
      'credential relayKeyAbcdefghijkl rejected': ['relayKeyAbcdefghijkl'],
    };
    for (final entry in cases.entries) {
      final got = secrets.redactError(entry.key);
      for (final leaked in entry.value) {
        expect(got, isNot(contains(leaked)), reason: 'for input: ${entry.key}');
      }
      expect(secrets.redactCredentials(got), got,
          reason: 'idempotent for input: ${entry.key}');
    }
    expect(secrets.redactError(null), isEmpty);
  });

  test('redact leaves working directory PWD alone', () {
    const input =
        'PWD=/home/user/project\nOLDPWD=/home/user\nDB_PWD=hunter2-swordfish-123';
    final got = secrets.redact(input);
    expect(got, contains('PWD=/home/user/project'));
    expect(got, contains('OLDPWD=/home/user'));
    expect(got, isNot(contains('hunter2-swordfish-123')));
  });

  test('env key sensitive', () {
    for (final key in [
      'DEEPSEEK_API_KEY',
      'GH_TOKEN',
      'AWS_SECRET_ACCESS_KEY',
      'DB_PASSWORD',
      'MYSQL_PWD',
      'NPM_TOKEN',
    ]) {
      expect(secrets.envKeySensitive(key), isTrue, reason: key);
    }
    for (final key in [
      'PWD',
      'OLDPWD',
      'PATH',
      'HOME',
      'LANG',
      'GOPATH',
      'TERM',
    ]) {
      expect(secrets.envKeySensitive(key), isFalse, reason: key);
    }
  });

  test('filter env drops sensitive keys', () {
    final got = secrets.filterEnv([
      'PATH=/usr/bin',
      'DEEPSEEK_API_KEY=sk-real-secret-value-123456',
      'GH_TOKEN=ghp_abcdefghijklmnopqrstuvwxyz',
      'PWD=/home/user/project',
      'HOME=/tmp/home',
    ]);
    final joined = got.join('\n');
    expect(joined, isNot(contains('DEEPSEEK_API_KEY')));
    expect(joined, isNot(contains('GH_TOKEN')));
    expect(joined, contains('PATH=/usr/bin'));
    expect(joined, contains('HOME=/tmp/home'));
    expect(joined, contains('PWD=/home/user/project'));
  });

  test('registered credential keys are always filtered', () {
    const key = 'REASONIX_TEST_CUSTOM_PROVIDER_CREDENTIAL';
    secrets.registerCredentialEnvKeys([key]);
    final got = secrets.filterEnv([
      '$key=opaque-provider-value',
      'REASONIX_TEST_BENIGN_ENV=visible',
      'DEEPSEEK_API_KEY=secret',
    ]);
    final joined = got.join('\n');
    expect(joined, isNot(contains(key)));
    expect(joined, isNot(contains('opaque-provider-value')));
    expect(joined, contains('REASONIX_TEST_BENIGN_ENV=visible'));
    expect(joined, isNot(contains('DEEPSEEK_API_KEY')));
  });

  test('redact messages does not mutate input', () {
    const secret = 'sk-real-secret-value-123456';
    final msgs = [
      provider.Message()
        ..role = provider.Role.assistant
        ..content = 'checking'
        ..toolCalls = [
          provider.ToolCall()
            ..id = 'call_1'
            ..name = 'bash'
            ..arguments = '{"command":"echo DEEPSEEK_API_KEY=$secret"}',
        ]
        ..memoryCitations = [
          provider.MemoryCitation()..note = 'token $secret',
        ],
      provider.Message()
        ..role = provider.Role.tool
        ..toolCallId = 'call_1'
        ..content = 'DEEPSEEK_API_KEY=$secret',
    ];

    final out = secrets.redactMessages(msgs);

    expect(out[0].toolCalls[0].arguments, isNot(contains(secret)));
    expect(out[1].content, isNot(contains(secret)));
    expect(msgs[0].toolCalls[0].arguments, contains(secret));
    expect(msgs[0].memoryCitations[0].note, contains(secret));
    expect(msgs[1].content, contains(secret));
  });
}
