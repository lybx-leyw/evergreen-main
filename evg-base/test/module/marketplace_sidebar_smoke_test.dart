// 编译冒烟测试：强制编译 app_shell.dart（侧边栏过滤）+ marketplace_slot.dart
// （改用共享 pluginStateProvider）+ nav_filter.dart + plugin_state_provider.dart，
// 验证 /marketplace 反馈修复（开关即时影响侧边栏）编译通过。
// 本环境 flutter analyze 报全局 false-error，编译裁定以 flutter test 为准。
import 'package:evergreen_base/renderer/app/app_shell.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/marketplace/marketplace_slot.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/marketplace/nav_filter.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/marketplace/plugin_state_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('侧边栏与 marketplace 组件编译通过且过滤函数可用', () {
    // 引用类型，强制参与编译
    expect(AppShell, isNotNull);
    expect(MarketplaceSlot, isNotNull);
    expect(pluginStateProvider, isNotNull);
    // 空输入下过滤函数保持纯函数语义
    expect(filterNavByPluginState(const [], {}), isEmpty);
  });
}
