/// 模式窄轨（AI 视图 / 开发者模式）——视图图标（点击循环切换）+ 4 个系统按钮
/// + 开发者插件入口。
///
/// 设计依据：《三模式视图重构_实施计划.md》（根目录）。
///
/// - 顶部视图图标：点击**循环切换**下一个视图
///   （AI 视图 → 开发者模式 → 插件视图 → AI 视图 …），切换并持久化；
///   不再弹扇形菜单（原扇形菜单视觉不符合预期，已移除）；
/// - 4 个系统按钮：显示设置 / 插件中心 / 数据中心 → 全屏推入新页（context.push），
///   返回后 AI 会话在 provider 中后台继续；远程同步为占位（点击提示即将上线）；
/// - 「发现插件」不再单列入口，统一由「插件中心」内部按钮跳转（路由 `/discover`）；
/// - 开发者模式：4 按钮下方追加 主题创作 / 插件制作 / 数据爬取 三个入口，
///   点击切换主区（IndexedStack 保持状态）；安卓端爬取入口变占位，
///   点击提示「安卓不支持，请使用 Windows 版」；
/// - 颜色一律从 Theme.colorScheme 派生，不硬编码。
library;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:evergreen_base/core/module/module_registry.dart';
import 'package:evergreen_base/providers.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/marketplace/plugin_state_provider.dart';
import 'app_mode.dart';

/// 窄轨宽度（与旧 collapsed 侧栏一致）。
const double kModeRailWidth = 60;

/// 当前是否为安卓（可被 debugDefaultTargetPlatformOverride 覆盖，便于测试）。
bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;

// ═══════ 系统按钮 ═══════

/// 系统按钮声明——标签为产品术语（显示设置/插件中心/数据中心），
/// 与插件 manifest 名称（设置/插件市场/数据中枢）解耦。
class _SystemButton {
  const _SystemButton({
    required this.label,
    required this.icon,
    this.route,
    this.placeholder = false,
  });

  final String label;
  final IconData icon;

  /// 目标路由；null = 占位（远程同步）。
  final String? route;
  final bool placeholder;
}

const List<_SystemButton> _systemButtons = [
  _SystemButton(
      label: '显示设置',
      icon: Icons.display_settings_outlined,
      route: '/settings'),
  _SystemButton(
      label: '插件中心',
      icon: Icons.storefront_outlined,
      route: '/marketplace'),
  _SystemButton(
      label: '数据中心',
      icon: Icons.storage_outlined,
      route: '/data-dashboard'),
  _SystemButton(
      label: '远程同步', icon: Icons.sync, placeholder: true),
];

/// 开发者五插件入口（顺序与 [kDevPluginIds] 对齐）。
const List<String> _devPluginNames = ['主题创作', '插件制作', '数据爬取', 'DSH', 'Skill 创作'];
const List<IconData> _devPluginIcons = [
  Icons.palette_outlined,
  Icons.code,
  Icons.public,
  Icons.hub_outlined,
  Icons.auto_fix_high_outlined,
];

// ═══════ ModeRail ═══════

/// 模式窄轨：视图图标 + 系统按钮 +（开发者模式）三插件入口。
class ModeRail extends ConsumerWidget {
  final AppMode mode;
  const ModeRail({super.key, required this.mode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registry = ref.watch(moduleRegistryProvider);
    final location = GoRouterState.of(context).uri.path;
    final devIndex = ref.watch(devHubIndexProvider);

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: ModeSwitchButton(mode: mode),
            ),
            const Divider(),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  for (final b in _systemButtons)
                    _buildSystemButton(context, b, location),
                ],
              ),
            ),
            if (mode == AppMode.developer) ...[
              const Divider(),
              for (int i = 0; i < kDevPluginIds.length; i++)
                _buildDevPluginButton(context, ref, registry, i, location,
                    devIndex),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSystemButton(
      BuildContext context, _SystemButton b, String location) {
    final dimmed = b.placeholder;
    return _RailButton(
      label: b.label,
      icon: b.icon,
      dimmed: dimmed,
      onTap: () => _openSystem(context, b, location),
    );
  }

  void _openSystem(BuildContext context, _SystemButton b, String location) {
    if (b.placeholder || b.route == null) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('远程同步'),
          content: const Text('远程同步即将上线，敬请期待。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return;
    }
    if (location == b.route) return; // 已在目标页
    context.push(b.route!);
  }

  Widget _buildDevPluginButton(
    BuildContext context,
    WidgetRef ref,
    ModuleRegistry registry,
    int index,
    String location,
    int devIndex,
  ) {
    final id = kDevPluginIds[index];
    // 插件未安装 → 隐藏入口（主区占位页兜底）。
    if (registry.findById(id) == null) {
      return const SizedBox.shrink();
    }
    // 仅 Windows 插件（scraper / dsh / skill-creator 依赖 WebView2 或桌面能力）在安卓端弱化 + 拦截。
    final isWindowsOnlyAndroid = kWindowsOnlyPluginIds.contains(id) && _isAndroid;
    final active = location == '/dev-hub' && devIndex == index;
    return _RailButton(
      label: _devPluginNames[index],
      icon: _devPluginIcons[index],
      active: active,
      dimmed: isWindowsOnlyAndroid,
      onTap: () =>
          _openDevPlugin(context, ref, id, index, isWindowsOnlyAndroid),
    );
  }

  void _openDevPlugin(BuildContext context, WidgetRef ref, String id,
      int index, bool isWindowsOnlyAndroid) {
    if (isWindowsOnlyAndroid) {
      final label = _devPluginNames[index];
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('$label仅支持 Windows 版'),
          content: const Text('安卓版暂未提供此功能，请使用 Windows 版 Evergreen。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return;
    }
    ref.read(devHubIndexProvider.notifier).state = index;
    context.go('/dev-hub');
  }
}

// ═══════ _RailButton ═══════

/// 窄轨图标按钮（Tooltip + 可选高亮/弱化）。
class _RailButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool active;
  final bool dimmed;

  const _RailButton({
    required this.label,
    required this.icon,
    this.onTap,
    this.active = false,
    this.dimmed = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = active
        ? scheme.onPrimaryContainer
        : (dimmed
            ? scheme.onSurfaceVariant.withValues(alpha: 0.45)
            : scheme.onSurfaceVariant);
    return Tooltip(
      message: label,
      waitDuration: const Duration(milliseconds: 300),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Material(
          color: active ? scheme.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            hoverColor: scheme.primary.withValues(alpha: 0.08),
            splashColor: scheme.primary.withValues(alpha: 0.12),
            highlightColor: scheme.primary.withValues(alpha: 0.04),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Icon(icon, size: 20, color: color),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════ 扇形模式切换菜单 ═══════

/// 顶部视图图标按钮——点击循环切到下一个视图模式。
///
/// 公开供壳层（app_shell）复用：插件视图的侧栏/抽屉顶部也放一个，
/// 否则进入插件视图后无法切回 AI 视图 / 开发者模式（单向门）。
class ModeSwitchButton extends ConsumerStatefulWidget {
  final AppMode mode;
  const ModeSwitchButton({super.key, required this.mode});

  @override
  ConsumerState<ModeSwitchButton> createState() => _ModeSwitchButtonState();
}

class _ModeSwitchButtonState extends ConsumerState<ModeSwitchButton> {
  /// 点击循环切到下一个视图模式（ai → developer → plugins → ai …），
  /// 不再弹扇形菜单。切后导航到该模式默认视图，避免壳层变了主内容仍停在旧路由。
  Future<void> _cycle() async {
    final modes = AppMode.values;
    final next = modes[(widget.mode.index + 1) % modes.length];
    await setAppMode(ref, next);
    final registry = ref.read(moduleRegistryProvider);
    final target = defaultRouteForMode(
      mode: next,
      registry: registry,
      pluginStates: ref.read(pluginStateProvider).records,
    );
    if (target != null && mounted) context.go(target);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final next = AppMode.values[(widget.mode.index + 1) % AppMode.values.length];
    return Tooltip(
      message: '当前：${appModeLabel(widget.mode)}　点击切到：${appModeLabel(next)}',
      waitDuration: const Duration(milliseconds: 300),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _cycle,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            shape: BoxShape.circle,
            border: Border.all(color: scheme.outlineVariant, width: 1.2),
          ),
          child: Icon(Icons.view_quilt_outlined,
              size: 20, color: scheme.primary),
        ),
      ),
    );
  }
}

/// （扇形菜单已移除：模式切换改为点击循环切换，见 [ModeSwitchButton]。）
