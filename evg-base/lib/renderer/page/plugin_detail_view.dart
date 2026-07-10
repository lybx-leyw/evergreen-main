/// 插件详情页——描述/版本/截图轮播/权限分级/维度清单/安装按钮。
///
/// 对应 R-S2-2。遵循描述符驱动 + 数据注入模式。
import 'package:flutter/material.dart';
import '../components/shared/widgets/models.dart';
import '../components/shared/widgets/ability_tag.dart';
import '../components/shared/widgets/install_progress.dart';
import '../components/shared/widgets/permission_dialog.dart';

/// 插件详情页。
class PluginDetailView extends StatefulWidget {
  final PluginDescriptor plugin;
  final InstallProgress? installProgress;
  final VoidCallback? onInstall;
  final VoidCallback? onBack;

  const PluginDetailView({
    super.key,
    required this.plugin,
    this.installProgress,
    this.onInstall,
    this.onBack,
  });

  @override
  State<PluginDetailView> createState() => _PluginDetailViewState();
}

class _PluginDetailViewState extends State<PluginDetailView> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final p = widget.plugin;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 返回按钮
          if (widget.onBack != null)
            TextButton.icon(
              onPressed: widget.onBack,
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('返回市场'),
            ),
          const SizedBox(height: 8),
          // 内容区：左右分栏
          LayoutBuilder(
            builder: (ctx, constraints) {
              final isWide = constraints.maxWidth > 700;
              return isWide ? _buildWideLayout(p, theme, scheme) : _buildNarrowLayout(p, theme, scheme);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildWideLayout(PluginDescriptor p, ThemeData theme, ColorScheme scheme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 主内容区
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHero(p, scheme),
              const SizedBox(height: 16),
              _buildDescription(p, theme, scheme),
              const SizedBox(height: 16),
              _buildScreenshots(p, theme, scheme),
            ],
          ),
        ),
        const SizedBox(width: 24),
        // 侧边栏
        SizedBox(
          width: 280,
          child: _buildSidebar(p, theme, scheme),
        ),
      ],
    );
  }

  Widget _buildNarrowLayout(PluginDescriptor p, ThemeData theme, ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSidebar(p, theme, scheme),
        const SizedBox(height: 16),
        _buildHero(p, scheme),
        const SizedBox(height: 16),
        _buildDescription(p, theme, scheme),
        const SizedBox(height: 16),
        _buildScreenshots(p, theme, scheme),
      ],
    );
  }

  Widget _buildHero(PluginDescriptor p, ColorScheme scheme) {
    return Container(
      height: 180,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          colors: [scheme.primary, Color.lerp(scheme.primary, scheme.tertiary, 0.6)!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Text(
          p.name[0].toUpperCase(),
          style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w300, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildDescription(PluginDescriptor p, ThemeData theme, ColorScheme scheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('📝 描述', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              p.longDescription.isNotEmpty ? p.longDescription : p.description,
              style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.7), height: 1.5),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 24,
              runSpacing: 4,
              children: [
                _metaItem(Icons.person, p.author, scheme),
                _metaItem(Icons.inventory, 'v${p.version}', scheme),
                _metaItem(Icons.download, '${p.installCount} 安装', scheme),
                _metaItem(Icons.star, '${p.rating}', scheme),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metaItem(IconData icon, String text, ColorScheme scheme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: scheme.onSurface.withValues(alpha: 0.5)),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 13, color: scheme.onSurface.withValues(alpha: 0.6))),
      ],
    );
  }

  Widget _buildScreenshots(PluginDescriptor p, ThemeData theme, ColorScheme scheme) {
    if (p.screenshotCount == 0) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('🖼 截图', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SizedBox(
              height: 120,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: p.screenshotCount,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (ctx, i) => Container(
                  width: 180,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: scheme.outline.withValues(alpha: 0.2)),
                  ),
                  child: Center(
                    child: Text(
                      '截图 ${i + 1}',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurface.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar(PluginDescriptor p, ThemeData theme, ColorScheme scheme) {
    return Column(
      children: [
        // 安装卡片
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(p.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                AbilityTagRow(dims: p.dimensions),
                const SizedBox(height: 6),
                Text(
                  'v${p.version} · ${p.author}',
                  style: TextStyle(fontSize: 13, color: scheme.onSurface.withValues(alpha: 0.5)),
                ),
                const SizedBox(height: 12),
                // 安装进度或按钮
                if (widget.installProgress != null &&
                    widget.installProgress!.status != InstallStatus.completed)
                  InstallProgressWidget(
                    progress: widget.installProgress!,
                    onRetry: widget.onInstall,
                    onCancel: () {},
                  )
                else if (p.installed && !p.hasUpdate)
                  FilledButton.tonal(
                    onPressed: null,
                    child: const Text('✅ 已安装'),
                  )
                else
                  FilledButton.icon(
                    onPressed: () => _handleInstall(context, p),
                    icon: Icon(p.hasUpdate ? Icons.update : Icons.download),
                    label: Text(p.hasUpdate ? '更新' : '安装'),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // 权限卡片
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('🔐 权限', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                ...p.permissions.map((perm) => _PermRow(permission: perm, scheme: scheme)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // 能力维度卡片
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('📐 能力维度', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                ...p.dimensions.map((d) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      AbilityTag(dim: d),
                      const SizedBox(width: 8),
                      Text(
                        _dimDesc(d),
                        style: TextStyle(fontSize: 13, color: scheme.onSurface.withValues(alpha: 0.6)),
                      ),
                    ],
                  ),
                )),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _handleInstall(BuildContext context, PluginDescriptor p) async {
    if (p.permissions.any((perm) => perm.level == PermissionLevel.danger)) {
      final ok = await showPermissionDialog(
        context,
        pluginName: p.name,
        permissions: p.permissions,
      );
      if (ok == true) {
        widget.onInstall?.call();
      }
    } else {
      widget.onInstall?.call();
    }
  }

  String _dimDesc(AbilityDim d) {
    switch (d) {
      case AbilityDim.agent: return '智能体能力';
      case AbilityDim.ui: return '界面渲染';
      case AbilityDim.data: return '数据处理';
      case AbilityDim.theme: return '主题定制';
      case AbilityDim.settings: return '配置管理';
      case AbilityDim.skill: return '技能扩展';
    }
  }
}

class _PermRow extends StatelessWidget {
  final PluginPermission permission;
  final ColorScheme scheme;

  const _PermRow({required this.permission, required this.scheme});

  @override
  Widget build(BuildContext context) {
    Color dotColor;
    IconData icon;
    switch (permission.level) {
      case PermissionLevel.danger:
        dotColor = scheme.error;
        icon = Icons.warning_amber_rounded;
      case PermissionLevel.warning:
        dotColor = const Color(0xFFFA8C16);
        icon = Icons.info_outline;
      case PermissionLevel.safe:
        dotColor = const Color(0xFF2DA44E);
        icon = Icons.check_circle_outline;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 14, color: dotColor),
          const SizedBox(width: 6),
          Text(permission.name, style: const TextStyle(fontSize: 13)),
          const Spacer(),
          Text(
            permission.levelLabel,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: dotColor),
          ),
        ],
      ),
    );
  }
}
