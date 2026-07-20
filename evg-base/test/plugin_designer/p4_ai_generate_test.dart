/// A-P4 Batch 1 测试：AI 设计生成引擎（A1 生成 / A2 白名单 / A3 降级 / D 数据绑定 / C 改稿复用）。
///
/// 使用 [_FakeProvider] 注入确定性响应，不调用真实 DeepSeek，不驱动
/// PluginDesignerView（避免 PluginPreloader 常驻定时器与 flutter_test 泵冲突，见 FAIL #13）。
import 'dart:convert';

import 'package:evergreen_base/core/agent/agent.dart' as agent;
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/models/design_document.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/models/design_page.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/services/ai_design_generator.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/services/design_to_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

/// 受控的 LLM 通道：返回固定文本，可模拟抛错，并捕获传入的消息。
class _FakeProvider implements agent.Provider {
  final String responseText;
  final bool throwOnChat;
  List<agent.Message>? capturedMessages;

  _FakeProvider(this.responseText, {this.throwOnChat = false});

  @override
  String get name => 'fake';

  @override
  Stream<agent.ProviderEvent> chat({
    required List<agent.Message> messages,
    List<Map<String, dynamic>> tools = const [],
  }) async* {
    capturedMessages = messages;
    if (throwOnChat) throw Exception('boom');
    yield agent.ProviderEvent.content(responseText);
    yield agent.ProviderEvent.done();
  }
}

/// 合法 JSON：2 页；含 1 个数据绑定（data-dashboard + dataSource）与 1 个越界 type（foo-bar）。
const _validJson = '''
{
  "plugin_id": "ai-demo",
  "plugin_name": "AI 演示插件",
  "icon": "dashboard",
  "description": "由 AI 生成的演示",
  "route": "/ai-demo",
  "version": "1.0.0",
  "nav": {"section": "通用", "sectionOrder": 50, "order": 50, "badge": false},
  "dependencies": [],
  "pages": [
    {
      "id": "page_0",
      "label": "首页",
      "layout_preset": "grid",
      "default": true,
      "hideTab": false,
      "slots": [
        {"id": "slot_0", "label": "仪表盘", "region": "center", "component": {"type": "data-dashboard", "config": {"dataSource": {"endpoint": "orch://courses"}}}},
        {"id": "slot_1", "label": "非法组件", "region": "top", "component": {"type": "foo-bar", "config": {}}}
      ]
    },
    {
      "id": "page_1",
      "label": "关于",
      "layout_preset": "fullscreen",
      "default": false,
      "hideTab": false,
      "slots": [
        {"id": "slot_2", "label": "文档", "region": "center", "component": {"type": "markdown", "config": {}}}
      ]
    }
  ]
}
''';

/// 同上但用 ```json 代码块包裹（验证剥离逻辑）。
const _validJsonWrapped = '这是一些前言\n```json\n$_validJson\n```\n后记';

/// 缺 pages 的 JSON（应触发 no_pages 失败）。
const _emptyPagesJson = '{"plugin_id":"x","plugin_name":"空","pages":[]}';

void main() {
  group('A1 生成引擎：自然语言 → DesignDocument', () {
    test('合法 JSON → 返回非空 doc（含页面与 slot）', () async {
      final gen = AiDesignGenerator(_FakeProvider(_validJson));
      final doc = await gen.generate('做一个课程表插件');
      expect(doc.pluginId, 'ai-demo');
      expect(doc.pluginName, 'AI 演示插件');
      expect(doc.pages.length, 2);
      expect(doc.slotCount, 3);
    });

    test('```json 代码块包裹 → 仍能正确剥离并解析', () async {
      final gen = AiDesignGenerator(_FakeProvider(_validJsonWrapped));
      final doc = await gen.generate('做一个插件');
      expect(doc.pages.length, 2);
      expect(doc.slotCount, 3);
    });

    test('生成结果经 DesignToManifest.compile 不抛错', () async {
      final gen = AiDesignGenerator(_FakeProvider(_validJson));
      final doc = await gen.generate('做一个插件');
      expect(() => DesignToManifest.compile(doc), returnsNormally);
    });
  });

  group('A2 组件白名单约束', () {
    test('越界 type (foo-bar) → 降级为 component == null', () async {
      final gen = AiDesignGenerator(_FakeProvider(_validJson));
      final doc = await gen.generate('做一个插件');
      final badSlot = doc.pages[0].slots
          .firstWhere((s) => s.id == 'slot_1');
      expect(badSlot.component, isNull);
    });

    test('合法 type 全部保留，不误伤', () async {
      final gen = AiDesignGenerator(_FakeProvider(_validJson));
      final doc = await gen.generate('做一个插件');
      final okSlot = doc.pages[0].slots
          .firstWhere((s) => s.id == 'slot_0');
      expect(okSlot.component?.type, 'data-dashboard');
    });
  });

  group('A3 降级与健壮性', () {
    test('API 抛错 → 抛 AiGenerateException', () async {
      final gen = AiDesignGenerator(_FakeProvider('', throwOnChat: true));
      expect(
        () => gen.generate('做一个插件'),
        throwsA(isA<AiGenerateException>()
            .having((e) => e.reason, 'reason', 'api_error')),
      );
    });

    test('非 JSON 响应 → 抛 AiGenerateException(invalid_json)', () async {
      final gen = AiDesignGenerator(
        _FakeProvider('我觉得这个需求很合理，但我不输出 JSON。'),
      );
      expect(
        () => gen.generate('做一个插件'),
        throwsA(isA<AiGenerateException>()
            .having((e) => e.reason, 'reason', 'invalid_json')),
      );
    });

    test('缺 pages → 抛 AiGenerateException(no_pages)', () async {
      final gen = AiDesignGenerator(_FakeProvider(_emptyPagesJson));
      expect(
        () => gen.generate('做一个插件'),
        throwsA(isA<AiGenerateException>()
            .having((e) => e.reason, 'reason', 'no_pages')),
      );
    });
  });

  group('C 多轮改稿（复用 A1/A2/A3）', () {
    test('改稿模式：用户消息含 base JSON 与修改指令', () async {
      final base = DesignDocument(pluginId: 'base-old', pluginName: '旧插件');
      final fake = _FakeProvider(_validJson);
      final gen = AiDesignGenerator(fake);
      await gen.generate('把首页改成网格布局', base: base);
      final userMsg = fake.capturedMessages!
          .firstWhere((m) => m.role == agent.Role.user);
      expect(userMsg.content, contains('修改指令'));
      expect(userMsg.content, contains('base-old')); // base.toJson 已注入
    });

    test('改稿产出仍是合法 doc 且经 compile 不抛错', () async {
      final base = DesignDocument(pluginId: 'base-old', pluginName: '旧插件');
      final gen = AiDesignGenerator(_FakeProvider(_validJson));
      final revised = await gen.generate('把首页改成网格', base: base);
      expect(revised.pages.length, 2);
      expect(revised.pages.first.layoutPreset, LayoutPreset.grid);
      expect(() => DesignToManifest.compile(revised), returnsNormally);
    });
  });

  group('D 自动数据接入', () {
    test('数据组件含 dataSource 对象（orch:// 端点），且编译后进入 manifest', () async {
      final gen = AiDesignGenerator(_FakeProvider(_validJson));
      final doc = await gen.generate('展示我的课程成绩表格');
      final compiled = DesignToManifest.compile(doc);
      final slots = (compiled['pages'] as List)
          .first as Map<String, dynamic>;
      final slotMap = slots['layout']['slots'] as Map<String, dynamic>;
      final dashSlot = slotMap['slot_0'] as Map<String, dynamic>;
      final ds = dashSlot['component']['config']['dataSource'] as Map;
      expect(ds['endpoint'], 'orch://courses');
    });

    test('无数据需求的描述，AI 未强行塞 dataSource 时不报错', () async {
      final gen = AiDesignGenerator(_FakeProvider(_validJson));
      final doc = await gen.generate('纯展示封面页');
      // 任何 dataSource 都必须是合法对象（endpoint 非空），不得是空字符串/非法形态
      final hasSpurious = doc.pages.expand((p) => p.slots).any((s) {
        final comp = s.component;
        if (comp == null) return false;
        final ds = comp.config['dataSource'];
        if (ds is! Map) return ds != null; // 非对象即非法（null 不算）
        final ep = ds['endpoint'];
        return ep is! String || (ep as String).isEmpty;
      });
      expect(hasSpurious, isFalse);
    });
  });
}
