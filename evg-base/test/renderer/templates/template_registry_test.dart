// TemplateRegistry 接线测试：验证注册表由生成器产物提供、路由与回退行为正确。
// 注意：生成物内容随 release profile 变化（tool/gen_template_registry.dart），
// 本测试只断言"与 profile 无关"的契约：
//   1. v4 必须始终可用（任何 profile 的兜底模板）
//   2. 未知/缺失 template 必须回退到 v4
//   3. 注册表 Map 与 buildTemplateRegistry() 的 keys 一致
import 'package:flutter_test/flutter_test.dart';

import 'package:evergreen_base/renderer/templates/template.dart';
import 'package:evergreen_base/renderer/templates/template_registry.dart';
import 'package:evergreen_base/renderer/templates/generated/template_registry.g.dart';

void main() {
  test('注册表由生成函数提供，且 v4 始终可用', () {
    final reg = buildTemplateRegistry();
    expect(reg, isNotEmpty);
    expect(reg.containsKey('v4'), isTrue);
    expect(TemplateRegistry.resolve('v4'), isA<ModleRenderer>());
  });

  test('注册表 Map 与生成函数的 keys 完全一致', () {
    final reg = buildTemplateRegistry();
    // 内部私有字段无法直接访问，通过 resolve 行为间接断言：
    // 每个生成条目都能被 resolve 命中（非回退）。
    for (final name in reg.keys) {
      expect(TemplateRegistry.resolve(name).runtimeType, reg[name].runtimeType,
          reason: '模板 "$name" 应路由到其注册的渲染器');
    }
  });

  test('未知 / 缺失 template 回退 v4', () {
    expect(TemplateRegistry.resolve('no-such-template'),
        TemplateRegistry.resolve('v4'));
    expect(TemplateRegistry.resolve(null), TemplateRegistry.resolve('v4'));
    expect(TemplateRegistry.resolve(''), TemplateRegistry.resolve('v4'));
  });
}
