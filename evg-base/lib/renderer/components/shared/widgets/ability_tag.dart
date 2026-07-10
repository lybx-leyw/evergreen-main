/// 六色能力标签——用于市场卡片、详情页等场景。
///
/// 对应 [AbilityDim] 枚举的六种维度，使用 [color_palette.md] 定义的色值。
import 'package:flutter/material.dart';
import 'models.dart';

/// 单个能力维度标签。
///
/// 示例：
/// ```dart
/// AbilityTag(dim: AbilityDim.agent)
/// ```
class AbilityTag extends StatelessWidget {
  final AbilityDim dim;
  final bool compact; // 紧凑模式：仅显示图标

  const AbilityTag({super.key, required this.dim, this.compact = false});

  static const _tagColors = <AbilityDim, _TagColor>{
    AbilityDim.agent: _TagColor(
      bg: Color(0xFFE6F4FF),
      text: Color(0xFF1677FF),
      darkBg: Color(0xFF111D2C),
      darkText: Color(0xFF4096FF),
    ),
    AbilityDim.ui: _TagColor(
      bg: Color(0xFFF6FFED),
      text: Color(0xFF52C41A),
      darkBg: Color(0xFF1C2B11),
      darkText: Color(0xFF73D13D),
    ),
    AbilityDim.data: _TagColor(
      bg: Color(0xFFFFF7E6),
      text: Color(0xFFFA8C16),
      darkBg: Color(0xFF2B1D11),
      darkText: Color(0xFFD29922),
    ),
    AbilityDim.theme: _TagColor(
      bg: Color(0xFFF9F0FF),
      text: Color(0xFF722ED1),
      darkBg: Color(0xFF1A1135),
      darkText: Color(0xFFB37FEB),
    ),
    AbilityDim.settings: _TagColor(
      bg: Color(0xFFFAFAFA),
      text: Color(0xFF8C8C8C),
      darkBg: Color(0xFF1F1F1F),
      darkText: Color(0xFF8B949E),
    ),
    AbilityDim.skill: _TagColor(
      bg: Color(0xFFE6FFFB),
      text: Color(0xFF13C2C2),
      darkBg: Color(0xFF112A2A),
      darkText: Color(0xFF13C2C2),
    ),
  };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = _tagColors[dim]!;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 4 : 8,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: isDark ? colors.darkBg : colors.bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        compact ? dim.label : dim.displayName,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: isDark ? colors.darkText : colors.text,
        ),
      ),
    );
  }
}

/// 能力标签行——水平排列多个标签。
class AbilityTagRow extends StatelessWidget {
  final List<AbilityDim> dims;
  final bool compact;

  const AbilityTagRow({super.key, required this.dims, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 2,
      children: dims.map((d) => AbilityTag(dim: d, compact: compact)).toList(),
    );
  }
}

class _TagColor {
  final Color bg;
  final Color text;
  final Color darkBg;
  final Color darkText;
  const _TagColor({
    required this.bg,
    required this.text,
    required this.darkBg,
    required this.darkText,
  });
}
