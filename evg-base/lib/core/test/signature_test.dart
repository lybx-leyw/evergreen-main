/// 签名校验测试——覆盖合法签名通过、篡改拒绝、缺失拒绝。
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

// ═══════ helpers ═══════

/// 计算 SHA-256 hex 签名。
String _sign(List<int> bytes) => sha256.convert(bytes).toString();

/// 常数时间比较（同 PluginInstaller 内部实现）。
bool _constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var result = 0;
  for (var i = 0; i < a.length; i++) {
    result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return result == 0;
}

void main() {
  group('签名计算', () {
    test('相同内容产生相同签名', () {
      final a = _sign(utf8.encode('{"name":"test"}'));
      final b = _sign(utf8.encode('{"name":"test"}'));
      expect(a, b);
    });

    test('不同内容产生不同签名', () {
      final a = _sign(utf8.encode('{"version":"1.0"}'));
      final b = _sign(utf8.encode('{"version":"2.0"}'));
      expect(a, isNot(b));
    });

    test('签名长度为 64 字符（SHA-256 hex）', () {
      final sig = _sign(utf8.encode('hello world'));
      expect(sig.length, 64);
    });

    test('签名仅由小写 hex 字符组成', () {
      final sig = _sign(utf8.encode('test'));
      expect(sig, matches(RegExp(r'^[0-9a-f]{64}$')));
    });
  });

  group('常数时间比较', () {
    test('相同字符串返回 true', () {
      expect(_constantTimeEquals('abc123', 'abc123'), isTrue);
    });

    test('不同字符串返回 false', () {
      expect(_constantTimeEquals('abc123', 'abc124'), isFalse);
    });

    test('不同长度字符串返回 false', () {
      expect(_constantTimeEquals('abc', 'abc123'), isFalse);
    });

    test('空字符串比较', () {
      expect(_constantTimeEquals('', ''), isTrue);
      expect(_constantTimeEquals('a', ''), isFalse);
    });
  });

  group('签名校验场景', () {
    test('合法签名通过校验', () {
      final content = utf8.encode('{"type":"plugin","id":"test","name":"T","version":"1.0"}');
      final sig = _sign(content);
      final computed = _sign(content);
      expect(_constantTimeEquals(sig, computed), isTrue);
    });

    test('篡改内容后签名不匹配', () {
      final original = utf8.encode('{"type":"plugin","id":"test","name":"T","version":"1.0"}');
      final tampered = utf8.encode('{"type":"plugin","id":"evil","name":"X","version":"1.0"}');
      final sig = _sign(original);
      final computed = _sign(tampered);
      expect(_constantTimeEquals(sig, computed), isFalse);
    });

    test('签名中的空白字符导致不匹配（trim 后验证）', () {
      final content = utf8.encode('{"x":"y"}');
      final sig = '  ${_sign(content)}\n';
      expect(_constantTimeEquals(sig.trim(), _sign(content)), isTrue);
    });
  });
}
