import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/core/utils/safe_parse.dart';

void main() {
  group('SafeParse.string', () {
    test('正常 String', () {
      expect(SafeParse.string('hello'), 'hello');
    });
    test('null → default', () {
      expect(SafeParse.string(null, defaultValue: 'fallback'), 'fallback');
    });
    test('int → toString()', () {
      expect(SafeParse.string(42), '42');
    });
  });

  group('SafeParse.double_', () {
    test('正常 double', () {
      expect(SafeParse.double_(3.14), 3.14);
    });
    test('int → double', () {
      expect(SafeParse.double_(42), 42.0);
    });
    test('String → parse', () {
      expect(SafeParse.double_('3.14'), 3.14);
    });
    test('null → 0.0', () {
      expect(SafeParse.double_(null), 0.0);
    });
    test('非法字符串 → 0.0', () {
      expect(SafeParse.double_('not_a_number'), 0.0);
    });
  });

  group('SafeParse.int_', () {
    test('正常 int', () {
      expect(SafeParse.int_(42), 42);
    });
    test('String → parse', () {
      expect(SafeParse.int_('99'), 99);
    });
    test('null → 0', () {
      expect(SafeParse.int_(null), 0);
    });
  });

  group('SafeParse.bool_', () {
    test('true', () {
      expect(SafeParse.bool_(true), true);
    });
    test('"true"', () {
      expect(SafeParse.bool_('true'), true);
    });
    test('"1"', () {
      expect(SafeParse.bool_('1'), true);
    });
    test('null → false', () {
      expect(SafeParse.bool_(null), false);
    });
  });

  group('SafeParse.dateTime', () {
    test('ISO 字符串', () {
      final dt = SafeParse.dateTime('2025-06-10T12:00:00');
      expect(dt, isNotNull);
      expect(dt!.year, 2025);
    });
    test('null → null', () {
      expect(SafeParse.dateTime(null), isNull);
    });
  });
}
