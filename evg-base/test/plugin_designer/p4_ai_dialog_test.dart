/// A-P4 Batch 2 测试：AI 生成对话框（B1 入口回调 / B2 友好失败）。
///
/// 注入 fake [agent.Provider]，不触发真实网络，也不驱动 PluginDesignerView
/// 的 PluginPreloader 常驻定时器（见 FAIL #13）。
library;
import 'package:evergreen_base/core/agent/agent.dart' as agent;
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/models/design_document.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/services/ai_design_generator.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/view/ai_generate_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 受控 LLM 通道。
class _FakeProvider implements agent.Provider {
  _FakeProvider(this.responseText);
  final String responseText;

  @override
  String get name => 'fake';

  @override
  Stream<agent.ProviderEvent> chat({
    required List<agent.Message> messages,
    List<Map<String, dynamic>> tools = const [],
  }) async* {
    yield agent.ProviderEvent.content(responseText);
    yield agent.ProviderEvent.done();
  }
}

const _validJson =
    '{"plugin_id":"ai-demo","plugin_name":"AI 演示插件","version":"1.0.0",'
    '"pages":[{"id":"page_0","label":"首页","layout_preset":"grid",'
    '"default":true,"hideTab":false,"slots":[]}]}';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('B1 生成成功 → onGenerated 收到合法 doc', (tester) async {
    DesignDocument? captured;
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: AiGenerateDialog(
          onGenerated: (d) => captured = d,
          generator: AiDesignGenerator(_FakeProvider(_validJson)),
        ),
      ),
    ));
    await tester.enterText(find.byType(TextField), '做一个插件');
    await tester.tap(find.text('生成'));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!.pluginId, 'ai-demo');
    expect(captured!.pluginName, 'AI 演示插件');
  });

  testWidgets('B1 失败路径 → 显示友好 SnackBar（不崩溃）', (tester) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: AiGenerateDialog(
            onGenerated: (_) {},
            generator: AiDesignGenerator(_FakeProvider('我不是合法 JSON')),
          ),
        ),
      ),
    ));
    await tester.enterText(find.byType(TextField), '做一个插件');
    await tester.tap(find.text('生成'));
    await tester.pumpAndSettle();

    expect(find.textContaining('生成失败'), findsWidgets);
  });

  testWidgets('空输入 → 不触发生成（按钮可重复）', (tester) async {
    var calls = 0;
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: AiGenerateDialog(
          onGenerated: (_) => calls++,
          generator: AiDesignGenerator(_FakeProvider(_validJson)),
        ),
      ),
    ));
    // 不输入任何文本，直接点生成
    await tester.tap(find.text('生成'));
    await tester.pumpAndSettle();

    expect(calls, 0);
  });

  testWidgets('C1 改稿模式 → 显示基于当前设计的提示横幅', (tester) async {
    final base = DesignDocument(pluginId: 'old', pluginName: '旧插件');
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: AiGenerateDialog(
          onGenerated: (_) {},
          baseDoc: base,
          generator: AiDesignGenerator(_FakeProvider(_validJson)),
        ),
      ),
    ));

    expect(find.textContaining('改稿模式'), findsWidgets);
    expect(find.textContaining('旧插件'), findsWidgets);
  });
}
