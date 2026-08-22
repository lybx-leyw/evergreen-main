import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:evergreen_base/core/log.dart';
import 'package:evergreen_base/core/config/settings.dart' show getSetting;
import 'package:evergreen_base/core/feedback/feedback_writer.dart'
    show FeedbackWriter, buildFeedbackBody, buildIssueTitle;
import 'package:evergreen_base/core/feedback/github_issue_publisher.dart'
    show publishGithubIssue, IssueSuccess, IssueFailure, IssueFailureKind, kGithubFeedbackTokenKey;
import 'screenshot.dart';

/// 反馈标签。
enum FeedbackTag {
  bug('🐛 Bug'),
  suggestion('💡 建议'),
  ux('😤 体验');

  const FeedbackTag(this.label);
  final String label;
}

/// 工作流步骤状态。
enum StepState {
  idle,
  running,
  done,
  failed,
}

/// 发 Issue 工作流的单个步骤。
class _FlowStep {
  final String label;
  StepState state;
  String? detail;
  _FlowStep(this.label, [this.state = StepState.idle, this.detail]);
}

/// 反馈输入弹窗——嵌入在 FeedbackFab overlay 中，不依赖 Navigator。
class FeedbackDialog extends StatefulWidget {
  final VoidCallback onClose;
  /// 请求浮窗临时隐藏遮罩以截取 bug 现场（dialog 仍保持 mounted）。
  final void Function(bool hide)? onCaptureMode;

  const FeedbackDialog({super.key, required this.onClose, this.onCaptureMode});

  @override
  State<FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<FeedbackDialog> {
  final _controller = TextEditingController();
  FeedbackTag _tag = FeedbackTag.bug;
  // 各自独立的 loading 态，互不阻塞
  bool _savingLocal = false;
  bool _publishing = false;

  /// 工作流步骤（发 Issue 时可见）。
  List<_FlowStep> _steps = const [];

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

  Future<String> _writeLocal(int t0, String route, String description) async {
    final writer = FeedbackWriter();
    return writer.write(
      timestampUs: t0,
      route: route,
      tag: _tag.label,
      description: description,
    );
  }

  /// 保存到本地：写 Markdown + 截图（弹窗关闭后截 bug 现场）。
  Future<void> _saveLocal() async {
    final description = _controller.text.trim();
    if (description.isEmpty) return;
    if (_savingLocal || _publishing) return;

    final route = _currentRoute;
    final t0 = DateTime.now().microsecondsSinceEpoch;
    Log().info('FEEDBACK: button_pressed(local)',
        data: {'ts': t0, 'route': route, 'tag': _tag.label});

    setState(() => _savingLocal = true);
    final sessionDir = await _writeLocal(t0, route, description);
    if (!mounted) return;

    widget.onClose();
    await Future.delayed(const Duration(milliseconds: 200));
    await captureScreenshot(sessionDir: sessionDir);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已保存到本地反馈目录'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// 把工作流步骤置为运行中。
  void _markStep(int index, StepState state, [String? detail]) {
    if (!mounted) return;
    setState(() {
      _steps[index].state = state;
      _steps[index].detail = detail;
    });
  }

  /// 发 Issue：可视化工作流——写本地 → 截屏 → 读令牌 → 提交 GitHub。
  ///
  /// 任一步失败都保留本地备份，并在工作流视图中标红展示具体原因，不阻塞 UI。
  Future<void> _publishIssue() async {
    final description = _controller.text.trim();
    if (description.isEmpty) return;
    if (_savingLocal || _publishing) return;

    final route = _currentRoute;
    final t0 = DateTime.now().microsecondsSinceEpoch;
    Log().info('FEEDBACK: button_pressed(issue)',
        data: {'ts': t0, 'route': route, 'tag': _tag.label});

    setState(() {
      _publishing = true;
      _steps = [
        _FlowStep('① 写本地备份'),
        _FlowStep('② 截取 bug 现场'),
        _FlowStep('③ 读取 GitHub 令牌'),
        _FlowStep('④ 提交到 GitHub'),
      ];
    });

    // ── 步骤 ① 写本地备份（始终先执行，保证有回退） ──
    _markStep(0, StepState.running);
    String sessionDir;
    try {
      sessionDir = await _writeLocal(t0, route, description);
      _markStep(0, StepState.done, sessionDir);
    } catch (e) {
      _markStep(0, StepState.failed, '本地写入失败：$e');
      _finishWithLocalOnly('本地备份写入失败，无法继续');
      return;
    }

    // ── 步骤 ② 截屏（失败不致命，仅影响 issue 内嵌图） ──
    _markStep(1, StepState.running);
    String? shotPath;
    try {
      // 临时隐藏遮罩（保持 dialog mounted）才能截到 bug 现场
      widget.onCaptureMode?.call(true);
      await Future.delayed(const Duration(milliseconds: 200));
      shotPath = await captureScreenshot(sessionDir: sessionDir);
      widget.onCaptureMode?.call(false);
      _markStep(1, StepState.done, shotPath ?? '（无截图）');
    } catch (e) {
      // 截屏失败仅警告，继续发 issue；务必恢复遮罩
      widget.onCaptureMode?.call(false);
      _markStep(1, StepState.done, '截图失败，已跳过：$e');
    }

    // ── 步骤 ③ 读令牌 ──
    _markStep(2, StepState.running);
    final prefs = await SharedPreferences.getInstance();
    final token = getSetting(prefs, kGithubFeedbackTokenKey).trim();
    if (token.isEmpty) {
      _markStep(2, StepState.failed, '未填写 GitHub 令牌');
      _finishWithLocalOnly(
        '未填写 GitHub 令牌（设置 → GitHub 反馈令牌），已存本地备份',
      );
      return;
    }
    _markStep(2, StepState.done, '令牌已读取（${token.length} 字符）');

    // ── 步骤 ④ 提交 GitHub ──
    _markStep(3, StepState.running);
    final body = buildFeedbackBody(
      timestampUs: t0,
      route: route,
      tag: _tag.label,
      description: description,
      screenshotPath: shotPath,
    );
    final title = buildIssueTitle(tag: _tag.label, description: description);

    final result = await publishGithubIssue(
      token: token,
      title: title,
      body: body,
    );
    if (!mounted) return;

    switch (result) {
      case IssueSuccess(:final htmlUrl):
        _markStep(3, StepState.done, htmlUrl);
        _publishState = _PublishSuccess(htmlUrl);
        // 不自动关闭，由用户点「关闭」按钮
        if (mounted) setState(() => _publishing = false);
      case IssueFailure(:final reason, :final kind, :final rawMessage):
        final hint = _failureHint(kind, rawMessage);
        _markStep(3, StepState.failed, '$reason\n$hint');
        _publishState = _PublishFailure(reason, hint);
        // 不自动关闭，由用户点「关闭」按钮，保持可见
        if (mounted) setState(() => _publishing = false);
    }
  }

  /// 针对失败分类给出可操作提示。
  String _failureHint(IssueFailureKind kind, String? raw) {
    final detail = (raw != null && raw.isNotEmpty && raw != '请求失败')
        ? '\nGitHub 原文：$raw'
        : '';
    return switch (kind) {
      IssueFailureKind.auth =>
        '提示：令牌无效或权限不足，请在 GitHub 生成具有 repo 权限的 PAT，并重新在设置中填写。$detail',
      IssueFailureKind.network =>
        '提示：检查网络是否可访问 api.github.com（代理 / 防火墙 / 离线）。',
      IssueFailureKind.timeout =>
        '提示：网络较慢或 GitHub 限流，稍后重试。',
      IssueFailureKind.api =>
        '提示：GitHub 返回服务端错误，可稍后重试或查看原文。$detail',
      IssueFailureKind.noToken =>
        '提示：请先在设置填写 GitHub 反馈令牌。',
      IssueFailureKind.unknown =>
        '提示：发生未知错误，详情见日志。$detail',
    };
  }

  /// 工作流中途失败（本地已备份）时的收尾：不关闭弹窗，让用户看到失败步骤。
  Future<void> _finishWithLocalOnly(String msg) async {
    if (!mounted) return;
    setState(() => _publishing = false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 4)),
    );
  }

  /// 发 Issue 最终结果（成功/失败），用于底部展示。
  _PublishOutcome? _publishState;

  @override
  Widget build(BuildContext context) {
    final busy = _savingLocal || _publishing;
    return AlertDialog(
      title: Text('反馈：$_currentRoute'),
      content: _publishing && _steps.isNotEmpty
          ? _buildFlowView()
          : _buildInputView(busy),
      actions: _publishing && _steps.isNotEmpty
          ? [
              // 工作流进行中或失败后，允许关闭
              TextButton(
                onPressed: widget.onClose,
                child: const Text('关闭'),
              ),
            ]
          : [
              TextButton(
                onPressed: busy ? null : widget.onClose,
                child: const Text('取消'),
              ),
              OutlinedButton(
                onPressed: busy ? null : _saveLocal,
                child: _savingLocal
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('保存到本地'),
              ),
              FilledButton(
                onPressed: busy ? null : _publishIssue,
                child: _publishing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('发 Issue'),
              ),
            ],
    );
  }

  Widget _buildInputView(bool busy) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: FeedbackTag.values.map((tag) {
            final selected = _tag == tag;
            return ChoiceChip(
              label: Text(tag.label),
              selected: selected,
              onSelected: busy ? null : (_) => setState(() => _tag = tag),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
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
    );
  }

  /// 可视化工作流：每步状态 + 失败详情 + 最终结果。
  Widget _buildFlowView() {
    final outcome = _publishState;
    return SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ..._steps.map((s) => _buildStepRow(s)),
          if (outcome != null) ...[
            const SizedBox(height: 12),
            _buildOutcome(outcome),
          ],
        ],
      ),
    );
  }

  Widget _buildStepRow(_FlowStep s) {
    final (icon, color) = switch (s.state) {
      StepState.idle => (const Icon(Icons.circle_outlined, size: 18), Colors.grey),
      StepState.running => (const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2)),
          Colors.blue),
      StepState.done => (const Icon(Icons.check_circle, size: 18, color: Colors.green), Colors.green),
      StepState.failed => (const Icon(Icons.error, size: 18, color: Colors.red), Colors.red),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 22, height: 22, child: Center(child: icon)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
                if (s.detail != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: SelectableText(
                      s.detail!,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOutcome(_PublishOutcome outcome) {
    return switch (outcome) {
      _PublishSuccess(:final url) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('✅ Issue 提交成功',
                style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            InkWell(
              onTap: () async {
                try {
                  await Clipboard.setData(ClipboardData(text: url));
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Issue 链接已复制'), duration: Duration(seconds: 1)),
                    );
                  }
                } catch (_) {}
              },
              child: SelectableText(
                url,
                style: const TextStyle(
                    decoration: TextDecoration.underline, color: Colors.blue),
              ),
            ),
            const Text('（点击复制链接）', style: TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      _PublishFailure(:final reason, :final hint) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('❌ Issue 提交失败（本地备份已保留）',
                style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            SelectableText(reason, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            SelectableText(hint,
                style: const TextStyle(fontSize: 12, color: Colors.orange)),
          ],
        ),
    };
  }
}

/// 发 Issue 最终结果。
sealed class _PublishOutcome {
  const _PublishOutcome();
}
class _PublishSuccess extends _PublishOutcome {
  final String url;
  const _PublishSuccess(this.url);
}
class _PublishFailure extends _PublishOutcome {
  final String reason;
  final String hint;
  const _PublishFailure(this.reason, this.hint);
}
