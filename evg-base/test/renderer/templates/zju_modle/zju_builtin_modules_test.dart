/// zju 内置模块注册契约测试（B4）——插件市场「zju 模板」可见性的注册侧验证。
///
/// 验证 [zjuBuiltinModules] / [registerZjuBuiltinModules]：
/// - 9 个模块 id 唯一，template 均为 'zju'，modleRoute 覆盖 9 个 feature
/// - 每个模块有 route（navGroups 依赖 route 非空才能进侧边栏）
/// - 注册进 ModuleRegistry 后 seal 成功，navGroups 分「浙大·学习 / 浙大·校园」两组
/// - 与外部插件同 id 时不冲突（跳过该模块，其余继续注册）
/// - [pluginInfoFromBuiltinModule] 转换契约：isBuiltin=true / dirPath='' /
///   isModule=true（市场据此隐藏「卸载」按钮）
library;

import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/core/module/module_registry.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/marketplace/marketplace_scan.dart';
import 'package:evergreen_base/renderer/templates/zju_modle/zju_builtin_modules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('zjuBuiltinModules', () {
    test('9 个模块，id 唯一且带 zju- 前缀', () {
      final modules = zjuBuiltinModules();
      expect(modules, hasLength(9));
      final ids = modules.map((m) => m.id).toSet();
      expect(ids, hasLength(9), reason: 'id 必须唯一');
      for (final id in ids) {
        expect(id, startsWith('zju-'), reason: '内置模块 id 需 zju- 前缀防冲突');
      }
    });

    test('modleRoute 覆盖 9 个校园 feature', () {
      final routes = zjuBuiltinModules().map((m) => m.modleRoute).toSet();
      expect(routes, {
        'courses',
        'scores',
        'exams',
        'zdbk',
        'classroom',
        'library',
        'ecard',
        'teachers',
        'schedule',
      });
    });

    test('每个模块 template=zju、route 非空、hasSidebar、分组合法', () {
      const learnSections = {'浙大·学习'};
      const campusSections = {'浙大·校园'};
      for (final m in zjuBuiltinModules()) {
        expect(m.template, 'zju', reason: '${m.id} 必须走 zju 模板');
        expect(m.route, isNotNull, reason: '${m.id} 需 route 才能进侧边栏');
        expect(m.hasSidebar, isTrue, reason: '${m.id} 应显示在侧边栏');
        final section = m.nav.sidebar?.section;
        expect(
          learnSections.contains(section) || campusSections.contains(section),
          isTrue,
          reason: '${m.id} 分组应在 浙大·学习/浙大·校园，实际 $section',
        );
      }
    });

    test('学习 3 个 + 校园 6 个，分组 sectionOrder 正确', () {
      final learn = zjuBuiltinModules()
          .where((m) => m.nav.sidebar!.section == '浙大·学习')
          .toList();
      final campus = zjuBuiltinModules()
          .where((m) => m.nav.sidebar!.section == '浙大·校园')
          .toList();
      expect(learn, hasLength(3));
      expect(campus, hasLength(6));
      expect(
        learn.map((m) => m.nav.sidebar!.sectionOrder).toSet(),
        {30},
      );
      expect(
        campus.map((m) => m.nav.sidebar!.sectionOrder).toSet(),
        {40},
      );
    });
  });

  group('registerZjuBuiltinModules', () {
    test('注册后 seal 成功，navGroups 分两组、路由齐全', () {
      final registry = ModuleRegistry();
      registerZjuBuiltinModules(registry);
      registry.seal();

      expect(registry.modules, hasLength(9));
      // 路由路径（navGroups 依赖 route）全部生成
      expect(registry.buildRoutePaths(), hasLength(9));

      final groups = registry.navGroups;
      final sections = groups.map((g) => g.$1.label).toList();
      expect(sections, ['浙大·学习', '浙大·校园']);

      final flat = registry.navFlat.map((e) => e.moduleId).toList();
      expect(flat, contains('zju-courses'));
      expect(flat, contains('zju-schedule'));

      // 命令面板条目
      expect(registry.paletteItems, hasLength(9));
    });

    test('与外部插件同 id 冲突：跳过冲突模块，其余 8 个继续注册', () {
      final registry = ModuleRegistry();
      // 模拟外部插件撞名（如某个磁盘插件 id 恰好叫 zju-courses）
      registry.register(const ModuleDescriptor(
        id: 'zju-courses',
        name: '外部撞名插件',
        template: 'v4',
      ));
      registerZjuBuiltinModules(registry);
      registry.seal();
      expect(registry.modules, hasLength(1 + 8));
      expect(registry.findById('zju-courses')!.name, '外部撞名插件');
    });

    test('重复调用幂等（第二次不新增）', () {
      final registry = ModuleRegistry();
      registerZjuBuiltinModules(registry);
      registerZjuBuiltinModules(registry);
      registry.seal();
      expect(registry.modules, hasLength(9));
    });
  });

  group('pluginInfoFromBuiltinModule（市场展示契约）', () {
    test('内置模块转换：isBuiltin=true / dirPath 空 / isModule=true', () {
      final info = pluginInfoFromBuiltinModule(zjuBuiltinModules().first);
      expect(info.isBuiltin, isTrue);
      expect(info.dirPath, isEmpty, reason: '内置模块无磁盘目录（不可卸载）');
      expect(info.isModule, isTrue);
      expect(info.type, 'module');
      expect(info.id, 'zju-courses');
      expect(info.name, '我的课程');
      expect(info.pageCount, 0);
      expect(info.hasSidebar, isTrue);
    });
  });
}
