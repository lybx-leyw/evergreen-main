/// 安装前权限确认弹窗（M5-3 · renderer 侧）。
///
/// 用户点击「安装」后、真正调用 [PluginInstaller.install] 之前弹出。
/// 展示该插件由核心层 [CapabilityDimension] 推导的能力维度及其风险定级，
/// fail-closed：默认拒绝（点遮罩 / 取消 / ESC 都不安装），只有点「确认安装」才放行。
library;

import 'package:evergreen_base/core/module/capability.dart';
import 'package:evergreen_base/core/module/capability_bridge.dart';
import 'package:evergreen_base/renderer/components/shared/widgets/ability_capability_bridge.dart';
import 'package:evergreen_base/renderer/components/shared/widgets/models.dart';
import 'package:flutter/material.dart';

/// 权限确认弹窗。
///
/// [pluginName] 插件名；[dims] 核心层能力维度（来自磁盘 discoverCapabilities
/// 或 manifest 推导，不含 skill 这类无核心维度的项）。
/// [onConfirm] 用户点「确认安装」时调用；[onCancel] 取消时调用。
Future<bool> showPermissionConfirmDialog({
  required BuildContext context,
  required String pluginName,
  required List<CapabilityDimension> dims,
  required VoidCallback onConfirm,
  VoidCallback? onCancel,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false, // fail-closed：点遮罩不安装
    builder: (ctx) => PermissionConfirmDialog(
      pluginName: pluginName,
      dims: dims,
      onConfirm: () => Navigator.of(ctx).pop(true),
      onCancel: () => Navigator.of(ctx).pop(false),
    ),
  );
  if (confirmed == true) {
    onConfirm();
    return true;
  }
  onCancel?.call();
  return false;
}

/// 权限确认弹窗 Widget（可单测构造，不依赖 showDialog）。
class PermissionConfirmDialog extends StatelessWidget {
  final String pluginName;
  final List<CapabilityDimension> dims;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const PermissionConfirmDialog({
    super.key,
    required this.pluginName,
    required this.dims,
    required this.onConfirm,
    required this.onCancel,
  });

  RiskLevel get _maxRisk => maxRisk(dims);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final topRisk = _maxRisk;
    final topColor = _riskColor(topRisk, scheme);

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.shield_outlined, color: topColor, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text('安装前确认',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('即将安装「$pluginName」',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            // 顶部总览：最高风险等级
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: topColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: topColor.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Icon(_riskIcon(topRisk), size: 16, color: topColor),
                  const SizedBox(width: 6),
                  Text(
                    '风险等级：${_riskLabel(topRisk)}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: topColor, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text('该插件将获得以下能力：',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurface.withValues(alpha: 0.7))),
            const SizedBox(height: 8),
            // 能力维度清单
            ...dims.map((d) => _CapabilityRow(dim: d)),
            const SizedBox(height: 12),
            Text(
              '安装即代表你信任该插件按上述能力运行。'
              '内置能力默认最小授权（deny-all），插件无法越权访问未列出的维度。',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurface.withValues(alpha: 0.5)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: onCancel,
          child: const Text('取消'),
        ),
        FilledButton(
          // fail-closed：即使是安全插件，也需用户主动确认
          onPressed: onConfirm,
          style: FilledButton.styleFrom(
            backgroundColor: topColor,
            foregroundColor:
                topRisk == RiskLevel.safe ? scheme.onPrimary : Colors.white,
          ),
          child: const Text('确认安装'),
        ),
      ],
    );
  }

  Color _riskColor(RiskLevel risk, ColorScheme scheme) {
    switch (risk) {
      case RiskLevel.safe:
        return scheme.primary;
      case RiskLevel.warning:
        return const Color(0xFFFA8C16);
      case RiskLevel.danger:
        return scheme.error;
    }
  }

  IconData _riskIcon(RiskLevel risk) {
    switch (risk) {
      case RiskLevel.safe:
        return Icons.check_circle_outline;
      case RiskLevel.warning:
        return Icons.warning_amber_outlined;
      case RiskLevel.danger:
        return Icons.dangerous_outlined;
    }
  }

  String _riskLabel(RiskLevel risk) {
    switch (risk) {
      case RiskLevel.safe:
        return '安全';
      case RiskLevel.warning:
        return '中危';
      case RiskLevel.danger:
        return '高危';
    }
  }
}

/// 单个能力维度行：维度名 + 风险标签。
class _CapabilityRow extends StatelessWidget {
  final CapabilityDimension dim;

  const _CapabilityRow({required this.dim});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final risk = riskOf(dim);
    final riskColor = switch (risk) {
      RiskLevel.safe => scheme.primary,
      RiskLevel.warning => const Color(0xFFFA8C16),
      RiskLevel.danger => scheme.error,
    };
    // process 维度无 UI 色标，用文字说明
    final abilityDim = toAbilityDim(dim);
    final label = abilityDim?.displayName ?? _processLabel(dim);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(Icons.circle, size: 6, color: riskColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: riskColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              switch (risk) {
                RiskLevel.safe => '安全',
                RiskLevel.warning => '中危',
                RiskLevel.danger => '高危',
              },
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: riskColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _processLabel(CapabilityDimension dim) {
    if (dim == CapabilityDimension.process) return '后端进程';
    return dim.name;
  }
}
