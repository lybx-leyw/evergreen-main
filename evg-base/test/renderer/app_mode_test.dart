/// 三模式视图——AppMode 编码 / 模式过滤 / 默认路由 纯逻辑测试。
///
/// 不挂载 widget、不碰 Provider（避免测试环境挂死），只锁定：
/// 1. 持久化编解码往返与容错；
/// 2. filterNavByAppMode：4 个特殊插件被排除、空 section 整体移除；
/// 3. defaultRouteForMode：三个模式各自的 '/' 目标（含插件状态过滤链）。
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/core/module/module_registry.dart';
import 'package:evergreen_base/core/module/sidebar_section.dart';
import 'package:evergreen_base/renderer/app/app_mode.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/services/plugin_state_service.dart';
import 'package:flutter_test/flutter_test.dart';

ModuleDescriptor _mod(
  String id,
  String name,
  String route,
  String section, {
  int order = 10,
  int sectionOrder = 50,
}) =>
    ModuleDescriptor(
      id: id,
      name: name,
      route: route,
      icon: 0xe000,
      nav: NavObjectDescriptor(
        sidebar: SidebarDescriptor(
          section: section,
          sectionOrder: sectionOrder,
          order: order,
        ),
      ),
    );

PluginStateRecord _rec(String id, {bool enabled = true, bool sidebarVisible = true}) =>
    PluginStateRecord(
      pluginId: id,
      enabled: enabled,
      sidebarVisible: sidebarVisible,
      installedAt: DateTime(2026, 1, 1),
      lastUsedAt: DateTime(2026, 1, 1),
    );

void main() {
  group('AppMode 编码', () {
    test('appModeFromString 三值映射 + 未知容错', () {
      expect(appModeFromString('ai'), AppMode.ai);
      expect(appModeFromString('developer'), AppMode.developer);
      expect(appModeFromString('plugins'), AppMode.plugins);
      expect(appModeFromString(null), isNull);
      expect(appModeFromString(''), isNull);
      expect(appModeFromString('garbage'), isNull);
    });

    test('appModeToString 往返一致', () {
      for (final m in AppMode.values) {
        expect(appModeFromString(appModeToString(m)), m);
      }
    });

    test('appModeLabel 文案', () {
      expect(appModeLabel(AppMode.ai), 'AI 视图');
      expect(appModeLabel(AppMode.developer), '开发者模式');
      expect(appModeLabel(AppMode.plugins), '插件视图');
    });
  });

  group('filterNavByAppMode / filterNavFlatByAppMode', () {
    final groups = <(SidebarSection, List<NavEntry>)>[
      (
        const SidebarSection('主功能', order: 10),
        _entries(['ai-assistant', 'theme-creator', 'demo-plugin']),
      ),
      (
        const SidebarSection('系统', order: 20),
        _entries(['settings', 'html-creator']),
      ),
      (
        const SidebarSection('仅特殊', order: 30),
        _entries(['scraper']),
      ),
    ];

    test('4 个特殊插件被排除，空 section 整体移除', () {
      final out = filterNavByAppMode(groups);
      final flat = out.expand((g) => g.$2).map((e) => e.moduleId).toList();
      expect(flat, ['demo-plugin', 'settings']);
      expect(out.length, 2, reason: '「仅特殊」section 应被移除');
    });

    test('扁平过滤一致', () {
      final flat = filterNavFlatByAppMode(
          groups.expand((g) => g.$2).toList());
      expect(flat.map((e) => e.moduleId).toList(),
          ['demo-plugin', 'settings']);
    });
  });

  group('defaultRouteForMode', () {
    ModuleRegistry _sealed(List<ModuleDescriptor> mods) {
      final r = ModuleRegistry();
      r.registerAll(mods);
      r.seal();
      return r;
    }

    test('ai 模式 → /ai-assistant；未安装 → null', () {
      final withAi = _sealed([
        _mod('ai-assistant', 'AI 助手', '/ai-assistant', '主功能'),
      ]);
      expect(
        defaultRouteForMode(
            mode: AppMode.ai, registry: withAi),
        '/ai-assistant',
      );
      final withoutAi = _sealed([
        _mod('demo-plugin', '演示插件', '/demo-plugin', '主功能'),
      ]);
      expect(
        defaultRouteForMode(
            mode: AppMode.ai, registry: withoutAi),
        isNull,
      );
    });

    test('developer 模式 → /dev-hub（无条件）', () {
      final empty = _sealed([]);
      expect(
        defaultRouteForMode(
            mode: AppMode.developer, registry: empty),
        '/dev-hub',
      );
    });

    test('plugins 模式 → 侧栏第一个可见插件（特殊插件不计入）', () {
      final r = _sealed([
        _mod('ai-assistant', 'AI 助手', '/ai-assistant', '主功能',
            order: 1, sectionOrder: 10),
        _mod('theme-creator', '主题创作中心', '/theme-creator', '主功能',
            order: 2, sectionOrder: 10),
        _mod('demo-plugin', '演示插件', '/demo-plugin', '主功能',
            order: 3, sectionOrder: 10),
        _mod('settings', '设置', '/settings', '系统',
            order: 10, sectionOrder: 20),
      ]);
      expect(
        defaultRouteForMode(mode: AppMode.plugins, registry: r),
        '/demo-plugin',
        reason: '主功能 section 中特殊插件被排除后，第一个可见项是 demo-plugin',
      );
    });

    test('plugins 模式 + 插件状态过滤：停用插件被跳过', () {
      final r = _sealed([
        _mod('demo-plugin', '演示插件', '/demo-plugin', '主功能',
            sectionOrder: 10),
        _mod('settings', '设置', '/settings', '系统', sectionOrder: 20),
      ]);
      expect(
        defaultRouteForMode(
          mode: AppMode.plugins,
          registry: r,
          pluginStates: {'demo-plugin': _rec('demo-plugin', enabled: false)},
        ),
        '/settings',
      );
      expect(
        defaultRouteForMode(
          mode: AppMode.plugins,
          registry: r,
          pluginStates: {
            'demo-plugin': _rec('demo-plugin', enabled: false),
            'settings': _rec('settings', enabled: false),
          },
        ),
        isNull,
        reason: '全部隐藏 → 无目标，回退欢迎占位页',
      );
    });
  });
}

List<NavEntry> _entries(List<String> ids) => [
      for (final id in ids)
        NavEntry(icon: 0xe000, label: id, routePath: '/$id', moduleId: id),
    ];
