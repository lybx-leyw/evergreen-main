/// MarketView 审核闸 + 评分接入测试（M5-6 / M5-9 / M5-10）。
import 'package:evergreen_base/core/module/plugin_registry.dart';
import 'package:evergreen_base/core/module/plugin_review.dart';
import 'package:evergreen_base/renderer/components/shared/widgets/models.dart';
import 'package:evergreen_base/renderer/page/market_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

PluginDescriptor _desc(String id, String name) => PluginDescriptor(
      id: id,
      name: name,
      author: 'author_$id',
      stars: 42,
    );

void main() {
  group('MarketView 审核闸（M5-6）', () {
    testWidgets('传 reviewQueue 后仅白名单插件可见', (tester) async {
      final queue = ReviewQueue();
      queue.submit(ReviewRecord.fromJson(
          {'pluginId': 'ok', 'status': 'approved', 'reason': 'm'}));

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MarketView(
            plugins: [_desc('ok', '可展示插件'), _desc('no', '不可展示插件')],
            reviewQueue: queue,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('可展示插件'), findsOneWidget);
      expect(find.text('不可展示插件'), findsNothing);
    });

    testWidgets('不传 reviewQueue 时全量展示', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MarketView(
            plugins: [_desc('a', 'A 插件'), _desc('b', 'B 插件')],
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('A 插件'), findsOneWidget);
      expect(find.text('B 插件'), findsOneWidget);
    });
  });

  group('MarketView 市场信息（M6）', () {
    testWidgets('卡片展示 GitHub 作者 + star 数（不再展示评分/下载量）', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MarketView(
            plugins: [_desc('p1', '信息插件')],
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // 展示作者名与 star 数。
      expect(find.text('author_p1'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
    });
  });

  group('registryPluginToDescriptor（t24：lattice 并入分类维度）', () {
    test('theme 型插件：lattice=theme + dimensions=[ui] → 含 AbilityDim.theme', () {
      final p = RegistryPlugin(
        id: 'warm_study',
        name: '温暖学习',
        lattice: 'theme',
        dimensions: const ['ui'],
      );
      final d = registryPluginToDescriptor(p);
      expect(d.dimensions, contains(AbilityDim.theme));
      expect(d.dimensions, contains(AbilityDim.ui)); // 原有能力标签保留
      expect(d.dimensions.length, 2); // 去重
    });

    test('theme 型插件无能力标签时也能落到 theme 分类', () {
      final d = registryPluginToDescriptor(RegistryPlugin(
        id: 'warm_study2',
        name: '主题二',
        lattice: 'theme',
      ));
      expect(d.dimensions, [AbilityDim.theme]);
    });

    test('module 型插件 dimensions 已含 ui 时不重复追加', () {
      final d = registryPluginToDescriptor(RegistryPlugin(
        id: 'view',
        name: '我的成绩单',
        lattice: 'module',
        dimensions: const ['ui'],
      ));
      expect(d.dimensions, [AbilityDim.ui]);
    });

    test('未知 lattice 保持既有 dimensions 不变', () {
      final d = registryPluginToDescriptor(RegistryPlugin(
        id: 'x',
        name: 'X',
        dimensions: const ['ui', 'data'],
      ));
      expect(d.dimensions, [AbilityDim.ui, AbilityDim.data]);
    });

    test('data-source / agent-tool lattice 映射', () {
      expect(
        registryPluginToDescriptor(RegistryPlugin(
                id: 'ds', name: 'DS', lattice: 'data-source'))
            .dimensions,
        [AbilityDim.data],
      );
      expect(
        registryPluginToDescriptor(RegistryPlugin(
                id: 'ag', name: 'AG', lattice: 'agent-tool'))
            .dimensions,
        [AbilityDim.agent],
      );
    });
  });
}
