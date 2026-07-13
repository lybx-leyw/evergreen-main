import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/core/module/module_registry.dart';
import 'package:evergreen_base/providers.dart';
import 'package:evergreen_base/renderer/components/marketplace/marketplace_slot.dart';

void main() {
  group('P5 — 侧边栏 manifest 解析测试', () {
    test('marketplace manifest 能被 ModuleDescriptor.fromJson 解析', () {
      final f = File('../plugins/marketplace/module/manifest.json');
      expect(f.existsSync(), isTrue, reason: 'marketplace manifest.json 文件不存在');
      final json = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      expect(json['type'], 'module');
      final d = ModuleDescriptor.fromJson(json);
      expect(d.id, 'marketplace');
      expect(d.name, '插件市场');
      expect(d.icon, isNotNull);
      expect(d.nav.sidebar, isNotNull);
      expect(d.nav.sidebar!.section, '系统');
      expect(d.pages.length, 1);
      expect(d.pages.first.layout.slots.length, 1);
      expect(d.pages.first.layout.slots.keys.first, 'main');
      expect(d.pages.first.layout.slots.values.first.component!.type, 'marketplace');
      expect(d.hasSidebar, isTrue, reason: 'marketplace 应该出现在侧边栏');
    });

    test('plugin-designer manifest 能被 ModuleDescriptor.fromJson 解析', () {
      final f = File('../plugins/plugin-designer/module/manifest.json');
      expect(f.existsSync(), isTrue, reason: 'plugin-designer manifest.json 文件不存在');
      final json = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      expect(json['type'], 'module');
      final d = ModuleDescriptor.fromJson(json);
      expect(d.id, 'plugin-designer');
      expect(d.name, contains('全流程插件创作'));
      expect(d.icon, isNotNull);
      expect(d.nav.sidebar, isNotNull);
      expect(d.nav.sidebar!.section, '系统');
      expect(d.pages.length, 1);
      expect(d.hasSidebar, isTrue, reason: 'plugin-designer 应该出现在侧边栏');
    });

    test('ModuleRegistry 注册 + seal 后 navGroups 包含 marketplace', () {
      final f = File('../plugins/marketplace/module/manifest.json');
      final json = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      final d = ModuleDescriptor.fromJson(json);

      // 模拟 ModuleLoader 的行为
      final registry = ModuleRegistry();
      registry.register(d);
      registry.seal();

      final modules = registry.modules;
      expect(modules.length, 1);
      expect(modules.first.id, 'marketplace');

      final navGroups = registry.navGroups;
      expect(navGroups.isNotEmpty, isTrue, reason: 'navGroups 不应为空');
      expect(navGroups.first.$1.label, '系统');
      expect(navGroups.first.$2.length, 1);
      expect(navGroups.first.$2.first.moduleId, 'marketplace');
    });

    test('ModuleRegistry navFlat 包含 marketplace', () {
      final f = File('../plugins/marketplace/module/manifest.json');
      final json = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      final d = ModuleDescriptor.fromJson(json);

      final registry = ModuleRegistry();
      registry.register(d);
      registry.seal();

      final flat = registry.navFlat;
      expect(flat.length, 1);
      expect(flat.first.moduleId, 'marketplace');
    });

    test('P5+ — 插件市场能识别本地插件（与项目根 _findProjectRoot 一致）', () {
      // 模拟 main.dart 的 _findProjectRoot 逻辑：plugins/ 位于项目根上级
      // 项目根 = evg-base（pubspec.yaml 所在），所以 plugins/ = ../plugins
      final pluginsDir = p.join(Directory.current.path, '..', 'plugins').replaceAll(r'\', '/');
      debugPrint('[Test] 模拟扫描目录: $pluginsDir');

      final dir = Directory(pluginsDir);
      expect(dir.existsSync(), isTrue, reason: 'plugins/ 目录不存在: $pluginsDir');

      int moduleCount = 0;
      for (final entity in dir.listSync()) {
        if (entity is! Directory) continue;
        if (entity.path.contains(r'\.')) continue;

        final mp = File(p.join(entity.path, 'module', 'manifest.json'));
        if (!mp.existsSync()) continue;

        try {
          final json = jsonDecode(mp.readAsStringSync()) as Map<String, dynamic>;
          if (json['type'] != 'module') continue;
          final d = ModuleDescriptor.fromJson(json);
          if (d.id == 'marketplace' || d.id == 'plugin-designer') {
            // 跳过 marketplace 自身和 plugin-designer，验证其它模块能被识别
            continue;
          }
          moduleCount++;
        } catch (_) {
          // 解析失败的 manifest 静默跳过
        }
      }

      expect(moduleCount, greaterThan(0),
          reason: 'plugins/ 目录下应至少识别出一个有效 module 类型的插件');
      debugPrint('[Test] 识别出 $moduleCount 个有效本地插件');
    });

    testWidgets('P5++ — MarketplaceSlot 在 Riverpod 注入 pluginsDirProvider 后能识别本地插件',
        (tester) async {
      // 关键：用户截图显示侧边栏已出现但 UI 仍为 0 个插件。
      // 此测试验证：当 pluginsDirProvider 注入正确路径时，MarketplaceSlot 能找到插件。
      final pluginsDir = p.join(Directory.current.path, '..', 'plugins').replaceAll(r'\', '/');
      debugPrint('[Test] widget 测试注入 pluginsDir: $pluginsDir');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pluginsDirProvider.overrideWithValue(pluginsDir),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SizedBox(
                height: 800,
                child: MarketplaceSlot(),
              ),
            ),
          ),
        ),
      );
      // 等待 _loadPlugins 完成
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // 找到 "0 个插件" 文本 → 失败
      // 不存在 → 通过（说明 _allPlugins 非空）
      expect(find.text('0 个插件'), findsNothing,
          reason: 'pluginsDirProvider 注入正确路径后，MarketplaceSlot 应能识别出本地插件');
      expect(find.text('暂无本地插件'), findsNothing,
          reason: '不应显示"暂无本地插件"');
      // 至少出现一个 LocalPluginCard（其内部有"隐藏侧栏"或"显示侧栏"或"卸载"文案）
      final hasPluginCards = find.text('隐藏侧栏').evaluate().isNotEmpty ||
          find.text('显示侧栏').evaluate().isNotEmpty ||
          find.text('卸载').evaluate().isNotEmpty;
      expect(hasPluginCards, isTrue, reason: '应至少显示一个 LocalPluginCard');
    });
  });
}
