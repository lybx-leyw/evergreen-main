import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/core/utils/gpa_calculator.dart';
import 'package:evergreen_multi_tools/core/models/grade.dart';

Grade _g({
  String id = 'CS101',
  String name = '测试课程',
  double credit = 3.0,
  String original = '90',
  double fivePoint = 4.0,
  FivePointSource source = FivePointSource.fallback,
}) {
  return Grade(
    id: id, name: name, credit: credit,
    original: original, fivePoint: fivePoint,
    fivePointSource: source,
  );
}

void main() {
  group('GpaCalculator.calculateGpa', () {
    test('空列表 → 全零', () {
      final r = GpaCalculator.calculateGpa([]);
      expect(r.fivePoint, 0.0);
      expect(r.fourPoint, 0.0);
      expect(r.earnedCredits, 0.0);
    });

    test('单门课程', () {
      final r = GpaCalculator.calculateGpa([_g(credit: 4.0, fivePoint: 4.0)]);
      expect(r.fivePoint, closeTo(4.0, 0.01));
      expect(r.earnedCredits, 4.0);
    });

    test('全部排除 → 全零', () {
      final excluded = _g(original: '弃修', credit: 3.0, fivePoint: 0.0);
      final r = GpaCalculator.calculateGpa([excluded]);
      expect(r.fivePoint, 0.0);
      expect(r.earnedCredits, 0.0);
    });

    test('混合包含/排除', () {
      final r = GpaCalculator.calculateGpa([
        _g(id: 'A', credit: 4.0, fivePoint: 4.0),
        _g(id: 'B', credit: 2.0, fivePoint: 2.0, original: '弃修'),
      ]);
      // A: earnedCredit = 4.0 (未被排除), B: earnedCredit = 0 (弃修)
      expect(r.fivePoint, closeTo(4.0, 0.01));
      expect(r.earnedCredits, closeTo(4.0, 0.01));
    });
  });
}
