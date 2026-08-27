/// SkinDescriptor 全量测试——type 校验 / 未知键静默忽略 / 缺省段 / 各 DIY 段解析。
library;

import 'package:test/test.dart';

import '../skin_descriptor.dart';

// ═══════ helpers ═══════

Map<String, dynamic> _minimal() => {
      'type': 'skin',
      'id': 'evergreen-logo',
      'name': '绿意 Logo 皮肤',
    };

// ═══════ SkinDescriptor ═══════

void main() {
  group('SkinDescriptor.fromJson', () {
    test('最小合法 JSON（type/id/name）', () {
      final s = SkinDescriptor.fromJson(_minimal());
      expect(s.id, 'evergreen-logo');
      expect(s.name, '绿意 Logo 皮肤');
      expect(s.version, '');
      expect(s.description, isNull);
    });

    test('type 缺失抛 FormatException', () {
      expect(
        () => SkinDescriptor.fromJson({'id': 'x', 'name': 'X'}),
        throwsFormatException,
      );
    });

    test('type 非 skin 抛 FormatException', () {
      expect(
        () => SkinDescriptor.fromJson({'type': 'theme', 'id': 'x'}),
        throwsFormatException,
      );
    });

    test('未知键静默忽略，不抛异常', () {
      final s = SkinDescriptor.fromJson({
        ..._minimal(),
        'someUnknownKey': {'nested': 1},
        'another': 'value',
        'colors': {'primary': '#FF0000'}, // 与 theme 混淆的键也不影响
      });
      expect(s.id, 'evergreen-logo');
      expect(s.toJson()['someUnknownKey'], isNull); // 未知键不入序列化
      expect(s.toJson()['colors'], isNull);
    });

    test('id/name 缺失回退空串', () {
      final s = SkinDescriptor.fromJson({'type': 'skin'});
      expect(s.id, '');
      expect(s.name, '');
    });

    test('toJson 往返一致性（含 DIY 段）', () {
      final json = {
        ..._minimal(),
        'version': '1.0.0',
        'description': 'desc',
        'background': {'type': 'gradient', 'color': '#FFFFFF'},
        'buttons': {'inputBar': {'clear': false}},
        'thinking': {'title': '推理', 'colors': {'header': '#F57C00'}},
      };
      final s = SkinDescriptor.fromJson(json);
      final restored = SkinDescriptor.fromJson(s.toJson());
      expect(restored.id, s.id);
      expect(restored.name, s.name);
      expect(restored.version, '1.0.0');
      expect(restored.toJson(), s.toJson());
    });
  });

  group('SkinDescriptor 段解析', () {
    test('assets 段', () {
      final s = SkinDescriptor.fromJson({
        ..._minimal(),
        'assets': {
          'logoDesktop': 'logo_desktop.svg',
          'logoMobile': 'logo_mobile.svg',
          'emptyIcon': 'empty_icon.svg',
          'backgroundImage': 'bg_fallback.svg',
        },
      });
      expect(s.logoDesktop, 'logo_desktop.svg');
      expect(s.logoMobile, 'logo_mobile.svg');
      expect(s.emptyIcon, 'empty_icon.svg'); // R2-4 空状态图标（横竖屏一致）
      expect(s.backgroundImage, 'bg_fallback.svg');
    });

    test('assets 段：R2-4 缺省 emptyIcon 为 null（空状态回退旧键）', () {
      final s = SkinDescriptor.fromJson({
        ..._minimal(),
        'assets': {'logoDesktop': 'logo_desktop.svg'},
      });
      expect(s.emptyIcon, isNull);
    });

    test('background 段：solid', () {
      final s = SkinDescriptor.fromJson({
        ..._minimal(),
        'background': {'type': 'solid', 'color': '#FFFFFF'},
      });
      expect(s.backgroundType, 'solid');
      expect(s.backgroundColor, '#FFFFFF');
      expect(s.backgroundGradientFrom, isNull);
      expect(s.backgroundImageDesktop, isNull);
      expect(s.backgroundImageMobile, isNull);
    });

    test('background 段：gradient', () {
      final s = SkinDescriptor.fromJson({
        ..._minimal(),
        'background': {
          'type': 'gradient',
          'gradient': {'from': '#E8F5E9', 'to': '#FFFFFF', 'angle': 135},
        },
      });
      expect(s.backgroundType, 'gradient');
      expect(s.backgroundGradientFrom, '#E8F5E9');
      expect(s.backgroundGradientTo, '#FFFFFF');
      expect(s.backgroundGradientAngle, 135.0);
    });

    test('background 段：image 分横竖屏（R2-4）', () {
      final s = SkinDescriptor.fromJson({
        ..._minimal(),
        'background': {
          'type': 'image',
          'imageDesktop': 'bg_desktop.svg',
          'imageMobile': 'bg_mobile.svg',
        },
      });
      expect(s.backgroundType, 'image');
      expect(s.backgroundImageDesktop, 'bg_desktop.svg');
      expect(s.backgroundImageMobile, 'bg_mobile.svg');
      expect(s.backgroundColor, isNull); // image 与纯色互斥
    });

    test('background 段：image 缺省分屏键为 null（可回退 assets.backgroundImage）',
        () {
      final s = SkinDescriptor.fromJson({
        ..._minimal(),
        'background': {'type': 'image'},
      });
      expect(s.backgroundType, 'image');
      expect(s.backgroundImageDesktop, isNull);
      expect(s.backgroundImageMobile, isNull);
    });

    test('buttons 段：inputBar / messageActions', () {
      final s = SkinDescriptor.fromJson({
        ..._minimal(),
        'buttons': {
          'inputBar': {
            'workspace': true,
            'webSearch': false,
            'clear': true,
          },
          'messageActions': {'copy': false},
        },
      });
      expect(s.inputBarVisible('workspace'), isTrue);
      expect(s.inputBarVisible('webSearch'), isFalse);
      expect(s.inputBarVisible('clear'), isTrue);
      expect(s.inputBarVisible('skills'), isNull); // 未配置 → 缺省显示
      expect(s.messageActionVisible('copy'), isFalse);
      expect(s.messageActionVisible('regenerate'), isNull);
    });

    test('thinking 段：colors 子段与扁平写法', () {
      final s = SkinDescriptor.fromJson({
        ..._minimal(),
        'thinking': {
          'title': '推理过程',
          'colors': {
            'header': '#F57C00',
            'containerBackground': '#FFF8E1',
            'containerBorder': '#FFE082',
            'contentText': '#795548',
            'chipMemoryBg': '#F3E5F5',
          },
        },
      });
      expect(s.thinkingTitle, '推理过程');
      expect(s.thinkingColor('header'), '#F57C00');
      expect(s.thinkingColor('containerBackground'), '#FFF8E1');
      expect(s.thinkingColor('containerBorder'), '#FFE082');
      expect(s.thinkingColor('contentText'), '#795548');
      expect(s.thinkingColor('chipMemoryBg'), '#F3E5F5');
      expect(s.thinkingColor('chipSkillBg'), isNull); // 未配置
    });

    test('thinking 段：扁平写法兼容（thinking.header）', () {
      final s = SkinDescriptor.fromJson({
        ..._minimal(),
        'thinking': {'header': '#FF0000'},
      });
      expect(s.thinkingColor('header'), '#FF0000');
    });

    test('bubble 段', () {
      final s = SkinDescriptor.fromJson({
        ..._minimal(),
        'bubble': {
          'userBackgroundColor': '#E3F2FD',
          'assistantBackground': null,
          'borderRadius': 20,
          'maxWidthRatio': 0.8,
        },
      });
      expect(s.bubbleUserBackgroundColor, '#E3F2FD');
      expect(s.bubbleColor('userBackgroundColor'), '#E3F2FD');
      expect(s.bubbleAssistantBackground, isNull);
      expect(s.bubbleBorderRadius, 20.0);
      expect(s.bubbleMaxWidthRatio, 0.8);
    });

    test('bubble 段：R2-3 新键优先，旧键 userBackground 向后兼容', () {
      final legacy = SkinDescriptor.fromJson({
        ..._minimal(),
        'bubble': {'userBackground': '#E07A3F'},
      });
      expect(legacy.bubbleUserBackground, '#E07A3F');
      expect(legacy.bubbleUserBackgroundColor, '#E07A3F'); // 兼容旧键
      final both = SkinDescriptor.fromJson({
        ..._minimal(),
        'bubble': {
          'userBackground': '#E07A3F',
          'userBackgroundColor': '#E3F2FD',
        },
      });
      expect(both.bubbleUserBackgroundColor, '#E3F2FD'); // 新键优先
    });

    test('avatar / emptyState 段', () {
      final s = SkinDescriptor.fromJson({
        ..._minimal(),
        'avatar': {
          'user': '#E07A3F',
          'userBackgroundColor': '#C8E6C9',
          'assistant': 'logo_desktop.svg',
        },
        'emptyState': {'logo': 'logo_mobile.svg', 'title': '你好呀'},
      });
      expect(s.avatarUser, '#E07A3F');
      expect(s.avatarUserBackgroundColor, '#C8E6C9');
      expect(s.avatarColor('userBackgroundColor'), '#C8E6C9');
      expect(s.avatarAssistant, 'logo_desktop.svg');
      expect(s.emptyStateLogo, 'logo_mobile.svg');
      expect(s.emptyStateTitle, '你好呀');
    });

    test('顶层功能色快捷覆盖', () {
      final s = SkinDescriptor.fromJson({
        ..._minimal(),
        'effortColor': '#FF0000',
        'toolActiveColor': '#00FF00',
        'codeInline': '#AA0000',
        'codeBlockBackground': '#EEEEEE',
        'bubble': {'codeInline': '#BB0000'},
      });
      expect(s.effortColor, '#FF0000');
      expect(s.toolActiveColor, '#00FF00');
      expect(s.codeInline, '#AA0000'); // 顶层优先于 bubble 子段
      expect(s.codeBlockBackground, '#EEEEEE');
    });

    test('非法类型字段静默忽略（bool 当字符串 / 数字当颜色）', () {
      final s = SkinDescriptor.fromJson({
        ..._minimal(),
        'background': {'type': 'solid', 'color': 12345},
        'bubble': {'borderRadius': 'not-a-number'},
      });
      expect(s.backgroundColor, isNull);
      expect(s.bubbleBorderRadius, isNull);
    });
  });

  group('SkinDescriptor 其它', () {
    test('withSourceDir 复制并标记插件目录', () {
      final s = SkinDescriptor.fromJson(_minimal());
      final loaded = s.withSourceDir('/tmp/plugins/evergreen-logo');
      expect(loaded.sourceDir, '/tmp/plugins/evergreen-logo');
      expect(loaded.id, s.id);
      expect(s.sourceDir, isNull); // 原实例不变
    });

    test('const 构造 — 最小皮肤包', () {
      const s = SkinDescriptor(id: 'skin-default', name: '默认皮肤');
      expect(s.id, 'skin-default');
      expect(s.version, '');
      expect(s.raw, isEmpty);
    });

    test('fromJsonString — 有效 JSON', () {
      final s = SkinDescriptor.fromJsonString(
          '{"type":"skin","id":"x","name":"X"}');
      expect(s.id, 'x');
    });

    test('fromJsonString — 非法 JSON 抛 FormatException', () {
      expect(
        () => SkinDescriptor.fromJsonString('not json'),
        throwsFormatException,
      );
    });

    test('toString 摘要', () {
      final s = SkinDescriptor.fromJson(_minimal());
      expect(s.toString(), 'SkinDescriptor(evergreen-logo, 绿意 Logo 皮肤)');
    });
  });
}
