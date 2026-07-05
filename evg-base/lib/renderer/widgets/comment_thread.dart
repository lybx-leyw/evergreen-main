/// 批注线程——文档内联批注面板。
///
/// 公开类：[CommentThread]
import 'package:flutter/material.dart';
import 'empty_state.dart';

/// 文档批注面板。
///
/// 显示在文档编辑区右侧，列出所有批注。
class CommentThread extends StatelessWidget {
  const CommentThread({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              '批注',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          const Divider(height: 1),
          const Expanded(
            child: EmptyState(
              icon: Icons.comment_outlined,
              title: '暂无批注',
              subtitle: '选中文本后可添加批注',
            ),
          ),
        ],
      ),
    );
  }
}
