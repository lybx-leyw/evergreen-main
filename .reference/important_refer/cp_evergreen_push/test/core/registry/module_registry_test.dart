import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:evergreen_multi_tools/core/registry/modules.dart';

// ═══════════════════════════════════════════════════════════
// 测试用 Mock 模块
// ═══════════════════════════════════════════════════════════

class _TestModule extends FeatureModule {
  final String _id;
  final String _name;
  final IconData _icon;
  final SidebarSection _section;
  final int _order;
  final List<String> _deps;
  final String _route;
  final ProviderListenable<int?>? _badgeProvider;

  _TestModule({
    required String id,
    required String name,
    IconData icon = Icons.star,
    SidebarSection section = SidebarSection.system,
    int order = 50,
    List<String> deps = const [],
    String? route,
    ProviderListenable<int?>? badgeProvider,
  })  : _id = id,
        _name = name,
        _icon = icon,
        _section = section,
        _order = order,
        _deps = deps,
        _route = route ?? '/$id',
        _badgeProvider = badgeProvider;

  @override
  String get id => _id;
  @override
  String get name => _name;
  @override
  IconData get icon => _icon;
  @override
  SidebarSection get sidebarSection => _section;
  @override
  int get sidebarOrder => _order;
  @override
  List<String> get dependsOn => _deps;
  @override
  ProviderListenable<int?>? get sidebarBadgeProvider => _badgeProvider;

  @override
  List<RouteBase> buildRoutes() => [
        GoRoute(
          path: _route,
          pageBuilder: (context, state) => CustomTransitionPage<void>(
            key: state.pageKey,
            child: const SizedBox.shrink(),
            transitionsBuilder: (context, animation, _, child) =>
                FadeTransition(opacity: animation, child: child),
            transitionDuration: const Duration(milliseconds: 200),
          ),
        ),
      ];
}

void main() {
  // ═══════════════════════════════════════════════════
  // 注册
  // ═══════════════════════════════════════════════════

  group('ModuleRegistry.register', () {
    test('正常注册模块', () {
      final reg = ModuleRegistry();
      reg.register(_TestModule(id: 'test', name: '测试'));
      expect(() => reg.seal(), returnsNormally);
      expect(reg.modules.length, 1);
    });

    test('重复 id 抛出异常', () {
      final reg = ModuleRegistry();
      reg.register(_TestModule(id: 'dup', name: 'A'));
      expect(
        () => reg.register(_TestModule(id: 'dup', name: 'B')),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('seal 后注册抛出异常', () {
      final reg = ModuleRegistry();
      reg.register(_TestModule(id: 'a', name: 'A'));
      reg.seal();
      expect(
        () => reg.register(_TestModule(id: 'b', name: 'B')),
        throwsA(isA<StateError>()),
      );
    });
  });

  // ═══════════════════════════════════════════════════
  // 依赖校验
  // ═══════════════════════════════════════════════════

  group('ModuleRegistry.seal — 依赖校验', () {
    test('依赖存在 = 正常', () {
      final reg = ModuleRegistry();
      reg.register(_TestModule(id: 'base', name: '基座'));
      reg.register(_TestModule(id: 'child', name: '子模块', deps: ['base']));
      expect(() => reg.seal(), returnsNormally);
      expect(reg.modules.length, 2);
    });

    test('依赖缺失抛出异常', () {
      final reg = ModuleRegistry();
      reg.register(_TestModule(id: 'child', name: '子模块', deps: ['missing']));
      expect(() => reg.seal(), throwsA(isA<StateError>()));
    });

    test('链式依赖正常', () {
      final reg = ModuleRegistry();
      reg.register(_TestModule(id: 'a', name: 'A'));
      reg.register(_TestModule(id: 'b', name: 'B', deps: ['a']));
      reg.register(_TestModule(id: 'c', name: 'C', deps: ['b']));
      expect(() => reg.seal(), returnsNormally);
    });

    test('循环依赖不检测但注册不报错（运行时依赖应避免）', () {
      final reg = ModuleRegistry();
      reg.register(_TestModule(id: 'a', name: 'A', deps: ['b']));
      reg.register(_TestModule(id: 'b', name: 'B', deps: ['a']));
      // 循环依赖当前不做检测，仅校验 id 存在性
      expect(() => reg.seal(), returnsNormally);
    });
  });

  // ═══════════════════════════════════════════════════
  // 路由生成
  // ═══════════════════════════════════════════════════

  group('buildRoutes', () {
    test('收集所有模块的路由', () {
      final reg = ModuleRegistry();
      reg.register(_TestModule(id: 'a', name: 'A', route: '/a'));
      reg.register(_TestModule(id: 'b', name: 'B', route: '/b'));
      reg.seal();

      final routes = reg.buildRoutes();
      expect(routes.length, 2);
    });

    test('seal 前调用抛出异常', () {
      final reg = ModuleRegistry();
      reg.register(_TestModule(id: 'a', name: 'A'));
      expect(() => reg.buildRoutes(), throwsA(isA<StateError>()));
    });
  });

  // ═══════════════════════════════════════════════════
  // 侧边栏导航生成
  // ═══════════════════════════════════════════════════

  group('navGroups', () {
    test('按 section 分组', () {
      final reg = ModuleRegistry();
      reg.register(_TestModule(
        id: 'learn', name: '学习模块',
        icon: Icons.school, section: SidebarSection.learning, order: 10,
      ));
      reg.register(_TestModule(
        id: 'sys', name: '系统模块',
        icon: Icons.settings, section: SidebarSection.system, order: 10,
      ));
      reg.seal();

      final groups = reg.navGroups;
      expect(groups.length, 2);
      expect(groups[0].$1, SidebarSection.learning);
      expect(groups[0].$2.first.label, '学习模块');
      expect(groups[1].$1, SidebarSection.system);
      expect(groups[1].$2.first.label, '系统模块');
    });

    test('同 section 内按 order 排序', () {
      final reg = ModuleRegistry();
      reg.register(_TestModule(
        id: 'b', name: '后',
        icon: Icons.star, section: SidebarSection.learning, order: 90,
      ));
      reg.register(_TestModule(
        id: 'a', name: '先',
        icon: Icons.star, section: SidebarSection.learning, order: 10,
      ));
      reg.seal();

      final groups = reg.navGroups;
      expect(groups[0].$2[0].label, '先');
      expect(groups[0].$2[1].label, '后');
    });

    test('无 icon 的模块不出现在导航中', () {
      final reg = ModuleRegistry();
      // 没有 icon 的纯服务模块
      final serviceModule = _TestModule(
        id: 'service', name: '后台服务',
        section: SidebarSection.system,
      );
      // 覆写 icon 为 null
      final noIcon = _NoIconModule();
      reg.register(noIcon);
      reg.seal();

      expect(reg.navFlat.length, 0);
    });

    test('navFlat 返回扁平列表', () {
      final reg = ModuleRegistry();
      reg.register(_TestModule(
        id: 'x', name: 'X', icon: Icons.close,
        section: SidebarSection.system,
      ));
      reg.register(_TestModule(
        id: 'y', name: 'Y', icon: Icons.check,
        section: SidebarSection.learning,
      ));
      reg.seal();

      expect(reg.navFlat.length, 2);
    });
  });

  // ═══════════════════════════════════════════════════
  // 命令面板
  // ═══════════════════════════════════════════════════

  group('paletteItems', () {
    test('自动从模块生成搜索条目', () {
      final reg = ModuleRegistry();
      reg.register(_TestModule(
        id: 'search', name: '搜索',
        icon: Icons.search, section: SidebarSection.system,
        route: '/search',
      ));
      reg.seal();

      final items = reg.paletteItems;
      expect(items.length, 1);
      expect(items.first.title, '搜索');
      expect(items.first.route, '/search');
      expect(items.first.category, '系统');
    });

    test('无 icon/无 section 的模块不生成条目', () {
      final reg = ModuleRegistry();
      reg.register(_NoIconModule());
      reg.seal();

      expect(reg.paletteItems.length, 0);
    });
  });

  // ═══════════════════════════════════════════════════
  // 连通性检查收集
  // ═══════════════════════════════════════════════════

  group('connectivityChecks', () {
    test('收集所有声明的检查', () {
      final reg = ModuleRegistry();
      reg.register(_TestModule(id: 'a', name: 'A'));
      reg.seal();

      // 默认无检查
      expect(reg.connectivityChecks.length, 0);
    });
  });
}

/// 无 icon 的模块——不应出现在侧边栏中。
class _NoIconModule extends FeatureModule {
  @override String get id => 'no_icon';
  @override String get name => '隐藏模块';
  // 不覆写 icon → null → 不出现在导航
  // 不覆写 sidebarSection → null → 不出现在导航
}
