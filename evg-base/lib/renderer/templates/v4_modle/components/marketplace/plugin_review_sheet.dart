/// 用户评价面板（M5-8）。
///
/// 远程市场插件安装后，用户可在此打分（1–5 星）+ 写文字评价，
/// 提交后回传 [PluginReview] 给上层做聚合与持久化。
library;

import 'package:evergreen_base/core/module/plugin_review.dart';
import 'package:evergreen_base/renderer/components/shared/widgets/models.dart';
import 'package:flutter/material.dart';

/// 弹出评价面板，返回 [PluginReview]（取消返回 null）。
Future<PluginReview?> showPluginReviewSheet({
  required BuildContext context,
  required PluginDescriptor plugin,
}) {
  return showModalBottomSheet<PluginReview>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _PluginReviewSheetContent(plugin: plugin),
  );
}

class _PluginReviewSheetContent extends StatefulWidget {
  final PluginDescriptor plugin;

  const _PluginReviewSheetContent({required this.plugin});

  @override
  State<_PluginReviewSheetContent> createState() =>
      _PluginReviewSheetContentState();
}

class _PluginReviewSheetContentState extends State<_PluginReviewSheetContent> {
  int _stars = 0;
  final _commentCtrl = TextEditingController();

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '评价「${widget.plugin.name}」',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 星级选择
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final n = i + 1;
              return IconButton(
                icon: Icon(
                  n <= _stars ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: 36,
                  color: n <= _stars ? Colors.amber : scheme.onSurface.withValues(alpha: 0.4),
                ),
                onPressed: () => setState(() => _stars = n),
              );
            }),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _commentCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: '说说你的使用体验（可选）',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _stars == 0
                  ? null
                  : () => Navigator.of(context).pop(
                        PluginReview(
                          author: 'local-user',
                          stars: _stars,
                          comment: _commentCtrl.text.trim().isEmpty
                              ? null
                              : _commentCtrl.text.trim(),
                          source: 'user',
                        ),
                      ),
              child: const Text('提交评价'),
            ),
          ),
        ],
      ),
    );
  }
}
