/// 创作中心布局模式切换器（T2，仿 scraper_view_switch 范式）。
///
/// 宽屏下在工具栏下方提供一行模式切换：三栏 IDE / 双栏编辑+预览 / 全宽预览。
/// - ide      = 数据 | 编辑 | 预览（默认，数据面板 + 编辑器 + 预览对照）
/// - split    = 编辑 | 预览（收起数据栏，专注编码与渲染对照）
/// - preview  = 仅预览全宽（审阅渲染效果，配合 AI 评判 view_html_result）
library;

import 'package:flutter/material.dart';

/// 宽屏布局模式。
enum HtmlLayoutMode {
  /// 三栏 IDE（数据 | 编辑 | 预览）。
  ide,

  /// 双栏（编辑 | 预览），数据栏隐藏。
  split,

  /// 仅预览全宽。
  preview,
}

/// 布局模式切换栏（原子组件：纯展示 + 回调，不含业务逻辑）。
class HtmlViewSwitch extends StatelessWidget {
  final HtmlLayoutMode current;
  final ValueChanged<HtmlLayoutMode> onChanged;

  const HtmlViewSwitch({
    super.key,
    required this.current,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget item(
      HtmlLayoutMode mode,
      IconData icon,
      String label,
      String tooltip,
    ) {
      final active = current == mode;
      return Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: () => onChanged(mode),
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
                Icon(
                  icon,
                  size: 13,
                  color: active ? scheme.primary : scheme.onSurfaceVariant,
                ),
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
          item(
            HtmlLayoutMode.ide,
            Icons.view_column_rounded,
            '三栏',
            '数据 | 编辑 | 预览',
          ),
          const SizedBox(width: 4),
          item(
            HtmlLayoutMode.split,
            Icons.vertical_split_rounded,
            '双栏',
            '编辑 | 预览（收起数据栏）',
          ),
          const SizedBox(width: 4),
          item(
            HtmlLayoutMode.preview,
            Icons.visibility_rounded,
            '预览',
            '仅预览全宽（审阅渲染效果）',
          ),
          const Spacer(),
          // 右侧：当前布局简况（紧凑，仿 scraper 右侧阶段简况）
          Text(switch (current) {
            HtmlLayoutMode.ide => '三栏 IDE',
            HtmlLayoutMode.split => '双栏对照',
            HtmlLayoutMode.preview => '全宽预览',
          }, style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
