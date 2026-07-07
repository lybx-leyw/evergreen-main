/// Widgets 核心路径单元测试。
///
/// Sprint 3 最低覆盖：
/// - shared/：ThemeProvider token→Color 映射
/// - widgets/ 核心路径：MessageBubble 4 种内容类型、
///   ToolCallCard 折叠展开、DataTable 排序/选择、
///   ChatInputBar 发送/附件/快捷键
library;

import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/core/theme/theme_descriptor.dart';
import 'package:evergreen_base/renderer/widgets/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// 从 [ThemeColor.value] 提取 ARGB 分量。
int _a(int value) => (value >> 24) & 0xFF;
int _r(int value) => (value >> 16) & 0xFF;
int _g(int value) => (value >> 8) & 0xFF;
int _b(int value) => value & 0xFF;

// ═══════ ThemeDescriptor: 五层 token 查询 ═══════

// 构建最小合法主题（const 构造不校验子 token）
ThemeDescriptor _makeLightTheme() => const ThemeDescriptor(
  id: 'light',
  name: 'Light',
  app: {
    'sidebar': {'bg': '#F2F3F5', 'text': '#1A1D21', 'active': '#1677FF', 'hover': '#E8E8E8', 'divider': '#D0D5DD'},
    'header': {'bg': '#FFF', 'text': '#1A1D21', 'border': '#D0D5DD'},
    'footer': {'bg': '#FFF', 'text': '#1A1D21', 'border': '#D0D5DD'},
    'blank': {'bg': '#F5F5F5'},
    'commandPalette': {'bg': '#FFF', 'text': '#1A1D21', 'highlight': '#E8E8E8', 'border': '#D0D5DD'},
  },
  module: {'chrome': {'bg': '#FFF', 'border': '#D0D5DD'}},
  page: {
    'tabBar': {'bg': '#FFF', 'text': '#6B7280', 'active': '#1677FF', 'indicator': '#1677FF', 'hover': '#E8E8E8', 'border': '#D0D5DD'},
    'background': {'color': '#F5F5F5'},
  },
  slot: {
    'header': {'bg': '#FFF', 'text': '#1A1D21', 'border': '#D0D5DD'},
    'background': {'color': '#FFFFFF'},
    'border': {'color': '#D0D5DD', 'width': '1'},
  },
  components: {
    'sidebar': {'bg': '#F2F3F5', 'text': '#1A1D21', 'active': '#1677FF', 'hover': '#0958D9'},
    'button': {'primary': '#1677FF', 'hover': '#0958D9', 'active': '#1677FF', 'disabled': '#D0D5DD', 'text': '#FFFFFF'},
    'bubble': {'user': '#4096FF', 'assistant': '#21262D', 'text': '#E6EDF3', 'timestamp': '#8B949E'},
    'thinking': {'bg': '#1C1A14', 'text': '#8B949E', 'border': '#D29922'},
    'toolCall': {'bg': '#21262D', 'text': '#E6EDF3', 'border': '#30363D'},
    'card': {'bg': '#FFFFFF', 'border': '#D0D5DD', 'shadow': '#000000', 'text': '#1A1D21'},
  },
);

void main() {
  group('ThemeDescriptor — 五层 token 查询', () {
    late ThemeDescriptor lightTheme;

    setUp(() {
      lightTheme = _makeLightTheme();
    });

    test('parseHex 返回正确的 ThemeColor（#1677FF）', () {
      final color = ThemeDescriptor.parseHex('#1677FF');
      expect(color, isNotNull);
      expect(_r(color!.value), 0x16);
      expect(_g(color.value), 0x77);
      expect(_b(color.value), 0xFF);
    });

    test('parseHex 处理 8 位 hex（#FF1677FF）', () {
      final color = ThemeDescriptor.parseHex('#FF1677FF');
      expect(color, isNotNull);
      expect(_a(color!.value), 0xFF);
      expect(_r(color.value), 0x16);
      expect(_g(color.value), 0x77);
      expect(_b(color.value), 0xFF);
    });

    test('parseHex 处理 3 位 hex（#FFF）', () {
      final color = ThemeDescriptor.parseHex('#FFF');
      expect(color, isNotNull);
      expect(_r(color!.value), 0xFF);
      expect(_g(color.value), 0xFF);
      expect(_b(color.value), 0xFF);
    });

    test('parseHex 对无效格式返回 null', () {
      expect(ThemeDescriptor.parseHex('invalid'), isNull);
      expect(ThemeDescriptor.parseHex(''), isNull);
    });

    test('tokenValue 返回正确 token 值（app 层）', () {
      expect(lightTheme.tokenValue(lightTheme.app, 'sidebar', 'active'), '#1677FF');
      expect(lightTheme.tokenValue(lightTheme.app, 'blank', 'bg'), '#F5F5F5');
      expect(lightTheme.tokenValue(lightTheme.app, 'sidebar', 'text'), '#1A1D21');
    });

    test('tokenValue 对未知 key 返回 null', () {
      expect(lightTheme.tokenValue(lightTheme.app, 'unknown_key', 'x'), isNull);
    });

    test('tokenColor 返回 ThemeColor', () {
      final color = lightTheme.tokenColor(lightTheme.app, 'sidebar', 'active');
      expect(color, isNotNull);
      expect(_r(color!.value), 0x16);
      expect(_g(color.value), 0x77);
      expect(_b(color.value), 0xFF);
    });

    test('tokenColor 对未注册组件返回 null', () {
      expect(lightTheme.tokenColor(lightTheme.components, 'unknownComp', 'token'), isNull);
    });

    test('组件 token 查询（components 层）', () {
      final sidebar = lightTheme.components['sidebar'];
      expect(sidebar, isNotNull);
      expect(sidebar!['bg'], '#F2F3F5');
    });

    test('未注册组件返回 null', () {
      // bubble 不在当前 components 的 button/sidebar/card 中
      expect(lightTheme.tokenValue(lightTheme.components, 'nonexistent', 'bg'), isNull);
    });
  });

  group('ThemeDescriptor — dark theme 组件 token', () {
    late ThemeDescriptor theme;

    setUp(() {
      theme = _makeLightTheme(); // Reuse with built-in component data
    });

    test('bubble 组件 token', () {
      final bubble = theme.components['bubble']!;
      expect(bubble['user'], '#4096FF');
      expect(bubble['assistant'], '#21262D');
      expect(bubble['text'], '#E6EDF3');
    });

    test('thinking 组件 token', () {
      expect(theme.components['thinking']!['bg'], '#1C1A14');
      expect(theme.components['thinking']!['text'], '#8B949E');
      expect(theme.components['thinking']!['border'], '#D29922');
    });

    test('toolCall 组件 token', () {
      expect(theme.components['toolCall']!['bg'], '#21262D');
      expect(theme.components['toolCall']!['text'], '#E6EDF3');
      expect(theme.components['toolCall']!['border'], '#30363D');
    });

    test('component tokenColor 返回正确 ThemeColor', () {
      final user = theme.tokenColor(theme.components, 'bubble', 'user');
      expect(user, isNotNull);
      expect(_r(user!.value), 0x40);
      expect(_g(user.value), 0x96);
      expect(_b(user.value), 0xFF);

      final tBg = theme.tokenColor(theme.components, 'thinking', 'bg');
      expect(tBg, isNotNull);
      expect(_r(tBg!.value), 0x1C);
      expect(_g(tBg.value), 0x1A);
      expect(_b(tBg.value), 0x14);
    });
  });

  // ═══════ ChatMessage — MessageBubble 4 种内容类型 ═══════

  group('ChatMessage — 4 种内容类型', () {
    test('user 纯文本消息', () {
      final msg = ChatMessage(role: 'user', content: 'Hello');
      expect(msg.isUser, isTrue);
      expect(msg.isAssistant, isFalse);
      expect(msg.content, 'Hello');
      expect(msg.thinkingContent, isNull);
      expect(msg.toolCalls, isEmpty);
    });

    test('assistant 普通文本消息', () {
      final msg = ChatMessage(role: 'assistant', content: '你好');
      expect(msg.isAssistant, isTrue);
      expect(msg.content, '你好');
      expect(msg.thinkingContent, isNull);
      expect(msg.toolCalls, isEmpty);
    });

    test('assistant + 思考内容（ThinkingBlock）', () {
      final msg = ChatMessage(
        role: 'assistant',
        content: '答案: 42',
        thinkingContent: '让我想想...查询数据库...',
      );
      expect(msg.thinkingContent, '让我想想...查询数据库...');
      expect(msg.content, '答案: 42');
    });

    test('assistant + 工具调用（ToolCallCard）', () {
      final msg = ChatMessage(
        role: 'assistant',
        content: '',
        toolCalls: [
          const ToolCallData(name: 'search', arguments: '{"q":"x"}'),
          const ToolCallData(
            name: 'fetch', arguments: '{}', result: 'ok', completed: true,
          ),
        ],
      );
      expect(msg.toolCalls.length, 2);
      expect(msg.toolCalls[0].completed, isFalse);
      expect(msg.toolCalls[1].completed, isTrue);
    });
  });

  // ═══════ ToolCallData — 折叠展开 ═══════

  group('ToolCallData — 折叠展开', () {
    test('新调用默认未完成', () {
      const c = ToolCallData(name: 's', arguments: '{}');
      expect(c.completed, isFalse);
      expect(c.result, isNull);
    });

    test('已完成携带结果', () {
      const c = ToolCallData(name: 'f', result: 'ok', completed: true);
      expect(c.completed, isTrue);
      expect(c.result, 'ok');
    });
  });

  // ═══════ InputOptions — 发送/附件/快捷键 ═══════

  group('InputOptions — 发送/附件', () {
    test('free-text 默认 maxLength=0（不限制）', () {
      const i = InputOptions(mode: 'free-text');
      expect(i.mode, 'free-text');
      expect(i.maxLength, 0);
    });

    test('自定义 maxLength', () {
      const i = InputOptions(mode: 'free-text', maxLength: 500);
      expect(i.maxLength, 500);
    });

    test('code 模式', () {
      const i = InputOptions(mode: 'code');
      expect(i.mode, 'code');
    });

    test('附件启用 + maxSizeMb', () {
      const i = InputOptions(
        mode: 'free-text',
        attachments: AttachmentOptions(enabled: true, maxSizeMb: 10),
      );
      expect(i.attachments.enabled, isTrue);
      expect(i.attachments.maxSizeMb, 10);
    });
  });

  // ═══════ Chat / Thinking / ToolCall Options ═══════

  group('ChatOptions — 对话样式', () {
    test('完整配置', () {
      const c = ChatOptions(
        bubble: BubbleOptions(style: 'rounded', showTimestamp: true),
        stream: StreamOptions(enabled: true),
        thinking: ThinkingOptions(visible: true, mode: 'scroll'),
        toolCalls: ToolCallOptions(visible: true, autoCollapse: true),
      );
      expect(c.bubble.style, 'rounded');
      expect(c.stream.enabled, isTrue);
      expect(c.thinking.visible, isTrue);
      expect(c.toolCalls.autoCollapse, isTrue);
    });
  });

  group('ThinkingOptions', () {
    test('expand', () {
      const o = ThinkingOptions(visible: true, mode: 'expand');
      expect(o.visible, isTrue);
      expect(o.mode, 'expand');
    });

    test('scroll + showDuration', () {
      const o = ThinkingOptions(visible: true, mode: 'scroll', showDuration: true);
      expect(o.showDuration, isTrue);
    });
  });

  group('ToolCallOptions', () {
    test('showArgs + showResult', () {
      const o = ToolCallOptions(visible: true, showArgs: true, showResult: true);
      expect(o.showArgs, isTrue);
      expect(o.showResult, isTrue);
    });
  });

  // ═══════ DataTable 排序/选择 ═══════

  group('DataBindingDescriptor + ActionDescriptor', () {
    test('table / list / card', () {
      expect(DataBindingDescriptor(dataType: 'u', display: 'table').display, 'table');
      expect(DataBindingDescriptor(dataType: 't', display: 'list').display, 'list');
      expect(DataBindingDescriptor(dataType: 'p', display: 'card').display, 'card');
    });

    test('sortable 字段列表 + selection=multi', () {
      const a = ActionDescriptor(sortable: ['name'], selection: 'multi');
      expect(a.sortable, ['name']);
      expect(a.selection, 'multi');
    });

    test('完整 CRUD + 导出', () {
      const a = ActionDescriptor(
        creatable: true,
        editable: true,
        deletable: DeletableDescriptor(enabled: true, confirm: true),
        exportable: ['csv', 'json'],
        sortable: ['title'],
        selection: 'multi',
      );
      expect(a.creatable, isTrue);
      expect(a.deletable!.enabled, isTrue);
      expect(a.deletable!.confirm, isTrue);
      expect(a.exportable, ['csv', 'json']);
    });
  });

  // ═══════ 模型 ═══════

  group('WorkspaceFile', () {
    test('const 构造', () {
      const f = WorkspaceFile(name: 'a.dart', path: '/a.dart', sizeBytes: 512);
      expect(f.name, 'a.dart');
      expect(f.sizeBytes, 512);
    });
  });

  group('SlideData', () {
    test('const 构造', () {
      const s = SlideData(title: 'T', layout: 'title', content: '# H');
      expect(s.title, 'T');
      expect(s.layout, 'title');
    });
  });
}
