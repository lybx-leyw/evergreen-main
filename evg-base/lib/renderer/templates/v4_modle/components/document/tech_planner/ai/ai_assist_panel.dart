/// AI 助手面板。
///
/// 四模式交互：
/// - 补写（Complete）：AI 调研后补写缺失实现细节 → 幽灵文本
/// - 分析（Analyze）：AI 调研后输出只读风险分析报告 → 面板展示
/// - 改写（Revise）：AI 调研后逐段润色原文 → diff 对比
/// - 一键润色（Polish）：AI 调研后全量重写为可执行方案 → 替换全文
library;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/tech_planner/models/tech_document.dart';

/// AI 工作模式。
enum AiMode {
  /// AI 补写——续写缺失的实现细节（幽灵文本）。
  complete,

  /// AI 分析——只读风险分析 + 可行性调研。
  analyze,

  /// AI 改写——逐段润色原文（diff 对比）。
  revise,

  /// AI 一键润色——全量重写为可执行方案（替换全文）。
  polish,
}

/// AI 分析面板视图。
///
/// 顶部显示 4 个模式按钮，下方根据模式展示不同内容。
class AiAssistPanel extends StatefulWidget {
  /// 当前激活的 AI 模式。
  final AiMode currentMode;

  /// 当前分析报告（仅 analyze 模式使用）。
  final TechAnalysisReport? report;

  /// 是否正在分析中。
  final bool isLoading;

  /// 错误信息。
  final String? errorText;

  /// 模式完成后的提示文本（补写/改写/润色完成时显示）。
  final String? resultText;

  /// AI 实时思考流文本（加载中时显示，非空时替代 loading spinner）。
  final String? streamingText;

  /// 面板宽度。
  final double width;

  /// AI 补写回调。
  final VoidCallback? onComplete;

  /// AI 分析回调。
  final VoidCallback? onAnalyze;

  /// AI 改写回调。
  final VoidCallback? onRevise;

  /// AI 一键润色回调。
  final VoidCallback? onPolish;

  /// 关闭面板回调。
  final VoidCallback? onClose;

  const AiAssistPanel({
    super.key,
    this.currentMode = AiMode.analyze,
    this.report,
    this.isLoading = false,
    this.errorText,
    this.resultText,
    this.streamingText,
    this.width = 360,
    this.onComplete,
    this.onAnalyze,
    this.onRevise,
    this.onPolish,
    this.onClose,
  });

  @override
  State<AiAssistPanel> createState() => _AiAssistPanelState();
}

class _AiAssistPanelState extends State<AiAssistPanel> {
  final Set<String> _expandedSections = {'understanding', 'evidence'};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: widget.width,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(left: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 标题栏 ──
          _buildHeader(theme, colorScheme),

          // ── 四模式按钮栏 ──
          _buildModeBar(theme, colorScheme),

          // ── 分隔线 ──
          Divider(height: 1, color: colorScheme.outlineVariant),

          // ── 内容区 ──
          Expanded(child: _buildContent(theme, colorScheme)),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, ColorScheme colorScheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.tertiaryContainer.withValues(alpha: 0.3),
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Icon(Icons.psychology_outlined, size: 18, color: colorScheme.tertiary),
          const SizedBox(width: 8),
          Expanded(
            child: Text('AI 助手',
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: colorScheme.tertiary)),
          ),
          // 模式提示
          if (!widget.isLoading && widget.resultText == null)
            Text(
              _modeLabel(widget.currentMode),
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.tertiary.withValues(alpha: 0.7),
              ),
            ),
          if (widget.onClose != null) ...[
            const SizedBox(width: 8),
            IconButton(
              onPressed: widget.onClose,
              icon: Icon(Icons.close, size: 16, color: colorScheme.onSurfaceVariant),
              tooltip: '关闭',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
          ],
        ],
      ),
    );
  }

  /// 四模式按钮栏。
  Widget _buildModeBar(ThemeData theme, ColorScheme colorScheme) {
    final modes = [
      (_ModeItem(Icons.text_increase, '补写', '续写缺失的实现细节', AiMode.complete, widget.onComplete)),
      (_ModeItem(Icons.search, '分析', '风险分析与可行性调研', AiMode.analyze, widget.onAnalyze)),
      (_ModeItem(Icons.edit_note, '改写', '逐段润色使表述精准', AiMode.revise, widget.onRevise)),
      (_ModeItem(Icons.auto_awesome, '润色', '全量重写为可执行方案', AiMode.polish, widget.onPolish)),
    ];

    final isBusy = widget.isLoading;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: Row(
        children: [
          for (final m in modes)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: _ModeButton(
                  item: m,
                  isActive: widget.currentMode == m.mode,
                  isBusy: isBusy,
                  colorScheme: colorScheme,
                  theme: theme,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildContent(ThemeData theme, ColorScheme colorScheme) {
    // ── 加载中 ──
    if (widget.isLoading) {
      // 有流式文本 → 显示 AI 实时思考过程
      final stream = widget.streamingText;
      if (stream != null && stream.isNotEmpty) {
        return _buildStreamingView(theme, colorScheme, stream);
      }
      // 无流式文本 → 显示加载占位
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 48, height: 48,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: 16),
            Text('${_modeActionLabel(widget.currentMode)}中...',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: colorScheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            Text(_modeLoadingHint(widget.currentMode),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: colorScheme.onSurfaceVariant)),
          ],
        ),
      );
    }

    // ── 错误 ──
    if (widget.errorText != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: colorScheme.error),
              const SizedBox(height: 12),
              Text(widget.errorText!, textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: colorScheme.error)),
            ],
          ),
        ),
      );
    }

    // ── 结果展示（补写/改写/润色完成后） ──
    if (widget.resultText != null) {
      return _buildResultView(theme, colorScheme);
    }

    // ── 分析模式报告 ──
    if (widget.currentMode == AiMode.analyze &&
        widget.report != null &&
        !widget.report!.isEmpty) {
      return _buildAnalysisReport(theme, colorScheme, widget.report!);
    }

    // ── 空白状态 ──
    return _buildEmptyState(theme, colorScheme);
  }

  /// 完成结果展示。
  Widget _buildResultView(ThemeData theme, ColorScheme colorScheme) {
    final icon = switch (widget.currentMode) {
      AiMode.complete => Icons.text_increase,
      AiMode.revise => Icons.edit_note,
      AiMode.polish => Icons.auto_awesome,
      _ => Icons.check_circle,
    };
    final color = switch (widget.currentMode) {
      AiMode.complete => Colors.blue,
      AiMode.revise => Colors.purple,
      AiMode.polish => Colors.amber,
      _ => Colors.green,
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: color),
            const SizedBox(height: 12),
            Text(
              '${_modeLabel(widget.currentMode)}完成',
              style: theme.textTheme.titleMedium?.copyWith(
                color: color, fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            if (widget.resultText != null)
              Text(
                widget.resultText!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 空白状态。
  Widget _buildEmptyState(ThemeData theme, ColorScheme colorScheme) {
    final (String hint, String subHint) = switch (widget.currentMode) {
      AiMode.complete => (
        '点击「补写」按钮',
        'AI 会调研仓库后在文档末尾续写实现细节',
      ),
      AiMode.analyze => (
        '点击「分析」按钮',
        'AI 会调研仓库后给出风险分析和技术建议',
      ),
      AiMode.revise => (
        '点击「改写」按钮',
        'AI 会逐段润色原文，生成 diff 比对',
      ),
      AiMode.polish => (
        '点击「润色」按钮',
        'AI 会将全文重写为可执行的技术方案',
      ),
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.touch_app_outlined, size: 48,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text(hint,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: colorScheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text(subHint,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: Colors.white30)),
          ],
        ),
      ),
    );
  }

  /// AI 实时思考流显示——打字机效果展示生成中的文本。
  Widget _buildStreamingView(
      ThemeData theme, ColorScheme colorScheme, String text) {
    final scrollCtrl = ScrollController();
    // 自动滚到底部
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scrollCtrl.hasClients) {
        scrollCtrl.animateTo(scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut);
      }
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 顶部状态条
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: colorScheme.tertiaryContainer.withValues(alpha: 0.2),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 12, height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: colorScheme.tertiary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${_modeActionLabel(widget.currentMode)}...',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: colorScheme.tertiary),
              ),
              const Spacer(),
              Text('${text.length} 字',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: Colors.white30, fontSize: 10)),
            ],
          ),
        ),

        // 流式文本内容
        Expanded(
          child: SingleChildScrollView(
            controller: scrollCtrl,
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1.6,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 分析报告（analyze 模式专用）。
  Widget _buildAnalysisReport(
      ThemeData theme, ColorScheme colorScheme, TechAnalysisReport report) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionCard(
            theme, colorScheme,
            key: 'understanding',
            icon: Icons.article_outlined,
            iconColor: colorScheme.primary,
            title: '设计理解',
            children: [
              Text(report.understanding, style: theme.textTheme.bodyMedium),
            ],
          ),
          if (report.evidence.isNotEmpty)
            _sectionCard(
              theme, colorScheme,
              key: 'evidence',
              icon: Icons.science_outlined,
              iconColor: Colors.green,
              title: '可行性支撑',
              children: report.evidence.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.green.withValues(alpha: 0.15)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.content,
                          style: theme.textTheme.bodySmall?.copyWith(fontSize: 13)),
                      const SizedBox(height: 2),
                      _buildSourceLine(theme, e),
                    ],
                  ),
                ),
              )).toList(),
            ),
          if (report.blindSpots.isNotEmpty)
            _sectionCard(
              theme, colorScheme,
              key: 'blindSpots',
              icon: Icons.warning_amber_outlined,
              iconColor: Colors.orange,
              title: '盲区补充',
              children: report.blindSpots
                  .map((s) => _bulletItem(theme, '•', s, Colors.orange.shade200))
                  .toList(),
            ),
          if (report.newIdeas.isNotEmpty)
            _sectionCard(
              theme, colorScheme,
              key: 'newIdeas',
              icon: Icons.lightbulb_outline,
              iconColor: Colors.amber,
              title: '建议',
              children: report.newIdeas
                  .map((s) => _bulletItem(theme, '→', s, Colors.amber.shade200))
                  .toList(),
            ),
          if (report.risks.isNotEmpty)
            _sectionCard(
              theme, colorScheme,
              key: 'risks',
              icon: Icons.error_outline,
              iconColor: Colors.red,
              title: '风险',
              children: report.risks
                  .map((s) => _bulletItem(theme, '!', s, Colors.red.shade300))
                  .toList(),
            ),
        ],
      ),
    );
  }

  // ═══════ UI 组件 ═══════

  Widget _sectionCard(
    ThemeData theme, ColorScheme colorScheme, {
    required String key,
    required IconData icon,
    required Color iconColor,
    required String title,
    required List<Widget> children,
  }) {
    final isExpanded = _expandedSections.contains(key);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() {
              if (isExpanded) {
                _expandedSections.remove(key);
              } else {
                _expandedSections.add(key);
              }
            }),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Icon(icon, size: 16, color: iconColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(title,
                        style: theme.textTheme.labelMedium?.copyWith(color: iconColor)),
                  ),
                  Icon(isExpanded ? Icons.expand_less : Icons.expand_more,
                      size: 18, color: colorScheme.onSurfaceVariant),
                ],
              ),
            ),
          ),
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 10, 10),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: children),
            ),
        ],
      ),
    );
  }

  Widget _bulletItem(ThemeData theme, String bullet, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$bullet ', style: TextStyle(color: color, fontSize: 13)),
          Expanded(
            child: Text(text,
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceLine(ThemeData theme, TechEvidence e) {
    if (e.url != null && e.url!.isNotEmpty) {
      return RichText(
        text: TextSpan(
          style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 11, color: Colors.green.shade300),
          children: [
            const TextSpan(text: '— '),
            TextSpan(
              text: e.source,
              style: TextStyle(
                color: Colors.green.shade300,
                decoration: TextDecoration.underline,
              ),
              recognizer: TapGestureRecognizer()
                ..onTap = () {
                  final uri = Uri.tryParse(e.url!);
                  if (uri != null) {
                    launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
            ),
          ],
        ),
      );
    }
    return Text('— ${e.source}',
        style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 11, color: Colors.green.shade300));
  }

  // ═══════ 辅助 ═══════

  static String _modeLabel(AiMode mode) => switch (mode) {
    AiMode.complete => '补写',
    AiMode.analyze => '分析',
    AiMode.revise => '改写',
    AiMode.polish => '一键润色',
  };

  static String _modeActionLabel(AiMode mode) => switch (mode) {
    AiMode.complete => '正在撰写补全内容',
    AiMode.analyze => '正在分析',
    AiMode.revise => '正在改写',
    AiMode.polish => '正在润色',
  };

  static String _modeLoadingHint(AiMode mode) => switch (mode) {
    AiMode.complete => '调研仓库架构、生成续写内容...',
    AiMode.analyze => '调研技术方案、评估风险...',
    AiMode.revise => '调研仓库模式、逐段精准润色...',
    AiMode.polish => '调研仓库全貌、构建完整技术方案...',
  };
}

/// 模式按钮数据。
class _ModeItem {
  final IconData icon;
  final String label;
  final String tooltip;
  final AiMode mode;
  final VoidCallback? onTap;
  const _ModeItem(this.icon, this.label, this.tooltip, this.mode, this.onTap);
}

/// 单个模式按钮。
class _ModeButton extends StatelessWidget {
  final _ModeItem item;
  final bool isActive;
  final bool isBusy;
  final ColorScheme colorScheme;
  final ThemeData theme;

  const _ModeButton({
    required this.item,
    required this.isActive,
    required this.isBusy,
    required this.colorScheme,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final onPressed = (item.onTap != null && !isBusy) ? item.onTap : null;
    final bg = isActive
        ? colorScheme.tertiaryContainer
        : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5);
    final fg = isActive ? colorScheme.onTertiaryContainer : colorScheme.onSurfaceVariant;

    return Tooltip(
      message: item.tooltip,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(item.icon, size: 18, color: fg),
                const SizedBox(height: 2),
                Text(
                  item.label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: fg,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
