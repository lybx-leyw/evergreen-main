/// 单个语义色的编辑控件——色块预览 + hex 输入 + 预设色板。
///
/// 无第三方依赖（无网络环境无法 pub add 色盘包），自研：
/// - 色块：当前颜色实时预览
/// - hex 输入：`#RRGGBB`，实时校验（非法时红色边框）
/// - 预设色板：点击即填充
library;

import 'package:flutter/material.dart';
import 'package:evergreen_base/core/theme/theme_descriptor.dart';

import 'color_picker_dialog.dart';

/// 单个语义色编辑行。
class ColorField extends StatefulWidget {
  final String semanticKey;
  final String label;
  final String value;
  final List<String> presets;
  final ValueChanged<String> onChanged;

  const ColorField({
    super.key,
    required this.semanticKey,
    required this.label,
    required this.value,
    required this.presets,
    required this.onChanged,
  });

  @override
  State<ColorField> createState() => _ColorFieldState();
}

class _ColorFieldState extends State<ColorField> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(ColorField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部值变化（预设点选/加载草稿）时同步输入框；用户输入时值已一致，不重置光标
    if (widget.value != oldWidget.value && _ctrl.text != widget.value) {
      _ctrl.text = widget.value;
      _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Color? get _parsedColor {
    final c = ThemeDescriptor.parseHex(widget.value);
    return c != null ? Color(c.value) : null;
  }

  bool get _valid => ThemeDescriptor.parseHex(widget.value) != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valid = _valid;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          // 色块预览（点击打开调色板：SV 板 + 色相条 + RGB/HSV 滑杆）
          Tooltip(
            message: '打开调色板（SV 板 + 色相条）',
            child: InkWell(
              onTap: () async {
                final picked = await showColorPickerDialog(context,
                    initialHex: widget.value);
                if (picked != null && mounted) widget.onChanged(picked);
              },
              borderRadius: BorderRadius.circular(6),
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: _parsedColor ?? Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: valid
                        ? theme.colorScheme.outlineVariant
                        : theme.colorScheme.error,
                    width: 1,
                  ),
                ),
                child: valid
                    ? null
                    : Icon(Icons.broken_image_outlined,
                        size: 14, color: theme.colorScheme.error),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 语义名（弹性宽度，窄窗口收缩不溢出）
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
                Text(widget.semanticKey,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 10)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // hex 输入（窄固定宽）
          SizedBox(
            width: 84,
            child: TextField(
              controller: _ctrl,
              onChanged: widget.onChanged,
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: valid
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.error,
              ),
              decoration: InputDecoration(
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(
                    color: valid
                        ? theme.colorScheme.outlineVariant
                        : theme.colorScheme.error,
                  ),
                ),
                errorText: valid ? null : '非法 hex',
                errorStyle: const TextStyle(fontSize: 9, height: 0.8),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 预设色板
          Expanded(
            child: Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                for (final hex in widget.presets)
                  _PresetDot(
                    hex: hex,
                    selected: widget.value.toLowerCase() == hex.toLowerCase(),
                    onTap: () => widget.onChanged(hex),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 预设色板小圆点。
class _PresetDot extends StatelessWidget {
  final String hex;
  final bool selected;
  final VoidCallback onTap;

  const _PresetDot({
    required this.hex,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = ThemeDescriptor.parseHex(hex);
    final color = c != null ? Color(c.value) : Colors.transparent;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Colors.white : Colors.black26,
            width: selected ? 2 : 1,
          ),
        ),
        child: selected
            ? const Icon(Icons.check, size: 12, color: Colors.white)
            : null,
      ),
    );
  }
}
