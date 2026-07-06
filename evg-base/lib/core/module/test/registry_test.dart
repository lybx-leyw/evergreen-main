import 'package:test/test.dart';
import '../capability.dart';
import '../module_descriptor.dart';
import '../module_registry.dart';

/// ModuleRegistry V2 测试——覆盖注册/seal/查询/搜索/路由/导航/依赖校验/
/// 边界条件和异常路径。
void main() {
  // ═══════ 固定数据（V2 schema）══════

  final agentModule = ModuleDescriptor(
    id: 'agent',
    name: 'AI 助手',
    description: '流式对话',
    icon: 0xf06c, // smart_toy codePoint
    route: '/agent',
    nav: const NavObjectDescriptor(
      sidebar: SidebarDescriptor(section: 'AI 工具', order: 10),
    ),
  );

  final scoreModule = ModuleDescriptor(
    id: 'scores',
    name: '成绩单',
    description: '学生成绩管理',
    icon: 0xe269, // score codePoint
    route: '/scores',
    nav: const NavObjectDescriptor(
      sidebar: SidebarDescriptor(section: '教育', order: 20),
    ),
    dataBindings: const [
      DataBindingDescriptor(dataType: 'scores', display: 'table'),
    ],
    actions: const ActionDescriptor(
      selection: 'multi',
      sortable: ['name'],
      exportable: ['csv'],
    ),
    dependencies: ['agent'],
  );

  final serviceModule = ModuleDescriptor(
    id: 'background',
    name: '后台服务',
    description: '无 UI',
    process: const [
      ProcessDescriptor(exe: 'bg.exe'),
    ],
  );

  ModuleRegistry _freshRegistry() {
    final r = ModuleRegistry();
    r.register(agentModule);
    r.register(scoreModule);
    r.register(serviceModule);
    r.setCapabilities('agent', [CapabilityDimension.agent, CapabilityDimension.module, CapabilityDimension.process]);
    r.setCapabilities('scores', [CapabilityDimension.module]);
    r.setCapabilities('background', [CapabilityDimension.process]);
    r.seal();
    return r;
  }

  // ═══════════════════════════════════════════════════════════════
  // 1. 注册
  // ═══════════════════════════════════════════════════════════════
  group('注册', () {
    test('register 正常注册', () {
      final r = ModuleRegistry();
      r.register(agentModule);
      r.register(scoreModule);
      r.seal();
      expect(r.modules.length, 2);
    });

    test('registerAll 批量注册', () {
      final r = ModuleRegistry();
      r.registerAll([agentModule, scoreModule]);
      r.seal();
      expect(r.modules.length, 2);
    });

    test('registerFromJson 从 JSON 字符串注册', () {
      final r = ModuleRegistry();
      r.registerFromJson(
          '{"type":"module","id":"json_mod","name":"JSON模块"}');
      r.seal();
      expect(r.findById('json_mod'), isNotNull);
    });

    test('重复 id 抛出 ArgumentError', () {
      final r = ModuleRegistry();
      r.register(agentModule);
      expect(() => r.register(agentModule), throwsArgumentError);
    });

    test('seal 后 register 抛出 StateError', () {
      final r = ModuleRegistry();
      r.register(agentModule);
      r.seal();
      expect(() => r.register(scoreModule), throwsStateError);
    });

    test('seal 后 setCapabilities 抛出 StateError', () {
      final r = ModuleRegistry();
      r.register(agentModule);
      r.seal();
      expect(
        () => r.setCapabilities('agent', [CapabilityDimension.agent]),
        throwsStateError,
      );
    });

    test('seal 前查询抛出 StateError', () {
      final r = ModuleRegistry();
      r.register(agentModule);
      // 未 seal，不能查询
      expect(() => r.modules, throwsStateError);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 2. 查询
  // ═══════════════════════════════════════════════════════════════
  group('查询', () {
    test('findById 找到', () {
      final r = _freshRegistry();
      expect(r.findById('agent')!.name, 'AI 助手');
    });

    test('findById 未找到返回 null', () {
      final r = _freshRegistry();
      expect(r.findById('nonexistent'), isNull);
    });

    test('findByRoute 匹配主路由', () {
      final r = _freshRegistry();
      final m = r.findByRoute('/agent');
      expect(m, isNotNull);
      expect(m!.id, 'agent');
    });

    test('findByRoute 匹配页面路由', () {
      final r = ModuleRegistry();
      r.register(ModuleDescriptor(
        id: 'multi_page',
        name: '多页面',
        route: '/multi',
        pages: [
          PageDescriptor(id: 'p1', label: 'P1', route: '/multi/p1'),
          PageDescriptor(id: 'p2', label: 'P2', route: '/multi/p2'),
        ],
      ));
      r.seal();
      expect(r.findByRoute('/multi/p1'), isNotNull);
      expect(r.findByRoute('/multi/p2'), isNotNull);
    });

    test('findByRoute 匹配子导航路由', () {
      final r = ModuleRegistry();
      r.register(ModuleDescriptor(
        id: 'navs',
        name: '子导航',
        route: '/navs',
        nav: const NavObjectDescriptor(
          secondary: [
            NavDescriptor(
                label: 'Sub', routePath: '/sub-page', section: '工具'),
          ],
        ),
      ));
      r.seal();
      expect(r.findByRoute('/sub-page'), isNotNull);
    });

    test('findByRoute 无匹配返回 null', () {
      final r = _freshRegistry();
      expect(r.findByRoute('/nowhere'), isNull);
    });

    test('modules 返回不可变列表', () {
      final r = _freshRegistry();
      expect(() => r.modules.add(agentModule), throwsUnsupportedError);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 3. search（I10）
  // ═══════════════════════════════════════════════════════════════
  group('search', () {
    test('按名称匹配（不区分大小写）', () {
      final r = _freshRegistry();
      final results = r.search('ai');
      expect(results.length, 1);
      expect(results.first.id, 'agent');
    });

    test('按 id 匹配', () {
      final r = _freshRegistry();
      final results = r.search('scores');
      expect(results.length, 1);
      expect(results.first.id, 'scores');
    });

    test('按描述匹配', () {
      final r = _freshRegistry();
      final results = r.search('流式');
      expect(results.length, 1);
      expect(results.first.id, 'agent');
    });

    test('不区分大小写', () {
      final r = _freshRegistry();
      expect(r.search('AI').length, 1);
      expect(r.search('ai').length, 1);
    });

    test('无匹配返回空列表', () {
      final r = _freshRegistry();
      expect(r.search('zzz_nonexistent'), isEmpty);
    });

    test('按维度筛选', () {
      final r = _freshRegistry();
      final results = r.search('', dims: [CapabilityDimension.process]);
      expect(results.length, 2); // agent + background both have process
      final ids = results.map((p) => p.id).toSet();
      expect(ids, contains('agent'));
      expect(ids, contains('background'));
    });

    test('按维度筛选——无匹配', () {
      final r = _freshRegistry();
      final results = r.search('', dims: [CapabilityDimension.config]);
      expect(results, isEmpty);
    });

    test('按分类筛选', () {
      final r = _freshRegistry();
      final results = r.search('', cat: 'AI 工具');
      expect(results.length, 1);
      expect(results.first.id, 'agent');
    });

    test('组合筛选：query + dims + cat', () {
      final r = _freshRegistry();
      final results = r.search('ai',
          dims: [CapabilityDimension.agent], cat: 'AI 工具');
      expect(results.length, 1);
      expect(results.first.id, 'agent');
    });

    test('返回 PluginManifest 类型', () {
      final r = _freshRegistry();
      final results = r.search('agent');
      expect(results.first.id, 'agent');
      expect(results.first.name, 'AI 助手');
      expect(results.first.description, '流式对话');
      expect(results.first.category, 'AI 工具');
      expect(results.first.dimensions,
          contains(CapabilityDimension.agent));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 4. listByCapability
  // ═══════════════════════════════════════════════════════════════
  group('listByCapability', () {
    test('按 agent 维度列出', () {
      final r = _freshRegistry();
      final list = r.listByCapability(CapabilityDimension.agent);
      expect(list.length, 1);
      expect(list.first.id, 'agent');
    });

    test('按 module 维度列出', () {
      final r = _freshRegistry();
      final list = r.listByCapability(CapabilityDimension.module);
      expect(list.length, 2);
    });

    test('按 process 维度列出', () {
      final r = _freshRegistry();
      final list = r.listByCapability(CapabilityDimension.process);
      expect(list.length, 2);
    });

    test('未设置维度的模块不返回', () {
      final r = _freshRegistry();
      final list = r.listByCapability(CapabilityDimension.config);
      expect(list, isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 5. 路由
  // ═══════════════════════════════════════════════════════════════
  group('路由', () {
    test('buildRoutePaths 聚合所有路由', () {
      final r = _freshRegistry();
      final paths = r.buildRoutePaths();
      expect(paths, contains('/agent'));
      expect(paths, contains('/scores'));
    });

    test('纯服务模块不出现在路由中', () {
      final r = _freshRegistry();
      final paths = r.buildRoutePaths();
      // background 无 route + 无 pages，不应出现
      expect(paths.length, 2);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 6. 导航
  // ═══════════════════════════════════════════════════════════════
  group('导航', () {
    test('navGroups 按 section 分组', () {
      final r = _freshRegistry();
      final groups = r.navGroups;
      expect(groups.length, 2); // AI 工具 + 教育
      expect(groups[0].$1.label, 'AI 工具');
      expect(groups[1].$1.label, '教育');
    });

    test('navFlat 扁平列表', () {
      final r = _freshRegistry();
      final flat = r.navFlat;
      expect(flat.length, 2);
    });

    test('paletteItems 命令面板条目', () {
      final r = _freshRegistry();
      final items = r.paletteItems;
      expect(items.length, 2);
      expect(items[0].title, 'AI 助手');
      expect(items[0].route, '/agent');
      expect(items[1].title, '成绩单');
    });

    test('纯服务模块不出现在导航中', () {
      final r = _freshRegistry();
      for (final (_, entries) in r.navGroups) {
        for (final e in entries) {
          expect(e.label, isNot('后台服务'));
        }
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 7. 依赖校验
  // ═══════════════════════════════════════════════════════════════
  group('依赖校验', () {
    test('依赖已注册则通过', () {
      final r = ModuleRegistry();
      r.register(agentModule);
      r.register(scoreModule); // depends on agent
      // 不应抛出
      r.seal();
    });

    test('缺失依赖抛出 StateError', () {
      final r = ModuleRegistry();
      r.register(scoreModule); // depends on agent, but agent not registered
      expect(() => r.seal(), throwsStateError);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 8. 边界条件
  // ═══════════════════════════════════════════════════════════════
  group('边界条件', () {
    test('空注册中心', () {
      final r = ModuleRegistry();
      r.seal();
      expect(r.modules, isEmpty);
      expect(r.buildRoutePaths(), isEmpty);
      expect(r.navGroups, isEmpty);
      expect(r.navFlat, isEmpty);
      expect(r.paletteItems, isEmpty);
      expect(r.search(''), isEmpty);
      expect(r.findById('any'), isNull);
      expect(r.findByRoute('/any'), isNull);
    });

    test('setCapabilities 覆盖已有值', () {
      final r = ModuleRegistry();
      r.register(agentModule);
      r.setCapabilities('agent', [CapabilityDimension.agent]);
      r.setCapabilities('agent', [CapabilityDimension.module]);
      r.seal();
      final list = r.listByCapability(CapabilityDimension.agent);
      expect(list, isEmpty); // agent 维度被覆盖
      expect(r.listByCapability(CapabilityDimension.module).length, 1);
    });

    test('空字符串 query 匹配所有', () {
      final r = _freshRegistry();
      // 所有模块的 id/name/description 都包含空字符串
      expect(r.search('').length, 3);
    });
  });
}
