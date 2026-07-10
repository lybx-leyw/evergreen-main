/// 记事本槽位——从 [ComponentDescriptor.config] 读取 content/placeholder 渲染。
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';

/// 记事本——`notepad` 组件。
class NotepadSlot extends StatelessWidget {
  final ComponentDescriptor config;

  const NotepadSlot({super.key, required this.config});

  @override
  Widget build(BuildContext context) {
    final cfg = config.config;
    final content = cfg['content'] as String? ?? '';
    final placeholder = cfg['placeholder'] as String? ?? '输入内容…';
    final title = cfg['title'] as String? ?? '记事本';
    final readOnly = cfg['readOnly'] as bool? ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: TextField(
              controller: TextEditingController(text: content),
              readOnly: readOnly,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              decoration: InputDecoration(
                hintText: placeholder,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
