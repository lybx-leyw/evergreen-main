/// EvergreenApp 编译冒烟测试。
///
/// 验证 EvergreenApp 可编译（含完整依赖图），非计数器示例。
library;

import 'package:evergreen_base/app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('EvergreenApp 编译冒烟', () {
    // 仅触发 EvergreenApp 类型编译（含 app.dart 完整依赖图），
    // 不 pumpWidget（避免 Provider/SharedPreferences 测试环境挂起）。
    expect(EvergreenApp, isNotNull);
  });
}
