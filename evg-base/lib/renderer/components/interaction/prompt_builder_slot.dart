/// 提示词构建器槽位——从 [ComponentDescriptor.config] 读取 template/variables 渲染。
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';

/// 提示词构建器——`prompt-builder` 组件。
class PromptBuilderSlot extends StatelessWidget {
  final ComponentDescriptor config;

  const PromptBuilderSlot({super.key, required this.config});

  @override
  Widget build(BuildContext context) {
    final cfg = config.config;
    final template = (cfg['template'] as String?) ?? '';
    final variables = (cfg['variables'] as Map<dynamic, dynamic>?) ?? {};
    final theme = Theme.of(context);

    // 用变量值替换模板中的 {{key}}
    var rendered = template;
    final controllers = <String, TextEditingController>{};
    for (final entry in variables.entries) {
      final key = entry.key.toString();
      final value = entry.value?.toString() ?? '';
      controllers[key] = TextEditingController(text: value);
      rendered = rendered.replaceAll('{{$key}}', value);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('模板',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
                template.isEmpty ? '（未配置 template）' : template),
          ),
          const SizedBox(height: 16),
          if (variables.isNotEmpty) ...[
            Text('变量',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            for (final key in variables.keys)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(
                  controller: controllers[key],
                  decoration: InputDecoration(
                    labelText: key.toString(),
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) {},
                ),
              ),
          ],
          const SizedBox(height: 16),
          Text('生成预览',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(
                  color: theme.colorScheme.outline.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
                rendered.isEmpty ? '（无生成内容）' : rendered),
          ),
        ],
      ),
    );
  }
}
