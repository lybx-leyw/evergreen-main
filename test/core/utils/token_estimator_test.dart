import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/core/utils/token_estimator.dart';

void main() {
  group('TokenEstimator.estimate', () {
    test('空字符串 → 0', () {
      expect(TokenEstimator.estimate(''), 0);
    });

    test('纯英文 ≈ 字符数 × 0.35', () {
      final tokens = TokenEstimator.estimate('hello world');
      // 11 chars × 0.35 ≈ 4
      expect(tokens, greaterThan(2));
      expect(tokens, lessThan(10));
    });

    test('纯中文 ≈ 字符数 × 1.5', () {
      final tokens = TokenEstimator.estimate('你好世界');
      // 4 chars × 1.5 = 6
      expect(tokens, greaterThan(4));
      expect(tokens, lessThan(12));
    });

    test('混合中英文', () {
      final tokens = TokenEstimator.estimate('hello 你好');
      // 6 ASCII × 0.35 ≈ 3 + 2 CJK × 1.5 = 3 → ~6
      expect(tokens, greaterThan(3));
      expect(tokens, lessThan(15));
    });
  });

  group('TokenEstimator.estimateConversation', () {
    test('空列表 → 0', () {
      expect(TokenEstimator.estimateConversation([]), 0);
    });

    test('单条消息含 role 开销', () {
      final tokens = TokenEstimator.estimateConversation([
        {'role': 'user', 'content': 'hello'},
      ]);
      // 4 (role overhead) + ASCII estimate
      expect(tokens, greaterThan(3));
    });
  });
}
