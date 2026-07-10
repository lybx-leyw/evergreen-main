/// Sprint 2 页面和组件测试。
///
/// 覆盖：
/// - widgets/models.dart 新增数据模型（PluginDescriptor, AbilityDim,
///   PluginPermission, InstallProgress, SettingsItem, SettingsGroup,
///   PluginPermissionSnapshot）
/// - widgets/ 新增组件（AbilityTag, InstallProgressWidget, NotificationCard）
/// - shared/ 新增页面（MarketView, PluginDetailView, MyPluginsView, SettingsView,
///   PermissionManagementView）
/// - compositions/workspace_page.dart
library;

import 'package:evergreen_base/renderer/components/shared/widgets/models.dart';
import 'package:evergreen_base/renderer/components/shared/widgets/ability_tag.dart';
import 'package:evergreen_base/renderer/components/shared/widgets/install_progress.dart';
import 'package:evergreen_base/renderer/components/shared/widgets/notification_card.dart';
import 'package:evergreen_base/renderer/page/market_view.dart';
import 'package:evergreen_base/renderer/page/plugin_detail_view.dart';
import 'package:evergreen_base/renderer/page/my_plugins_view.dart';
import 'package:evergreen_base/renderer/page/settings_view.dart';
import 'package:evergreen_base/renderer/page/composite_view.dart';
import 'package:evergreen_base/renderer/page/permission_management_view.dart';
// workspace_page removed in renderer refactor
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

// ── Helper: 构建测试用 PluginDescriptor ──

PluginDescriptor _testPlugin({
  String id = 'p1',
  String name = 'AI 代码助手',
  String desc = '智能代码补全',
  String longDesc = '基于大语言模型的智能代码助手。',
  String author = 'Evergreen Labs',
  String version = '2.1.0',
  List<AbilityDim> dims = const [AbilityDim.agent, AbilityDim.skill],
  List<PluginPermission> perms = const [
    PluginPermission(name: '网络访问', level: PermissionLevel.danger),
    PluginPermission(name: '文件读写', level: PermissionLevel.warning),
    PluginPermission(name: '剪贴板', level: PermissionLevel.safe),
  ],
  int screenshots = 3,
  int installs = 2300,
  double rating = 4.8,
  bool installed = false,
  bool hasUpdate = false,
}) {
  return PluginDescriptor(
    id: id,
    name: name,
    description: desc,
    longDescription: longDesc,
    author: author,
    version: version,
    dimensions: dims,
    permissions: perms,
    screenshotCount: screenshots,
    installCount: installs,
    rating: rating,
    installed: installed,
    hasUpdate: hasUpdate,
  );
}

Widget _materialApp(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

// ═══════════════════════════════════════════════════════════════════
// 1. 数据模型测试
// ═══════════════════════════════════════════════════════════════════

void main() {
  SharedPreferences.setMockInitialValues({});
  group('AbilityDim', () {
    test('6 个枚举值', () {
      expect(AbilityDim.values.length, 6);
      expect(AbilityDim.values, contains(AbilityDim.agent));
      expect(AbilityDim.values, contains(AbilityDim.ui));
      expect(AbilityDim.values, contains(AbilityDim.data));
      expect(AbilityDim.values, contains(AbilityDim.theme));
      expect(AbilityDim.values, contains(AbilityDim.settings));
      expect(AbilityDim.values, contains(AbilityDim.skill));
    });

    test('label 返回英文缩写', () {
      expect(AbilityDim.agent.label, 'Agent');
      expect(AbilityDim.ui.label, 'UI');
      expect(AbilityDim.data.label, 'Data');
    });

    test('displayName 返回中文名', () {
      expect(AbilityDim.agent.displayName, '智能体');
      expect(AbilityDim.theme.displayName, '主题');
      expect(AbilityDim.skill.displayName, '技能');
    });
  });

  group('PluginPermission', () {
    test('默认 level=safe, granted=true', () {
      const p = PluginPermission(name: '存储');
      expect(p.level, PermissionLevel.safe);
      expect(p.levelLabel, '安全');
      expect(p.granted, isTrue);
    });

    test('danger 级别', () {
      const p = PluginPermission(name: 'Shell', level: PermissionLevel.danger);
      expect(p.levelLabel, '高危');
    });

    test('copyWith', () {
      const p = PluginPermission(name: '存储', level: PermissionLevel.safe, granted: true);
      final revoked = p.copyWith(granted: false);
      expect(revoked.granted, isFalse);
      expect(revoked.name, '存储');
      expect(revoked.level, PermissionLevel.safe);
    });
  });

  group('PluginPermissionSnapshot', () {
    test('计数统计', () {
      const snap = PluginPermissionSnapshot(
        pluginId: 'p1',
        pluginName: '测试',
        permissions: [
          PluginPermission(name: 'a', level: PermissionLevel.safe, granted: true),
          PluginPermission(name: 'b', level: PermissionLevel.safe, granted: true),
          PluginPermission(name: 'c', level: PermissionLevel.warning, granted: true),
          PluginPermission(name: 'd', level: PermissionLevel.danger, granted: false),
        ],
      );
      expect(snap.safeCount, 2);
      expect(snap.warningCount, 1);
      expect(snap.dangerCount, 1);
      expect(snap.grantedCount, 3);
    });

    test('空权限列表', () {
      const snap = PluginPermissionSnapshot(
        pluginId: 'p1',
        pluginName: '测试',
        permissions: [],
      );
      expect(snap.safeCount, 0);
      expect(snap.dangerCount, 0);
      expect(snap.grantedCount, 0);
    });
  });

  group('PluginDescriptor', () {
    test('完整构造', () {
      final p = _testPlugin();
      expect(p.id, 'p1');
      expect(p.name, 'AI 代码助手');
      expect(p.dimensions.length, 2);
      expect(p.permissions.length, 3);
      expect(p.installed, isFalse);
    });

    test('已安装 + 待更新', () {
      final p = _testPlugin(installed: true, hasUpdate: true);
      expect(p.installed, isTrue);
      expect(p.hasUpdate, isTrue);
    });

    test('无截图', () {
      final p = _testPlugin(screenshots: 0);
      expect(p.screenshotCount, 0);
    });
  });

  group('InstallProgress + InstallStatus', () {
    test('InstallStatus label', () {
      expect(InstallStatus.preparing.label, '准备安装...');
      expect(InstallStatus.downloading.label, '下载中...');
      expect(InstallStatus.installing.label, '安装中...');
      expect(InstallStatus.completed.label, '安装完成');
      expect(InstallStatus.failed.label, '安装失败');
    });

    test('InstallProgress 构造', () {
      const p = InstallProgress(
        pluginId: 'p1',
        progress: 0.5,
        status: InstallStatus.downloading,
      );
      expect(p.pluginId, 'p1');
      expect(p.progress, 0.5);
      expect(p.status, InstallStatus.downloading);
    });
  });

  group('SettingsGroup + SettingsItem', () {
    test('SettingsItem toggle', () {
      var toggled = false;
      final item = SettingsItem(
        label: '深色模式',
        description: '切换主题',
        type: SettingsItemType.toggle,
        value: true,
        onToggle: (bool v) => toggled = true,
      );
      expect(item.type, SettingsItemType.toggle);
      expect(item.value, isTrue);
      item.onToggle?.call(true);
      expect(toggled, isTrue);
    });

    test('SettingsGroup', () {
      final group = SettingsGroup(
        title: '外观',
        items: [
          const SettingsItem(label: '深色模式', type: SettingsItemType.toggle),
          const SettingsItem(label: '版本', type: SettingsItemType.info),
        ],
      );
      expect(group.title, '外观');
      expect(group.items.length, 2);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 2. AbilityTag 组件测试
  // ═══════════════════════════════════════════════════════════════

  group('AbilityTag', () {
    testWidgets('渲染 6 种标签', (tester) async {
      await tester.pumpWidget(_materialApp(
        Wrap(
          children: AbilityDim.values
              .map((d) => AbilityTag(dim: d))
              .toList(),
        ),
      ));
      expect(find.text('智能体'), findsOneWidget);
      expect(find.text('界面'), findsOneWidget);
      expect(find.text('数据'), findsOneWidget);
      expect(find.text('主题'), findsOneWidget);
      expect(find.text('设置'), findsOneWidget);
      expect(find.text('技能'), findsOneWidget);
    });

    testWidgets('compact 模式仅显示缩写', (tester) async {
      await tester.pumpWidget(_materialApp(
        AbilityTag(dim: AbilityDim.agent, compact: true),
      ));
      expect(find.text('Agent'), findsOneWidget);
      expect(find.text('智能体'), findsNothing);
    });
  });

  group('AbilityTagRow', () {
    testWidgets('渲染多个标签', (tester) async {
      await tester.pumpWidget(_materialApp(
        AbilityTagRow(dims: const [AbilityDim.agent, AbilityDim.ui, AbilityDim.data]),
      ));
      expect(find.text('智能体'), findsOneWidget);
      expect(find.text('界面'), findsOneWidget);
      expect(find.text('数据'), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 3. InstallProgressWidget 测试
  // ═══════════════════════════════════════════════════════════════

  group('InstallProgressWidget', () {
    testWidgets('渲染进行中状态', (tester) async {
      await tester.pumpWidget(_materialApp(
        const InstallProgressWidget(
          progress: InstallProgress(
            pluginId: 'p1',
            progress: 0.45,
            status: InstallStatus.downloading,
          ),
        ),
      ));
      expect(find.text('下载中...'), findsOneWidget);
      expect(find.text(' 45%'), findsOneWidget);
    });

    testWidgets('渲染完成状态', (tester) async {
      await tester.pumpWidget(_materialApp(
        const InstallProgressWidget(
          progress: InstallProgress(
            pluginId: 'p1',
            progress: 1.0,
            status: InstallStatus.completed,
          ),
        ),
      ));
      expect(find.text('安装完成'), findsOneWidget);
    });

    testWidgets('渲染失败状态 + 重试按钮', (tester) async {
      var retried = false;
      await tester.pumpWidget(_materialApp(
        InstallProgressWidget(
          progress: const InstallProgress(
            pluginId: 'p1',
            progress: 0.3,
            status: InstallStatus.failed,
            message: '网络错误',
          ),
          onRetry: () => retried = true,
        ),
      ));
      expect(find.text('网络错误'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      await tester.tap(find.text('重试'));
      expect(retried, isTrue);
    });
  });

  group('InstallBadge', () {
    testWidgets('未安装不显示', (tester) async {
      await tester.pumpWidget(_materialApp(
        const InstallBadge(installed: false),
      ));
      expect(find.byType(InstallBadge), findsOneWidget);
      expect(find.text('已安装'), findsNothing);
    });

    testWidgets('已安装显示', (tester) async {
      await tester.pumpWidget(_materialApp(
        const InstallBadge(installed: true),
      ));
      expect(find.text('已安装'), findsOneWidget);
    });

    testWidgets('待更新显示', (tester) async {
      await tester.pumpWidget(_materialApp(
        const InstallBadge(installed: true, hasUpdate: true),
      ));
      expect(find.text('更新'), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 4. NotificationCard 测试
  // ═══════════════════════════════════════════════════════════════

  group('NotificationCard', () {
    testWidgets('渲染通知', (tester) async {
      var tapped = false;
      final notification = AppNotification(
        title: '插件更新',
        message: 'AI 代码助手 v2.2.0 可用',
        type: NotificationType.update,
        onTap: () => tapped = true,
      );
      await tester.pumpWidget(_materialApp(
        SingleChildScrollView(child: NotificationCard(notification: notification)),
      ));
      expect(find.text('插件更新'), findsOneWidget);
      expect(find.text('AI 代码助手 v2.2.0 可用'), findsOneWidget);
      await tester.tap(find.text('插件更新'));
      expect(tapped, isTrue);
    });

    testWidgets('5 种通知类型均可渲染', (tester) async {
      for (final type in NotificationType.values) {
        final n = AppNotification(title: 'T', message: type.name, type: type);
        await tester.pumpWidget(_materialApp(SingleChildScrollView(child: NotificationCard(notification: n))));
      }
      // 不崩溃即可
    });
  });

  group('NotificationList', () {
    testWidgets('空列表显示空状态', (tester) async {
      await tester.pumpWidget(_materialApp(
        const NotificationList(notifications: []),
      ));
      expect(find.text('暂无通知'), findsOneWidget);
    });

    testWidgets('多条通知', (tester) async {
      final list = [
        AppNotification(title: 'A', message: 'msgA'),
        AppNotification(title: 'B', message: 'msgB'),
      ];
      await tester.pumpWidget(_materialApp(NotificationList(notifications: list)));
      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 5. MarketView 测试
  // ═══════════════════════════════════════════════════════════════

  group('MarketView', () {
    testWidgets('渲染插件列表', (tester) async {
      final plugins = [
        _testPlugin(id: '1', name: '插件A'),
        _testPlugin(id: '2', name: '插件B', dims: [AbilityDim.ui]),
      ];
      await tester.pumpWidget(_materialApp(
        MarketView(plugins: plugins),
      ));
      expect(find.text('插件A'), findsOneWidget);
      expect(find.text('插件B'), findsOneWidget);
    });

    testWidgets('空列表显示空状态', (tester) async {
      await tester.pumpWidget(_materialApp(
        const MarketView(plugins: []),
      ));
      expect(find.text('没有找到匹配的插件'), findsOneWidget);
    });

    testWidgets('搜索结果计数', (tester) async {
      await tester.pumpWidget(_materialApp(
        MarketView(plugins: [
          _testPlugin(id: '1', name: 'AI 代码助手'),
          _testPlugin(id: '2', name: '数据面板', dims: [AbilityDim.data]),
        ]),
      ));
      expect(find.text('2 个插件'), findsOneWidget);
    });

    testWidgets('筛选标签显示', (tester) async {
      await tester.pumpWidget(_materialApp(
        MarketView(plugins: [_testPlugin()]),
      ));
      expect(find.text('全部'), findsOneWidget);
      expect(find.text('智能体'), findsWidgets);
      expect(find.text('界面'), findsWidgets);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 6. PluginDetailView 测试
  // ═══════════════════════════════════════════════════════════════

  group('PluginDetailView', () {
    testWidgets('渲染插件详情', (tester) async {
      final p = _testPlugin();
      await tester.pumpWidget(_materialApp(
        SingleChildScrollView(child: PluginDetailView(plugin: p)),
      ));
      expect(find.text('AI 代码助手'), findsWidgets); // title + sidebar
      expect(find.text('v2.1.0 · Evergreen Labs'), findsOneWidget);
    });

    testWidgets('已安装显示已安装按钮', (tester) async {
      final p = _testPlugin(installed: true);
      await tester.pumpWidget(_materialApp(
        SingleChildScrollView(child: PluginDetailView(plugin: p)),
      ));
      expect(find.text('✅ 已安装'), findsOneWidget);
    });

    testWidgets('待更新显示更新按钮', (tester) async {
      final p = _testPlugin(installed: true, hasUpdate: true);
      await tester.pumpWidget(_materialApp(
        SingleChildScrollView(child: PluginDetailView(plugin: p)),
      ));
      expect(find.text('更新'), findsOneWidget);
    });

    testWidgets('未安装显示安装按钮', (tester) async {
      final p = _testPlugin();
      await tester.pumpWidget(_materialApp(
        SingleChildScrollView(child: PluginDetailView(plugin: p)),
      ));
      expect(find.text('安装'), findsOneWidget);
    });

    testWidgets('安装进度显示', (tester) async {
      final p = _testPlugin();
      await tester.pumpWidget(_materialApp(
        SingleChildScrollView(
          child: PluginDetailView(
            plugin: p,
            installProgress: const InstallProgress(
              pluginId: 'p1',
              progress: 0.6,
              status: InstallStatus.installing,
            ),
          ),
        ),
      ));
      expect(find.text('安装中...'), findsOneWidget);
    });

    testWidgets('权限列表渲染', (tester) async {
      final p = _testPlugin();
      await tester.pumpWidget(_materialApp(
        SingleChildScrollView(child: PluginDetailView(plugin: p)),
      ));
      expect(find.text('网络访问'), findsOneWidget);
      expect(find.text('文件读写'), findsOneWidget);
      expect(find.text('剪贴板'), findsOneWidget);
      expect(find.text('高危'), findsOneWidget);
      expect(find.text('安全'), findsOneWidget);
    });

    testWidgets('返回按钮', (tester) async {
      var backTapped = false;
      final p = _testPlugin();
      await tester.pumpWidget(_materialApp(
        SingleChildScrollView(
          child: PluginDetailView(plugin: p, onBack: () => backTapped = true),
        ),
      ));
      await tester.tap(find.text('返回市场'));
      expect(backTapped, isTrue);
    });

    testWidgets('无截图不显示截图区', (tester) async {
      final p = _testPlugin(screenshots: 0);
      await tester.pumpWidget(_materialApp(
        SingleChildScrollView(child: PluginDetailView(plugin: p)),
      ));
      expect(find.text('🖼 截图'), findsNothing);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 7. MyPluginsView 测试
  // ═══════════════════════════════════════════════════════════════

  group('MyPluginsView', () {
    testWidgets('渲染我的插件列表', (tester) async {
      final plugins = [
        _testPlugin(id: '1', name: '插件A', installed: true),
        _testPlugin(id: '2', name: '插件B', installed: true, dims: [AbilityDim.ui]),
      ];
      await tester.pumpWidget(_materialApp(
        MyPluginsView(plugins: plugins),
      ));
      expect(find.text('插件A'), findsOneWidget);
      expect(find.text('插件B'), findsOneWidget);
    });

    testWidgets('空列表显示空状态', (tester) async {
      await tester.pumpWidget(_materialApp(
        const MyPluginsView(plugins: []),
      ));
      expect(find.text('你还没有安装任何插件'), findsOneWidget);
    });

    testWidgets('按维度分组显示', (tester) async {
      final plugins = [
        _testPlugin(id: '1', name: 'Agent插件', installed: true, dims: [AbilityDim.agent]),
        _testPlugin(id: '2', name: 'UI插件', installed: true, dims: [AbilityDim.ui]),
      ];
      await tester.pumpWidget(_materialApp(
        MyPluginsView(plugins: plugins),
      ));
      // 分组标题
      expect(find.textContaining('智能体'), findsWidgets);
      expect(find.textContaining('界面'), findsWidgets);
    });

    testWidgets('排序按钮存在', (tester) async {
      await tester.pumpWidget(_materialApp(
        MyPluginsView(plugins: [_testPlugin(installed: true)]),
      ));
      // 排序图标按钮存在
      expect(find.byIcon(Icons.sort), findsOneWidget);
    });

    testWidgets('检查更新按钮', (tester) async {
      var updated = false;
      await tester.pumpWidget(_materialApp(
        MyPluginsView(
          plugins: [_testPlugin(installed: true)],
          onCheckUpdates: () => updated = true,
        ),
      ));
      await tester.tap(find.byIcon(Icons.refresh));
      expect(updated, isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 8. SettingsView 测试
  // ═══════════════════════════════════════════════════════════════

  group('SettingsView', () {
    testWidgets('渲染设置视图（ProviderScope + 端口注入）', (tester) async {
      final descriptor = ModuleDescriptor(id: 'settings', name: 'Settings');
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
          ],
          child: MaterialApp(
            home: Scaffold(body: SettingsView(descriptor: descriptor)),
          ),
        ),
      );
      // 首帧: loading; pump() 触发 addPostFrameCallback → _ready=true → 表单
      await tester.pump();
      expect(find.byType(SettingsView), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 9. PermissionManagementView 测试 (原 WorkspacePage 已随 compositions/ 移除)
  // ═══════════════════════════════════════════════════════════════

  group('PermissionManagementView', () {
    PluginPermissionSnapshot _testSnapshot() {
      return PluginPermissionSnapshot(
        pluginId: 'test-plugin',
        pluginName: '测试插件',
        permissions: [
          const PluginPermission(name: '读取文件', level: PermissionLevel.safe, granted: true),
          const PluginPermission(name: '联网访问', level: PermissionLevel.warning, granted: true),
          const PluginPermission(name: '执行系统命令', level: PermissionLevel.danger, granted: false),
        ],
      );
    }

    testWidgets('渲染权限管理页面', (tester) async {
      await tester.pumpWidget(_materialApp(
        PermissionManagementView(snapshots: [_testSnapshot()]),
      ));
      expect(find.text('测试插件'), findsOneWidget);
      expect(find.text('读取文件'), findsOneWidget);
      expect(find.text('执行系统命令'), findsOneWidget);
      // 3 个 Switch 对应 3 个权限
      expect(find.byType(Switch), findsNWidgets(3));
    });

    testWidgets('空快照显示空状态', (tester) async {
      await tester.pumpWidget(_materialApp(
        const PermissionManagementView(snapshots: []),
      ));
      expect(find.text('暂无已安装插件'), findsOneWidget);
    });

    testWidgets('高危权限显示警告条', (tester) async {
      await tester.pumpWidget(_materialApp(
        PermissionManagementView(snapshots: [_testSnapshot()]),
      ));
      expect(find.textContaining('此插件含'), findsOneWidget);
      expect(find.textContaining('高危权限'), findsOneWidget);
    });

    testWidgets('Toggle 权限触发回调', (tester) async {
      String? toggledPluginId;
      String? toggledPermName;
      bool? toggledGranted;

      await tester.pumpWidget(_materialApp(
        PermissionManagementView(
          snapshots: [_testSnapshot()],
          onToggle: (pluginId, name, granted) {
            toggledPluginId = pluginId;
            toggledPermName = name;
            toggledGranted = granted;
          },
        ),
      ));

      // Toggle 高危权限（当前 granted=false → 变成 true）
      final switches = find.byType(Switch);
      await tester.tap(switches.last); // 最后一个 = 执行系统命令
      await tester.pump();

      expect(toggledPluginId, 'test-plugin');
      expect(toggledPermName, '执行系统命令');
      expect(toggledGranted, isTrue);
    });

    testWidgets('多插件渲染', (tester) async {
      await tester.pumpWidget(_materialApp(
        PermissionManagementView(snapshots: [
          _testSnapshot(),
          PluginPermissionSnapshot(
            pluginId: 'plugin-2',
            pluginName: '插件二',
            permissions: const [
              PluginPermission(name: '访问剪贴板', level: PermissionLevel.safe),
            ],
          ),
        ]),
      ));
      expect(find.text('测试插件'), findsOneWidget);
      expect(find.text('插件二'), findsOneWidget);
      // 3 + 1 = 4 switches
      expect(find.byType(Switch), findsNWidgets(4));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 11. 综合场景测试
  // ═══════════════════════════════════════════════════════════════

  group('综合场景', () {
    testWidgets('从市场→详情→安装流程', (tester) async {
      PluginDescriptor? detailPlugin;
      PluginDescriptor? installPlugin;

      final plugins = [_testPlugin()];

      await tester.pumpWidget(_materialApp(
        MarketView(
          plugins: plugins,
          onPluginTap: (p) => detailPlugin = p,
          onInstallTap: (p) => installPlugin = p,
        ),
      ));

      // 点击第一个插件卡片
      await tester.tap(find.text('AI 代码助手').first);
      expect(detailPlugin, isNotNull);
      expect(detailPlugin!.name, 'AI 代码助手');
    });

    testWidgets('SettingsView 需要 ProviderScope', (tester) async {
      final descriptor = ModuleDescriptor(id: 'settings', name: 'Settings');
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
          ],
          child: MaterialApp(
            theme: ThemeData(brightness: Brightness.light),
            darkTheme: ThemeData(brightness: Brightness.dark),
            home: Scaffold(body: SettingsView(descriptor: descriptor)),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(SettingsView), findsOneWidget);
    });
  });

  group('Chrome slot / 工具栏分离', () {
    testWidgets('chrome 内容 slot 留在内容区，无 Card 壳', (tester) async {
      final descriptor = ModuleDescriptor(
        id: 'test-chrome',
        name: 'Test Chrome',
        pages: [
          PageDescriptor(
            id: 'main',
            label: 'Main',
            layout: LayoutDescriptor(
              type: 'grid',
              preset: const LayoutPreset(columns: 1),
              slots: {
                'content': SlotDescriptor(
                  component: ComponentDescriptor(
                    type: 'divider',
                    config: {'chrome': true},
                  ),
                ),
              },
            ),
          ),
        ],
      );
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          child: MaterialApp(home: CompositeView(descriptor: descriptor)),
        ),
      );
      expect(find.byType(CompositeView), findsOneWidget);
      expect(find.textContaining('📌'), findsNothing);
    });

    testWidgets('非 chrome slot 保留 Card 壳', (tester) async {
      final descriptor = ModuleDescriptor(
        id: 'test-card',
        name: 'Test Card',
        pages: [
          PageDescriptor(
            id: 'main',
            label: 'Main',
            layout: LayoutDescriptor(
              type: 'grid',
              preset: const LayoutPreset(columns: 1),
              slots: {
                'card': SlotDescriptor(
                  component: ComponentDescriptor(type: 'divider'),
                ),
              },
            ),
          ),
        ],
      );
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          child: MaterialApp(home: CompositeView(descriptor: descriptor)),
        ),
      );
      expect(find.byType(CompositeView), findsOneWidget);
      expect(find.textContaining('📌'), findsOneWidget);
    });

    testWidgets('align 字段 → 工具栏分离，不崩', (tester) async {
      final descriptor = ModuleDescriptor(
        id: 'test-toolbar',
        name: 'Test Toolbar',
        pages: [
          PageDescriptor(
            id: 'main',
            label: 'Main',
            layout: LayoutDescriptor(
              type: 'grid',
              preset: const LayoutPreset(columns: 1, gap: 8),
              slots: {
                'tools': SlotDescriptor(
                  component: ComponentDescriptor(
                    type: 'button',
                    config: {
                      'chrome': true,
                      'align': 'left',
                      'buttons': [
                        {'label': '返回', 'icon': '🏠', 'event': 'slot:switch_page:home', 'style': 'tonal'},
                      ],
                    },
                  ),
                ),
              },
            ),
          ),
        ],
      );
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          child: MaterialApp(home: CompositeView(descriptor: descriptor)),
        ),
      );
      expect(find.byType(CompositeView), findsOneWidget);
    });
  });
}
