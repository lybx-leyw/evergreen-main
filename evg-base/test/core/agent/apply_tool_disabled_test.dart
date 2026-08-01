import 'package:evergreen_base/core/agent/tool.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/interaction/chat/chat_controller_view.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('applyToolDisabledSetToRegistry', () {
    Registry build() {
      final r = Registry();
      for (final n in ['a', 'b', 'c']) {
        r.register(SimpleTool(
          name: n,
          description: '',
          schema: {},
          execute: (_) async => '',
        ));
      }
      return r;
    }

    test('禁用集合内的工具被关闭，其余保持启用', () {
      final registry = build();

      applyToolDisabledSetToRegistry(registry, {'b'});

      expect(registry.isEnabled('a'), isTrue);
      expect(registry.isEnabled('b'), isFalse);
      expect(registry.isEnabled('c'), isTrue);
      expect(
        registry.enabled().map((t) => t.name).toList(),
        equals(['a', 'c']),
      );
    });

    test('从禁用集合移除后（重新启用）真正生效', () {
      final registry = build();
      registry.disable('a');
      expect(registry.isEnabled('a'), isFalse);

      applyToolDisabledSetToRegistry(registry, {});

      expect(registry.isEnabled('a'), isTrue);
    });

    test('禁用集合含未注册工具时不抛异常', () {
      final registry = build();

      expect(() => applyToolDisabledSetToRegistry(registry, {'x'}),
          returnsNormally);
      expect(registry.isEnabled('a'), isTrue);
    });
  });

  group('applyWebSearchEnabledToRegistry', () {
    Registry build() {
      final r = Registry();
      for (final n in ['web_search', 'web_fetch', 'other']) {
        r.register(SimpleTool(
          name: n,
          description: '',
          schema: {},
          execute: (_) async => '',
        ));
      }
      return r;
    }

    test('开启 → web_search/web_fetch 启用', () {
      final registry = build();
      registry.disable('web_search');
      registry.disable('web_fetch');

      applyWebSearchEnabledToRegistry(registry, true);

      expect(registry.isEnabled('web_search'), isTrue);
      expect(registry.isEnabled('web_fetch'), isTrue);
      expect(registry.isEnabled('other'), isTrue);
    });

    test('关闭 → web_search/web_fetch 禁用', () {
      final registry = build();

      applyWebSearchEnabledToRegistry(registry, false);

      expect(registry.isEnabled('web_search'), isFalse);
      expect(registry.isEnabled('web_fetch'), isFalse);
      expect(registry.isEnabled('other'), isTrue);
    });

    test('web_fetch 未注册时不抛异常', () {
      final registry = Registry();
      registry.register(SimpleTool(
        name: 'web_search',
        description: '',
        schema: {},
        execute: (_) async => '',
      ));

      expect(() => applyWebSearchEnabledToRegistry(registry, true),
          returnsNormally);
      expect(registry.isEnabled('web_search'), isTrue);
    });
  });
}
