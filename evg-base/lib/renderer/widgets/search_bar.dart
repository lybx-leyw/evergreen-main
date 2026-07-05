/// 搜索栏——根据 [SearchDescriptor] 渲染可配置搜索输入框。
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';

/// 搜索栏组件。
///
/// 读取 [SearchDescriptor] 配置（enabled / placeholder）。
/// 可独立使用，也可嵌入 AppBar bottom。
class EvergreenSearchBar extends StatefulWidget {
  final SearchDescriptor? searchConfig;
  final ValueChanged<String>? onSearch;
  final VoidCallback? onClear;
  final bool autoFocus;

  const EvergreenSearchBar({
    super.key,
    this.searchConfig,
    this.onSearch,
    this.onClear,
    this.autoFocus = false,
  });

  @override
  State<EvergreenSearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<EvergreenSearchBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  bool get _enabled => widget.searchConfig?.enabled ?? false;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_enabled) return const SizedBox.shrink();

    final placeholder =
        widget.searchConfig?.placeholder ?? '搜索...';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        autofocus: widget.autoFocus,
        onChanged: widget.onSearch,
        decoration: InputDecoration(
          hintText: placeholder,
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _controller.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    _controller.clear();
                    widget.onClear?.call();
                  },
                )
              : null,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }
}
