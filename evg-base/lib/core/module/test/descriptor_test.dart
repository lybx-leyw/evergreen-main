import 'package:test/test.dart';
import '../module_descriptor.dart';

/// ModuleDescriptor V2 测试——覆盖 fromJson/toJson 往返、全部新 schema、
/// activateSkills 字段、边界条件和异常路径。
void main() {
  // ═══════════════════════════════════════════════════════════════
  // 1. 最小 manifest
  // ═══════════════════════════════════════════════════════════════
  group('最小 manifest', () {
    test('fromJson 解析最小字段', () {
      final d = ModuleDescriptor.fromJson({
        'type': 'module',
        'id': 'minimal',
        'name': '最简模块',
      });
      expect(d.id, 'minimal');
      expect(d.name, '最简模块');
      expect(d.description, '');
      // icon 缺失 → 兜底为默认图标（避免 hasSidebar 失败导致插件从侧边栏静默消失）
      expect(d.icon, kDefaultIcon);
      expect(d.route, isNull);
      expect(d.isServiceOnly, isTrue);
      expect(d.dependencies, isEmpty);
      expect(d.activateSkills, isEmpty);
      expect(d.schemaVersion, '2.0');
    });

    test('fromJsonString 等效于 fromJson', () {
      final a = ModuleDescriptor.fromJsonString(
          '{"type":"module","id":"a","name":"A"}');
      final b = ModuleDescriptor.fromJson({
        'type': 'module',
        'id': 'a',
        'name': 'A'
      });
      expect(a.id, b.id);
      expect(a.name, b.name);
    });

    test('type 非 "module" 抛出 FormatException', () {
      expect(
        () => ModuleDescriptor.fromJson({
          'type': 'agent',
          'id': 'x',
          'name': 'X'
        }),
        throwsFormatException,
      );
    });

    test('缺失 id 抛出 FormatException', () {
      expect(
        () => ModuleDescriptor.fromJson({
          'type': 'module',
          'name': '无ID'
        }),
        throwsFormatException,
      );
    });

    test('缺失 name 抛出 FormatException', () {
      expect(
        () => ModuleDescriptor.fromJson({
          'type': 'module',
          'id': 'unnamed'
        }),
        throwsFormatException,
      );
    });

    test('非法 JSON 字符串抛出 FormatException', () {
      expect(
        () => ModuleDescriptor.fromJsonString('not json'),
        throwsFormatException,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 2. toJson / fromJson 往返
  // ═══════════════════════════════════════════════════════════════
  group('toJson → fromJson 往返', () {
    test('完整 manifest 往返一致', () {
      final original = ModuleDescriptor(
        id: 'full',
        name: '完整模块',
        description: '所有字段都填了',
        icon: 0xe24b, // extension codePoint
        route: '/full',
        dependencies: ['agent'],
        activateSkills: ['web_search', 'memory'],
      );
      final json = original.toJson();
      final restored = ModuleDescriptor.fromJson(json);
      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.description, original.description);
      expect(restored.route, original.route);
      expect(restored.dependencies, original.dependencies);
      expect(restored.activateSkills, original.activateSkills);
      expect(restored.schemaVersion, '2.0');
    });

    test('空字段被省略后回退默认值', () {
      final json = {
        'type': 'module',
        'id': 'defaults',
        'name': '默认值模块'
      };
      final d = ModuleDescriptor.fromJson(json);
      expect(d.description, '');
      expect(d.dataBindings, isEmpty);
      expect(d.dependencies, isEmpty);
      expect(d.activateSkills, isEmpty);
      expect(d.pages, isEmpty);
      expect(d.process, isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 3. V2 导航系统
  // ═══════════════════════════════════════════════════════════════
  group('V2 导航 (nav)', () {
    test('fromJson 解析 nav.sidebar', () {
      final d = ModuleDescriptor.fromJson({
        'type': 'module',
        'id': 'nav1',
        'name': '导航模块',
        'nav': {
          'sidebar': {
            'section': '工具',
            'sectionOrder': 100,
            'order': 1,
            'badge': true,
          },
        },
      });
      expect(d.nav.sidebar, isNotNull);
      expect(d.nav.sidebar!.section, '工具');
      expect(d.nav.sidebar!.sectionOrder, 100);
      expect(d.nav.sidebar!.badge, isTrue);
    });

    test('fromJson 解析 nav.secondary', () {
      final d = ModuleDescriptor.fromJson({
        'type': 'module',
        'id': 'nav2',
        'name': '多导航模块',
        'nav': {
          'secondary': [
            {
              'label': 'AI 助手',
              'route': '/showcase/chat',
              'icon': 'smart_toy',
              'section': '展示',
              'badge': true,
            },
            {
              'label': '编程器',
              'route': '/showcase/code',
              'icon': 'code',
              'section': '展示',
            },
          ],
        },
      });
      expect(d.nav.secondary.length, 2);
      expect(d.nav.secondary[0].label, 'AI 助手');
      expect(d.nav.secondary[0].routePath, '/showcase/chat');
      expect(d.nav.secondary[0].badge, isTrue);
      expect(d.nav.secondary[1].label, '编程器');
      expect(d.nav.secondary[1].routePath, '/showcase/code');
    });

    test('nav 往返一致', () {
      final original = ModuleDescriptor(
        id: 'nav3',
        name: '往返导航',
        nav: const NavObjectDescriptor(
          sidebar: SidebarDescriptor(section: '展示', badge: true),
          secondary: [
            NavDescriptor(label: 'AI', routePath: '/ai', section: '展示'),
          ],
        ),
      );
      final json = original.toJson();
      final restored = ModuleDescriptor.fromJson(json);
      expect(restored.nav.sidebar!.section, '展示');
      expect(restored.nav.secondary[0].label, 'AI');
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 4. V2 Process 数组化
  // ═══════════════════════════════════════════════════════════════
  group('V2 Process 数组化', () {
    test('fromJson 解析 process 数组', () {
      final d = ModuleDescriptor.fromJson({
        'type': 'module',
        'id': 'proc1',
        'name': '进程模块',
        'process': [
          {
            'id': 'main_server',
            'exe': 'module/server.exe',
            'protocol': 'http',
            'scope': 'long',
            'autoStart': true,
            'autoRestart': true,
          },
          {
            'id': 'batch_job',
            'exe': 'module/job.exe',
            'scope': 'short',
            'autoStart': false,
          },
        ],
      });
      expect(d.process.length, 2);
      expect(d.process[0].id, 'main_server');
      expect(d.process[0].exe, 'module/server.exe');
      expect(d.process[0].scope, 'long');
      expect(d.process[0].autoStart, isTrue);
      expect(d.process[0].autoRestart, isTrue);
      expect(d.process[1].id, 'batch_job');
      expect(d.process[1].scope, 'short');
      expect(d.process[1].autoStart, isFalse);
    });

    test('process 往返一致', () {
      final original = ModuleDescriptor(
        id: 'proc2',
        name: '进程往返',
        process: const [
          ProcessDescriptor(
            id: 'svc',
            exe: 'module/svc.exe',
            scope: 'long',
            autoRestart: true,
          ),
        ],
      );
      final json = original.toJson();
      final restored = ModuleDescriptor.fromJson(json);
      expect(restored.process[0].id, 'svc');
      expect(restored.process[0].autoRestart, isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 5. V2 页面 (pages) + Layout + Slot + Component
  // ═══════════════════════════════════════════════════════════════
  group('V2 pages / layout / slots / component', () {
    test('fromJson 解析页面树', () {
      final d = ModuleDescriptor.fromJson({
        'type': 'module',
        'id': 'page1',
        'name': '页面模块',
        'pages': [
          {
            'id': 'chat_page',
            'label': 'Chat',
            'route': '/showcase/chat',
            'default': true,
            'layout': {
              'type': 'grid',
              'preset': {'columns': 2, 'gap': 8},
              'features': {
                'zoom': {'enabled': false},
                'search': {'enabled': true, 'placeholder': '搜索...'},
                'drawers': ['left'],
              },
              'slots': {
                'left': {
                  'style': {
                    'gridColumn': '1 / 2',
                    'height': '100%',
                  },
                  'component': {
                    'type': 'chat',
                    'config': {
                      'thinking': {'visible': true},
                    },
                    'input': {
                      'mode': 'free-text',
                      'multiline': true,
                    },
                    'events': {
                      'emit': [
                        {'name': 'messages'},
                      ],
                      'listen': [],
                    },
                    'process': [
                      {
                        'id': 'chat_backend',
                        'exe': 'module/chat.exe',
                        'scope': 'long',
                      },
                    ],
                  },
                },
              },
            },
          },
        ],
      });

      expect(d.pages.length, 1);
      final page = d.pages[0];
      expect(page.id, 'chat_page');
      expect(page.label, 'Chat');
      expect(page.route, '/showcase/chat');
      expect(page.isDefault, isTrue);

      final layout = page.layout;
      expect(layout.type, 'grid');
      expect(layout.preset.columns, 2);
      expect(layout.preset.gap, 8);
      expect(layout.features.search!.enabled, isTrue);
      expect(layout.features.drawers, ['left']);

      expect(layout.slots.length, 1);
      final slot = layout.slots['left']!;
      expect(slot.style.gridColumn, '1 / 2');
      expect(slot.component, isNotNull);
      expect(slot.component!.type, 'chat');
      expect(slot.component!.process[0].id, 'chat_backend');
    });

    test('页面 componentTypes 聚合', () {
      final page = PageDescriptor(
        id: 'multi',
        label: '多组件',
        layout: LayoutDescriptor(
          type: 'grid',
          slots: {
            'top': SlotDescriptor(
              component: ComponentDescriptor(type: 'chart'),
            ),
            'bottom': SlotDescriptor(
              component: ComponentDescriptor(type: 'data-table'),
            ),
          },
        ),
      );
      expect(page.componentTypes, contains('chart'));
      expect(page.componentTypes, contains('data-table'));
    });

    test('页面往返一致', () {
      final original = ModuleDescriptor(
        id: 'page_rt',
        name: '页面往返',
        pages: [
          PageDescriptor(
            id: 'p1',
            label: 'P1',
            route: '/p1',
            layout: LayoutDescriptor(
              type: 'flex',
              preset: LayoutPreset(direction: 'row'),
              slots: {
                'center': SlotDescriptor(
                  component: ComponentDescriptor(
                    type: 'code-editor',
                    config: {'language': 'dart'},
                  ),
                ),
              },
            ),
          ),
        ],
      );
      final json = original.toJson();
      final restored = ModuleDescriptor.fromJson(json);
      expect(restored.pages[0].layout.type, 'flex');
      expect(restored.pages[0].layout.slots['center']!.component!.type,
          'code-editor');
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 6. V2 事件系统
  // ═══════════════════════════════════════════════════════════════
  group('V2 事件系统', () {
    test('EventDescriptor emit/listen/delegates', () {
      final e = EventDescriptor.fromJson({
        'emit': [
          {'name': 'code_executed', 'payload': {'exitCode': 'number'}},
          {'name': 'messages'},
        ],
        'listen': [
          {
            'event': 'code_executed',
            'source': '*.code-editor',
            'filter': {'exitCode': 0},
            'handler': 'update_table',
          },
        ],
        'delegates': {
          'onClick': 'handle_click',
          'propagate': false,
        },
      });
      expect(e.emit.length, 2);
      expect(e.emit[0].name, 'code_executed');
      expect(e.emit[0].payload!['exitCode'], 'number');
      expect(e.listen.length, 1);
      expect(e.listen[0].event, 'code_executed');
      expect(e.listen[0].source, '*.code-editor');
      expect(e.listen[0].handler, 'update_table');
      expect(e.delegates!.onClick, 'handle_click');
      expect(e.delegates!.propagate, isFalse);
    });

    test('EventDescriptor 往返', () {
      final original = EventDescriptor(
        emit: [
          EventEmitDescriptor(name: 'test'),
        ],
        listen: [
          EventListenDescriptor(event: 'test', handler: 'handler'),
        ],
        delegates: EventDelegatesDescriptor(onClick: 'click'),
      );
      final json = original.toJson();
      final restored = EventDescriptor.fromJson(json);
      expect(restored.emit[0].name, 'test');
      expect(restored.listen[0].handler, 'handler');
      expect(restored.delegates!.onClick, 'click');
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 7. V2 数据源
  // ═══════════════════════════════════════════════════════════════
  group('V2 数据源', () {
    test('DataSourceDescriptor fromJson', () {
      final ds = DataSourceDescriptor.fromJson({
        'endpoint': '/api/data',
        'method': 'POST',
        'dataPath': 'results',
        'transform': 'toChart',
        'refreshInterval': 30,
      });
      expect(ds.endpoint, '/api/data');
      expect(ds.method, 'POST');
      expect(ds.dataPath, 'results');
      expect(ds.transform, 'toChart');
      expect(ds.refreshInterval, 30);
    });

    test('DataSourceDescriptor 默认值', () {
      final ds = DataSourceDescriptor.fromJson(null);
      expect(ds.endpoint, isNull);
      expect(ds.method, 'GET');
      expect(ds.refreshInterval, 0);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 8. V2 样式系统
  // ═══════════════════════════════════════════════════════════════
  group('V2 样式系统', () {
    test('StyleDescriptor 完整解析', () {
      final s = StyleDescriptor.fromJson({
        'width': '100%',
        'height': 200,
        'padding': 16,
        'background': '#ffffff',
        'borderRadius': 8,
        'flex': 1,
        'flexDirection': 'row',
        'justifyContent': 'center',
        'alignItems': 'center',
        'gap': 12,
        'gridColumn': '1 / -1',
        'color': '#333333',
        'fontSize': 14,
        'overflow': 'auto',
      });
      expect(s.width, '100%');
      expect(s.height, 200);
      expect(s.padding, 16);
      expect(s.background, '#ffffff');
      expect(s.borderRadius, 8);
      expect(s.flex, 1);
      expect(s.flexDirection, 'row');
      expect(s.justifyContent, 'center');
      expect(s.gridColumn, '1 / -1');
      expect(s.color, '#333333');
      expect(s.overflow, 'auto');
    });

    test('StyleDescriptor 空 json → 全 null', () {
      final s = StyleDescriptor.fromJson(null);
      expect(s.width, isNull);
      expect(s.height, isNull);
      expect(s.isEmpty, isTrue);
    });

    test('StyleDescriptor isEmpty', () {
      expect(const StyleDescriptor().isEmpty, isTrue);
      expect(const StyleDescriptor(width: 100).isEmpty, isFalse);
    });

    test('StyleDescriptor 往返', () {
      final original = const StyleDescriptor(
        width: '100%',
        padding: 16,
        flex: 1,
      );
      final json = original.toJson();
      final restored = StyleDescriptor.fromJson(json);
      expect(restored.width, '100%');
      expect(restored.padding, 16);
      expect(restored.flex, 1);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 9. activateSkills 字段
  // ═══════════════════════════════════════════════════════════════
  group('activateSkills', () {
    test('fromJson 解析 activateSkills', () {
      final d = ModuleDescriptor.fromJson({
        'type': 'module',
        'id': 'skills1',
        'name': '技能模块',
        'activateSkills': ['web_search', 'memory', 'code_interpreter'],
      });
      expect(d.activateSkills, ['web_search', 'memory', 'code_interpreter']);
    });

    test('默认值为空列表', () {
      final d = ModuleDescriptor.fromJson({
        'type': 'module',
        'id': 'noskills',
        'name': '无技能'
      });
      expect(d.activateSkills, isEmpty);
    });

    test('toJson 空列表时省略字段', () {
      final d = ModuleDescriptor(id: 'noskills', name: '无技能');
      final json = d.toJson();
      expect(json.containsKey('activateSkills'), isFalse);
    });

    test('toJson 非空时输出', () {
      final d = ModuleDescriptor(
        id: 'withskills',
        name: '有技能',
        activateSkills: ['skill_a'],
      );
      final json = d.toJson();
      expect(json['activateSkills'], ['skill_a']);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 10. version 字段
  // ═══════════════════════════════════════════════════════════════
  group('version', () {
    test('fromJson 解析 version', () {
      final d = ModuleDescriptor.fromJson({
        'type': 'module',
        'id': 'v1',
        'name': '版本模块',
        'version': '2.5.0',
      });
      expect(d.version, '2.5.0');
    });

    test('默认值为 0.0.0', () {
      final d = ModuleDescriptor.fromJson({
        'type': 'module',
        'id': 'noversion',
        'name': '无版本'
      });
      expect(d.version, '0.0.0');
    });

    test('toJson 默认版本省略字段', () {
      final d = ModuleDescriptor(id: 'noversion', name: '无版本');
      final json = d.toJson();
      expect(json.containsKey('version'), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 11. 便捷属性
  // ═══════════════════════════════════════════════════════════════
  group('便捷属性', () {
    test('isServiceOnly — 无 pages 且无 route 为 true', () {
      final d = ModuleDescriptor(id: 'svc', name: '服务');
      expect(d.isServiceOnly, isTrue);
    });

    test('isServiceOnly — 有 pages 为 false', () {
      final d = ModuleDescriptor(
        id: 'page',
        name: '页面',
        pages: [PageDescriptor(id: 'p1', label: 'P1')],
      );
      expect(d.isServiceOnly, isFalse);
    });

    test('hasSidebar — 需 sidebar + 非服务（icon 缺失兜底默认图标）', () {
      final withAll = ModuleDescriptor(
        id: 'all',
        name: '全部',
        icon: 0xe88a,
        route: '/all',
        nav: NavObjectDescriptor(
          sidebar: SidebarDescriptor(section: '工具'),
        ),
      );
      expect(withAll.hasSidebar, isTrue);

      // icon 缺失不再阻止侧边栏显示（兜底默认图标）
      final noIcon = ModuleDescriptor(
        id: 'noicon',
        name: '无图标',
        route: '/noicon',
        nav: NavObjectDescriptor(
          sidebar: SidebarDescriptor(section: '工具'),
        ),
      );
      expect(noIcon.hasSidebar, isTrue);

      // 无 sidebar 仍不进侧边栏
      final noSidebar = ModuleDescriptor(
        id: 'nosidebar',
        name: '无侧栏',
        icon: 0xe88a,
        route: '/nosidebar',
      );
      expect(noSidebar.hasSidebar, isFalse);
    });

    test('allRoutePaths 聚合页面路由', () {
      final d = ModuleDescriptor(
        id: 'multi',
        name: '多路由',
        route: '/main',
        pages: [
          PageDescriptor(id: 'p1', label: 'P1', route: '/main/p1'),
          PageDescriptor(id: 'p2', label: 'P2', route: '/main/p2'),
        ],
      );
      final paths = d.allRoutePaths;
      expect(paths, contains('/main/p1'));
      expect(paths, contains('/main/p2'));
      expect(paths, contains('/main'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 12. 子描述符——边界条件
  // ═══════════════════════════════════════════════════════════════
  group('子描述符边界', () {
    test('SidebarDescriptor 默认值', () {
      final s = SidebarDescriptor.fromJson({'section': '测试'});
      expect(s.sectionOrder, 50);
      expect(s.order, 50);
      expect(s.badge, isFalse);
    });

    test('LayoutDescriptor 空 json → 默认值', () {
      final l = LayoutDescriptor.fromJson(null);
      expect(l.type, 'grid');
      expect(l.features.drawers, isEmpty);
      expect(l.slots, isEmpty);
    });

    test('ActionDescriptor 空 json → 默认值', () {
      final a = ActionDescriptor.fromJson(null);
      expect(a.selection, 'none');
      expect(a.sortable, isEmpty);
      expect(a.creatable, isFalse);
    });

    test('InputOptions 空 json → 默认值', () {
      final i = InputOptions.fromJson(null);
      expect(i.mode, 'free-text');
      expect(i.multiline, isTrue);
      expect(i.autoFocus, isTrue);
    });

    test('DeletableDescriptor confirm: bool/String/null', () {
      final d1 = DeletableDescriptor.fromJson({
        'enabled': true,
        'confirm': true,
      });
      expect(d1.confirmEnabled, isTrue);

      final d2 = DeletableDescriptor.fromJson({
        'enabled': true,
        'confirm': '确定删除？',
      });
      expect(d2.confirmEnabled, isTrue);
      expect(d2.confirmMessage, '确定删除？');

      final d3 = DeletableDescriptor.fromJson({
        'enabled': true,
        'confirm': false,
      });
      expect(d3.confirmEnabled, isFalse);
    });

    test('DataBindingDescriptor 从 "type" 字段读取', () {
      final d = DataBindingDescriptor.fromJson({
        'type': 'scores',
        'display': 'table',
        'filter': true,
      });
      expect(d.dataType, 'scores');
      expect(d.display, 'table');
      expect(d.filter, isTrue);
    });

    test('ModuleDescriptor == 基于 id', () {
      final a = ModuleDescriptor(id: 'same', name: 'A');
      final b = ModuleDescriptor(id: 'same', name: 'B');
      final c = ModuleDescriptor(id: 'diff', name: 'C');
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('ProcessDescriptor 新字段默认值', () {
      final p = ProcessDescriptor.fromJson({'exe': 'test.exe'});
      expect(p.id, isNull);
      expect(p.exe, 'test.exe');
      expect(p.protocol, 'http');
      expect(p.scope, 'long');
      expect(p.autoStart, isTrue);
      expect(p.autoRestart, isFalse);
    });

    test('ActionButtonDescriptor 支持 id 和 icon', () {
      final a = ActionButtonDescriptor.fromJson({
        'trigger': 'button:export',
        'label': '导出',
        'id': 'export_btn',
        'icon': 'download',
      });
      expect(a.id, 'export_btn');
      expect(a.trigger, 'button:export');
      expect(a.label, '导出');
      expect(a.icon, isNotNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 13. const 构造
  // ═══════════════════════════════════════════════════════════════
  group('const 构造', () {
    test('const ModuleDescriptor 可用', () {
      const d = ModuleDescriptor(id: 'const1', name: 'Const 模块');
      expect(d.id, 'const1');
      expect(d.isServiceOnly, isTrue);
    });

    test('const 嵌套子描述符', () {
      const d = ModuleDescriptor(
        id: 'const_nested',
        name: '嵌套 Const',
        style: StyleDescriptor(width: '100%'),
        process: [
          ProcessDescriptor(id: 'svc', exe: 'svc.exe', scope: 'long'),
        ],
        nav: NavObjectDescriptor(
          sidebar: SidebarDescriptor(section: '工具'),
        ),
      );
      expect(d.style.width, '100%');
      expect(d.process[0].id, 'svc');
      expect(d.nav.sidebar!.section, '工具');
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 14. V2 Showcase 完整 manifest 解析
  // ═══════════════════════════════════════════════════════════════
  group('V2 Showcase 完整解析', () {
    test('解析 Showcase V2 manifest', () {
      final d = ModuleDescriptor.fromJson({
        'type': 'module',
        'schemaVersion': '2.0',
        'id': 'showcase',
        'name': '展示大厅',
        'description': '全功能展示',
        'icon': 'auto_awesome',
        'version': '2.0.0',
        'route': '/showcase',
        'nav': {
          'sidebar': {'section': '展示', 'sectionOrder': 100, 'order': 1, 'badge': true},
          'secondary': [
            {'label': 'AI 助手', 'route': '/showcase/chat', 'icon': 'smart_toy', 'section': '展示'},
            {'label': '编程器', 'route': '/showcase/code', 'icon': 'code', 'section': '展示'},
          ],
        },
        'process': [
          {'id': 'showcase_global', 'exe': 'module/showcase.exe', 'scope': 'long', 'autoStart': true},
        ],
        'events': {
          'emit': [{'name': 'module_ready'}],
        },
        'actions': {
          'itemTap': 'detail',
          'creatable': true,
          'actionButtons': [
            {'id': 'export_btn', 'trigger': 'button:export', 'label': '导出', 'icon': 'download'},
          ],
        },
        'workspace': {'enabled': true, 'maxFiles': 100},
        'pages': [
          {
            'id': 'chat_page',
            'label': 'AI 助手',
            'route': '/showcase/chat',
            'default': true,
            'layout': {
              'type': 'grid',
              'preset': {'columns': 1},
              'slots': {
                'center': {
                  'component': {
                    'type': 'chat',
                    'config': {
                      'thinking': {'visible': true, 'transparent': true},
                    },
                    'input': {'mode': 'free-text'},
                    'process': [
                      {'id': 'chat_backend', 'exe': 'module/chat.exe', 'scope': 'long'},
                    ],
                  },
                },
              },
            },
          },
        ],
      });

      expect(d.id, 'showcase');
      expect(d.schemaVersion, '2.0');
      expect(d.nav.sidebar!.section, '展示');
      expect(d.nav.secondary.length, 2);
      expect(d.process[0].id, 'showcase_global');
      expect(d.actions!.actionButtons.length, 1);
      expect(d.actions!.actionButtons[0].id, 'export_btn');
      expect(d.workspace!.enabled, isTrue);
      expect(d.pages[0].layout.slots['center']!.component!.type, 'chat');
    });
  });
}
