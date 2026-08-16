/// 主视图切换器（Phase 2 · B1，用户 UI 决策）。
///
/// 顶部视图切换：主工作区 / workflow 流程图 / trace（Phase 3 预留）。
/// 非 workflow 视图时，workflow 压缩为顶部 Tab 下方一条横向步骤条（由父级渲染）。
library scraper_view_switch;

import 'package:flutter/material.dart';

/// 主视图模式。
enum ScraperMainView {
  /// 主工作区（默认，现有 dock 布局）。
  workspace,

  /// workflow 流程图视图。
  workflow,

  /// trace 视图（Phase 3 落地，先占位）。
  trace,
}

/// 视图切换栏。
class ScraperViewSwitch extends StatelessWidget {
  final ScraperMainView current;
  final ValueChanged<ScraperMainView> onChanged;
  final bool traceEnabled; // Phase 3 后置 true

  const ScraperViewSwitch({
    super.key,
    required this.current,
    required this.onChanged,
    this.traceEnabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget item(ScraperMainView view, IconData icon, String label) {
      final active = current == view;
      return InkWell(
        onTap: () => onChanged(view),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: active
                ? scheme.primaryContainer.withValues(alpha: 0.6)
                : null,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 13,
                  color: active ? scheme.primary : scheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                  color: active ? scheme.primary : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          item(ScraperMainView.workspace, Icons.dashboard_rounded, '工作区'),
          const SizedBox(width: 4),
          item(ScraperMainView.workflow, Icons.account_tree_rounded, '工作流'),
          const SizedBox(width: 4),
          // trace：Phase 3 前置位（禁用态）
          InkWell(
            onTap: traceEnabled
                ? () => onChanged(ScraperMainView.trace)
                : null,
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: current == ScraperMainView.trace
                    ? scheme.primaryContainer.withValues(alpha: 0.6)
                    : null,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.receipt_long_rounded,
                      size: 13,
                      color: traceEnabled
                          ? scheme.onSurfaceVariant
                          : scheme.outlineVariant),
                  const SizedBox(width: 4),
                  Text(
                    '轨迹',
                    style: TextStyle(
                      fontSize: 11,
                      color: traceEnabled
                          ? scheme.onSurfaceVariant
                          : scheme.outlineVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          // 右侧：当前工作流阶段简况（紧凑）
          if (current == ScraperMainView.workflow)
            Text(
              '完整流程图模式',
              style: TextStyle(
                fontSize: 10,
                color: scheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}
