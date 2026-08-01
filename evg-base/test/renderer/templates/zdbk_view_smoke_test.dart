/// zdbk-modle 编译冒烟测试（v5P）。
///
/// 仅触发整个 zdbk_modle 模板的编译（含 [ZdbkView] + 5 个子页 + models + bindings 接线），
/// 确保 bindings 接入后子页仍能通过编译（flutter analyze 在子路径下有 package 解析假错，
/// 故以 flutter test 编译为准）。
library;
import 'package:evergreen_base/renderer/templates/zju_modle/zdbk/zdbk_view.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('zdbk_modle 模板可编译（含 5 子页 + models + bindings 接线）', () {
    // 仅验证符号可解析、整棵模板可被 Dart 编译器通过。
    expect(ZdbkView, isNotNull);
    expect(zdbkPageHeader, isNotNull);
    expect(zdbkSectionTitle, isNotNull);
  });
}
