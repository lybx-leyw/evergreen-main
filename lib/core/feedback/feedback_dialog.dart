import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../log.dart';
import 'feedback_writer.dart';
import 'screenshot.dart';

/// 反馈标签。
enum FeedbackTag {
  bug('🐛 Bug'),
  suggestion('💡 建议'),
  ux('😤 体验');

  const FeedbackTag(this.label);
  final String label;
}

/// 反馈输入弹窗——嵌入在 FeedbackFab overlay 中，不依赖 Navigator。
class FeedbackDialog extends StatefulWidget {
  final VoidCallback onClose;

  const FeedbackDialog({super.key, required this.onClose});

  @override
  State<FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<FeedbackDialog> {
  final _controller = TextEditingController();
  FeedbackTag _tag = FeedbackTag.bug;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _currentRoute {
    try {
      return GoRouter.of(context).state.uri.path;
    } catch (_) {
      return '/';
    }
  }

  Future<void> _submit() async {
    final description = _controller.text.trim();
    if (description.isEmpty) return;

    final route = _currentRoute;
    setState(() => _saving = true);

    // ① t0 — 同源时钟
    final t0 = DateTime.now().microsecondsSinceEpoch;

    // ② 先写日志 + Markdown（创建 session 子目录）
    Log().info('FEEDBACK: button_pressed',
        data: {'ts': t0, 'route': route, 'tag': _tag.label});
    final writer = FeedbackWriter();
    final sessionDir = await writer.write(
      timestampUs: t0,
      route: route,
      tag: _tag.label,
      description: description,
    );

    // ③ 关闭弹窗，等一帧让 UI 渲染消失
    widget.onClose();
    await Future.delayed(const Duration(milliseconds: 200));

    // ④ 截取 APP 界面（弹窗已消失，截的是 bug 现场）
    await captureScreenshot(sessionDir: sessionDir);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('反馈：$_currentRoute'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标签选择
          Wrap(
            spacing: 8,
            children: FeedbackTag.values.map((tag) {
              final selected = _tag == tag;
              return ChoiceChip(
                label: Text(tag.label),
                selected: selected,
                onSelected: (_) => setState(() => _tag = tag),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          // 描述输入 — 支持键盘 + 手写（iPadOS Scribble / Windows Ink / Android 触控笔）
          TextField(
            controller: _controller,
            maxLines: 5,
            scribbleEnabled: true,
            decoration: const InputDecoration(
              hintText: '描述你遇到的问题（也支持手写输入）...',
              border: OutlineInputBorder(),
            ),
            autofocus: true,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : widget.onClose,
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('提交'),
        ),
      ],
    );
  }
}
