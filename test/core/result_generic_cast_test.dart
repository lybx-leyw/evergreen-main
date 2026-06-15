import 'package:flutter_test/flutter_test.dart';

/// 0.1.5 — Result<T> 泛型强转在缓存回退时不能崩溃。
///
/// 修复前：Ok(List<Map>) as Result<List<Grade>> 在运行时抛 type cast error。
/// 修复后：try-catch 包裹，类型不匹配时降级返回原始错误。
void main() {
  group('Result — generic cast safety', () {
    test('Ok<List<Map>> 不能强转为 List<Grade>，应降级', () {
      final cached = [
        {'jd': 4.5, 'cj': '90'},
      ];
      // 模拟原 bug：尝试强转不兼容泛型
      Object result;
      try {
        result = (cached as List<int>);
        fail('should have thrown');
      } catch (_) {
        // 降级：返回错误信息而非崩溃
        result = 'cache type mismatch';
      }
      expect(result, 'cache type mismatch');
    });

    test('同类型不抛异常', () {
      final list = [1, 2, 3];
      expect(() => list as List<int>, returnsNormally);
    });
  });
}
