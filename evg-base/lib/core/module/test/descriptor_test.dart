import 'dart:convert';
import 'package:test/test.dart';
import 'package:flutter/material.dart';
import '../module_descriptor.dart';

/// ModuleDescriptor 测试——覆盖 fromJson/toJson 往返、全部 7 种 ui 范式、
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
      expect(d.icon, isNull);
      expect(d.route, isNull);
      expect(d.ui, 'default');
      expect(d.isServiceOnly, isTrue);
      expect(d.dependencies, isEmpty);
      expect(d.activateSkills, isEmpty);
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
        icon: Icons.extension,
        route: '/full',
        ui: 'chat',
        dependencies: ['agent'],
        activateSkills: ['web_search', 'memory'],
      );
      final json = original.toJson();
      final restored = ModuleDescriptor.fromJson(json);
      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.description, original.description);
      expect(restored.route, original.route);
      expect(restored.ui, original.ui);
      expect(restored.dependencies, original.dependencies);
      expect(restored.activateSkills, original.activateSkills);
    });

    test('空字段被省略后回退默认值', () {
      final json = {
        'type': 'module',
        'id': 'defaults',
        'name': '默认值模块'
      };
      final d = ModuleDescriptor.fromJson(json);
      expect(d.description, '');
      expect(d.secondaryNavs, isEmpty);
      expect(d.dataBindings, isEmpty);
      expect(d.dependencies, isEmpty);
      expect(d.activateSkills, isEmpty);
      expect(d.ui, 'default');
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 3. 7 种 UI 范式
  // ═══════════════════════════════════════════════════════════════
  group('7 种 UI 范式', () {
    test('default 范式', () {
      final d = ModuleDescriptor.fromJson({
        'type': 'module',
        'id': 'd1',
        'name': '默认',
        'ui': 'default',
      });
      expect(d.ui, 'default');
      // ChatOptions.fromJson(null) 返回默认值，不会为 null
      expect(d.chat!.thinking.visible, isTrue); // 默认值
      expect(d.spreadsheet!.formulas, isFalse); // 默认值
      expect(d.document!.trackChanges, isFalse); // 默认值
      expect(d.presentation!.transitions, isFalse); // 默认值
    });

    test('chat 范式——完整选项', () {
      final d = ModuleDescriptor.fromJson({
        'type': 'module',
        'id': 'c1',
        'name': '聊天',
        'ui': 'chat',
        'chat': {
          'thinking': {
            'visible': true,
            'transparent': true,
            'mode': 'scroll',
            'showDuration': true,
          },
          'toolCalls': {
            'visible': true,
            'showArgs': true,
            'showResult': false,
            'autoCollapse': true,
          },
          'bubble': {
            'style': 'flat',
            'avatarPosition': 'none',
            'showTimestamp': false,
          },
          'stream': {
            'enabled': true,
            'animation': 'fade',
            'cursorStyle': 'static',
          },
          'placeholder': '问点什么...',
        },
      });
      expect(d.ui, 'chat');
      expect(d.chat, isNotNull);
      expect(d.chat!.thinking.transparent, isTrue);
      expect(d.chat!.thinking.mode, 'scroll');
      expect(d.chat!.toolCalls.showResult, isFalse);
      expect(d.chat!.toolCalls.autoCollapse, isTrue);
      expect(d.chat!.bubble.style, 'flat');
      expect(d.chat!.stream.animation, 'fade');
      expect(d.chat!.placeholder, '问点什么...');
    });

    test('spreadsheet 范式——完整选项', () {
      final d = ModuleDescriptor.fromJson({
        'type': 'module',
        'id': 's1',
        'name': '电子表格',
        'ui': 'spreadsheet',
        'spreadsheet': {
          'formulas': true,
          'charts': true,
          'sheets': true,
          'conditionalFormatting': true,
          'resizableColumns': false,
          'columns': 50,
          'rows': 500,
        },
      });
      expect(d.ui, 'spreadsheet');
      expect(d.spreadsheet, isNotNull);
      expect(d.spreadsheet!.formulas, isTrue);
      expect(d.spreadsheet!.charts, isTrue);
      expect(d.spreadsheet!.sheets, isTrue);
      expect(d.spreadsheet!.conditionalFormatting, isTrue);
      expect(d.spreadsheet!.resizableColumns, isFalse);
      expect(d.spreadsheet!.columns, 50);
      expect(d.spreadsheet!.rows, 500);
    });

    test('document 范式——往返', () {
      final d = ModuleDescriptor.fromJson({
        'type': 'module',
        'id': 'doc1',
        'name': '文档',
        'ui': 'document',
        'document': {
          'trackChanges': true,
          'comments': true,
          'tableOfContents': true,
          'footnotes': true,
          'headersFooters': true,
          'pageSetup': false,
          'exportFormats': ['pdf', 'docx', 'txt'],
        },
      });
      final json = d.toJson();
      final restored = ModuleDescriptor.fromJson(json);
      expect(restored.document!.trackChanges, isTrue);
      expect(restored.document!.exportFormats, ['pdf', 'docx', 'txt']);
    });

    test('presentation 范式——往返', () {
      final d = ModuleDescriptor.fromJson({
        'type': 'module',
        'id': 'p1',
        'name': '幻灯片',
        'ui': 'presentation',
        'presentation': {
          'transitions': true,
          'animations': true,
          'speakerNotes': true,
          'presenterView': true,
          'slideMaster': true,
          'layouts': ['title', 'blank', 'two-column'],
          'exportFormats': ['pdf'],
        },
      });
      final json = d.toJson();
      final restored = ModuleDescriptor.fromJson(json);
      expect(restored.presentation!.transitions, isTrue);
      expect(restored.presentation!.layouts, ['title', 'blank', 'two-column']);
    });

    test('dashboard 范式', () {
      final d = ModuleDescriptor.fromJson({
        'type': 'module',
        'id': 'db1',
        'name': '仪表盘',
        'ui': 'dashboard',
      });
      expect(d.ui, 'dashboard');
    });

    test('editor 范式', () {
      final d = ModuleDescriptor.fromJson({
        'type': 'module',
        'id': 'e1',
        'name': '编辑器',
        'ui': 'editor',
      });
      expect(d.ui, 'editor');
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 4. activateSkills 字段
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
  // 4b. version 字段
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

    test('toJson 非默认版本输出', () {
      final d = ModuleDescriptor(
        id: 'v2',
        name: '版本2',
        version: '3.0.0-beta',
      );
      final json = d.toJson();
      expect(json['version'], '3.0.0-beta');
    });

    test('fromJson → toJson 往返', () {
      final json = {
        'type': 'module',
        'id': 'roundtrip',
        'name': '往返',
        'version': '1.0.0',
      };
      final restored = ModuleDescriptor.fromJson(json);
      expect(restored.version, '1.0.0');
      // 默认值时省略，非默认保留
      expect(restored.toJson()['version'], '1.0.0');
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 5. 便捷属性
  // ═══════════════════════════════════════════════════════════════
  group('便捷属性', () {
    test('isServiceOnly — 无 route 为 true', () {
      final d =
          ModuleDescriptor(id: 'svc', name: '服务', route: null);
      expect(d.isServiceOnly, isTrue);
    });

    test('isServiceOnly — 空 route 为 true', () {
      final d = ModuleDescriptor(id: 'svc2', name: '服务2', route: '');
      expect(d.isServiceOnly, isTrue);
    });

    test('isServiceOnly — 有 route 为 false', () {
      final d = ModuleDescriptor(id: 'page', name: '页面', route: '/page');
      expect(d.isServiceOnly, isFalse);
    });

    test('hasSidebar — 需 icon + sidebar + route 三者齐全', () {
      final withAll = ModuleDescriptor(
        id: 'all',
        name: '全部',
        icon: Icons.home,
        route: '/all',
        sidebar: const SidebarDescriptor(section: '工具'),
      );
      expect(withAll.hasSidebar, isTrue);

      final noIcon = ModuleDescriptor(
        id: 'noicon',
        name: '无图标',
        route: '/noicon',
        sidebar: const SidebarDescriptor(section: '工具'),
      );
      expect(noIcon.hasSidebar, isFalse);

      final noRoute = ModuleDescriptor(
        id: 'noroute',
        name: '无路由',
        icon: Icons.home,
        sidebar: const SidebarDescriptor(section: '工具'),
      );
      expect(noRoute.hasSidebar, isFalse);
    });

    test('allRoutePaths 聚合所有路由', () {
      final d = ModuleDescriptor(
        id: 'multi',
        name: '多路由',
        route: '/main',
        layout: const LayoutDescriptor(panels: [
          PanelDescriptor(id: 'tab1', label: 'Tab 1', path: '/main/tab1'),
          PanelDescriptor(id: 'tab2', label: 'Tab 2', path: '/main/tab2'),
        ]),
        secondaryNavs: const [
          NavDescriptor(
              label: 'Sub', routePath: '/sub', section: '工具'),
        ],
      );
      final paths = d.allRoutePaths;
      expect(paths, contains('/main'));
      expect(paths, contains('/main/tab1'));
      expect(paths, contains('/main/tab2'));
      expect(paths, contains('/sub'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 6. 子描述符——边界条件
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
      expect(l.mode, 'scroll');
      expect(l.drawers, isEmpty);
      expect(l.panels, isEmpty);
      expect(l.zoom.enabled, isFalse);
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
  });

  // ═══════════════════════════════════════════════════════════════
  // 7. const 构造
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
        ui: 'chat',
        chat: ChatOptions(
          thinking: ThinkingOptions(transparent: true),
          stream: StreamOptions(cursorStyle: 'static'),
        ),
        input: InputOptions(mode: 'code', language: 'dart'),
      );
      expect(d.chat!.thinking.transparent, isTrue);
      expect(d.input!.language, 'dart');
    });
  });
}
