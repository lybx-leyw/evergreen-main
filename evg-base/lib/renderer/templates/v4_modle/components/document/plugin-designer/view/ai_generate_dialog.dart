/// AI 生成插件对话框 —— 设计器"✨ AI 生成"入口的承载 UI。
///
/// 用户输入自然语言描述 → 调用 [AiDesignGenerator] → 成功后将生成的
/// [DesignDocument] 通过 [onGenerated] 回传（由设计器替换 `_doc` 并刷新预览）。
///
/// [generator] 可注入（测试用 fake）；为空时从 SharedPreferences 读取
/// DeepSeek API Key 自行构建 [agent.DeepSeekProvider]。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:evergreen_base/providers.dart';
import 'package:evergreen_base/core/config/settings.dart';
import 'package:evergreen_base/core/agent/agent.dart' as agent;
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/models/design_document.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/services/ai_design_generator.dart';

/// AI 生成对话框。
class AiGenerateDialog extends ConsumerStatefulWidget {
  /// 生成成功回调（设计器据此替换 `_doc`）。
  final void Function(DesignDocument) onGenerated;

  /// 可注入的生成器（测试用）；为空则按 API Key 自建。
  final AiDesignGenerator? generator;

  /// 改稿模式的基准设计；非空时进入"基于现有设计修改"模式。
  final DesignDocument? baseDoc;

  const AiGenerateDialog({
    super.key,
    required this.onGenerated,
    this.generator,
    this.baseDoc,
  });

  @override
  ConsumerState<AiGenerateDialog> createState() => _AiGenerateDialogState();
}

class _AiGenerateDialogState extends ConsumerState<AiGenerateDialog> {
  final _ctrl = TextEditingController();
  final StringBuffer _streamBuf = StringBuffer();
  bool _running = false;
  String _streamText = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  AiDesignGenerator _buildGenerator() {
    final prefs = ref.read(sharedPreferencesProvider);
    final apiKey = getSetting(prefs, 'DEEPSEEK_API_KEY');
    if (apiKey.isEmpty) {
      throw AiGenerateException(
        reason: 'no_api_key',
        message: '未配置 DeepSeek API Key，请在设置中配置后重试',
      );
    }
    final provider = agent.DeepSeekProvider(
      dio: Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 120),
      )),
      apiKey: apiKey,
    );
    return AiDesignGenerator(provider);
  }

  Future<void> _generate() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _running) return;

    setState(() {
      _running = true;
      _streamText = '';
      _streamBuf.clear();
    });

    try {
      final gen = widget.generator ?? _buildGenerator();
      final doc = await gen.generate(
        text,
        base: widget.baseDoc,
        onToken: (delta) {
        _streamBuf.write(delta);
        if (mounted) setState(() => _streamText = _streamBuf.toString());
      });
      if (!mounted) return;
      widget.onGenerated(doc);
      Navigator.of(context).pop();
    } on AiGenerateException catch (e) {
      if (!mounted) return;
      setState(() => _running = false);
      _showError('生成失败：${e.message}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _running = false);
      _showError('生成异常：$e');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.auto_awesome, size: 18),
          const SizedBox(width: 8),
          const Text('✨ AI 生成插件'),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _ctrl,
              enabled: !_running,
              maxLines: 4,
              minLines: 2,
              decoration: const InputDecoration(
                hintText: '用一句话描述你想要的插件，例如：\n'
                    '“做一个课程表插件，首页用网格展示本周课表，再加一个关于页”',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            if (widget.baseDoc != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.auto_fix_high, size: 14),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '改稿模式：将基于「${widget.baseDoc!.pluginName}」'
                        '进行修改，请描述你想改动的部分',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
            if (_running) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              const Text('AI 正在理解需求并生成设计…',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 6),
              Container(
                height: 120,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    _streamText.isEmpty ? '（等待 AI 输出…）' : _streamText,
                    style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _running ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: _running ? null : _generate,
          icon: _running
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.auto_awesome, size: 16),
          label: Text(_running ? '生成中…' : '生成'),
        ),
      ],
    );
  }
}
