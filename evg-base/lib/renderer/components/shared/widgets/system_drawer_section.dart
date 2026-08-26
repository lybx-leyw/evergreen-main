/// 系统功能抽屉分区 —— 原 AI 视图窄轨（ModeRail）里的「系统按钮 + 模式切换」
/// 收进 AI 助手左侧抽屉后的复用组件。
///
/// 背景：AI 视图下壳层最左窄轨（ModeRail）整体隐藏（见 app_shell._RailShell），
/// 原来那排入口（模式切换 / 显示设置 / 插件中心 / 数据中心 / 远程同步）全部移入
/// AI 助手左侧「会话历史」抽屉内的本「系统」分区，保证入口可达、视觉更收敛。
///
/// 说明：开发者模式入口不在本分区——开发者模式（AppMode.developer）仍保留窄轨
/// （ModeRail 未隐藏），开发者入口逻辑照旧由窄轨承载，不重复收进 AI 助手抽屉。
///
/// 跳转语义与 mode_rail.dart 的 `_openSystem` 完全一致：
/// - 模式切换 → [ModeSwitchButton]（循环切视图，同窄轨顶部圆钮）；
/// - 系统按钮 → `context.push(route)`（远程同步为占位弹窗）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:evergreen_base/renderer/app/app_mode.dart';
import 'package:evergreen_base/renderer/app/mode_rail.dart';

/// 系统按钮声明（与 mode_rail 的 `_systemButtons` 对齐，避免漂移）。
class _SysButton {
  const _SysButton(this.label, this.icon,
      {this.route, this.placeholder = false});
  final String label;
  final IconData icon;
  final String? route;
  final bool placeholder;
}

const List<_SysButton> _systemButtons = [
  _SysButton('显示设置', Icons.display_settings_outlined, route: '/settings'),
  _SysButton('插件中心', Icons.storefront_outlined, route: '/marketplace'),
  _SysButton('数据中心', Icons.storage_outlined, route: '/data-dashboard'),
  _SysButton('远程同步', Icons.sync, placeholder: true),
];

/// 系统功能抽屉分区（模式切换 + 系统按钮）。
///
/// 供 AI 助手左侧抽屉复用；不依赖任何父 Widget 状态，
/// 仅通过 Riverpod + GoRouter 完成导航。
class SystemDrawerSection extends ConsumerWidget {
  const SystemDrawerSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final location = GoRouterState.of(context).uri.path;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Row(
            children: [
              Icon(Icons.settings_outlined,
                  size: 16, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                '系统',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              ModeSwitchButton(mode: ref.watch(appModeProvider)),
            ],
          ),
        ),
        for (final b in _systemButtons) _buildSystemTile(context, b, location),
      ],
    );
  }

  Widget _buildSystemTile(BuildContext context, _SysButton b, String location) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Icon(b.icon, size: 20),
      title: Text(b.label, style: const TextStyle(fontSize: 13)),
      onTap: () {
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
        if (location == b.route) return;
        context.push(b.route!);
      },
    );
  }
}
