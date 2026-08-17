/// 路由重定向回归测试。
///
/// 背景：三模式视图重构后，GoRouter 缺失两处接线——
/// 1. `/dev-hub` 路由从未注册（mode_rail 点击插件入口 context.go('/dev-hub') 会 404）；
/// 2. `/` 无 redirect，首屏始终停在 _HomePlaceholder，不按模式跳默认视图。
///
/// 本测试直接验证 defaultRouteForMode 的语义（redirect 逻辑复用该函数）：
/// AI 视图 '/' → /ai-assistant；开发者视图 '/' → /dev-hub；插件视图 → 第一个可见插件。
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/core/module/module_registry.dart';
import 'package:evergreen_base/renderer/app/app_mode.dart';
import 'package:flutter_test/flutter_test.dart';

ModuleDescriptor _mod(String id, String name, String route) => ModuleDescriptor(
      id: id,
      name: name,
      route: route,
      icon: 0xe000,
      nav: NavObjectDescriptor(
        sidebar: SidebarDescriptor(section: '主功能', order: 10),
      ),
    );

void main() {
  test('defaultRouteForMode：ai → /ai-assistant（存在时）', () {
    final r = ModuleRegistry();
    r.registerAll([_mod('ai-assistant', 'AI 助手', '/ai-assistant')]);
    r.seal();
    expect(
      defaultRouteForMode(mode: AppMode.ai, registry: r),
      '/ai-assistant',
    );
  });

  test('defaultRouteForMode：ai 未安装 → null（回退欢迎页）', () {
    final r = ModuleRegistry();
    r.registerAll([_mod('settings', '设置', '/settings')]);
    r.seal();
    expect(defaultRouteForMode(mode: AppMode.ai, registry: r), isNull);
  });

  test('defaultRouteForMode：developer → /dev-hub（无条件）', () {
    final r = ModuleRegistry();
    r.seal();
    expect(
      defaultRouteForMode(mode: AppMode.developer, registry: r),
      '/dev-hub',
    );
  });

  test('defaultRouteForMode：plugins → 侧栏第一个可见插件', () {
    final r = ModuleRegistry();
    r.registerAll([
      _mod('settings', '设置', '/settings'),
      _mod('pdf_translate', 'PDF 翻译', '/pdf-translate'),
    ]);
    r.seal();
    expect(
      defaultRouteForMode(mode: AppMode.plugins, registry: r),
      '/settings',
    );
  });
}
