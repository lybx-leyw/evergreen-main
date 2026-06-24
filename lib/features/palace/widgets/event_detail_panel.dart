/// Palace 事件详情面板 —— 点击事件卡片后展开的全文视图。
library;

import 'package:flutter/material.dart';

import '../../../core/palace/models/consciousness_event.dart'
    show ConsciousnessEvent, EventType, SourceTool;

/// 事件类型的中文名 + 图标。
String _typeLabel(EventType type) => switch (type) {
  EventType.thought => '💡 想法',
  EventType.lesson => '📖 教训',
  EventType.decision => '🎯 决策',
  EventType.reflection => '🪞 反思',
  EventType.connection => '🔗 连接',
  EventType.milestone => '🏔️ 节点',
};

String _sourceLabel(SourceTool source) => switch (source) {
  SourceTool.agent => 'AI 助手',
  SourceTool.manual => '手动输入',
  SourceTool.tutor => 'AI 笔记',
  SourceTool.todo => '待办',
  SourceTool.scores => '成绩',
  SourceTool.courses => '课程',
  SourceTool.classroom => '智云课堂',
  SourceTool.wordpecker => '背词',
  SourceTool.external => '外部',
};

/// 事件详情面板——全文内容 + AI 摘要 + 元数据。
class EventDetailPanel extends StatelessWidget {
  final ConsciousnessEvent event;

  const EventDetailPanel({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 类型 + 来源
            Row(
              children: [
                Chip(
                  avatar: const Icon(Icons.tag, size: 14),
                  label: Text(_typeLabel(event.type),
                      style: theme.textTheme.labelSmall),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '来源：${_sourceLabel(event.source)} · '
                    '${_formatDate(event.capturedAt)}',
                    style: theme.textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // AI 摘要
            if (event.aiSummary != null && event.aiSummary!.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.auto_awesome, size: 16,
                        color: theme.colorScheme.tertiary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        event.aiSummary!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // 正文
            Text(
              event.rawContent,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 12),

            // 标签
            if (event.tagIds.isNotEmpty)
              Wrap(
                spacing: 6,
                children: event.tagIds
                    .map((t) => Chip(
                          label: Text(t, style: theme.textTheme.labelSmall),
                          visualDensity: VisualDensity.compact,
                        ))
                    .toList(),
              ),

            // 情境快照
            if (event.context != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _contextSummary(event.context!),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(dt.year, dt.month, dt.day);

    if (date == today) return '今天 ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    if (date == today.subtract(const Duration(days: 1))) return '昨天';
    return '${dt.month}月${dt.day}日';
  }

  String _contextSummary(dynamic ctx) {
    final parts = <String>[];
    if (ctx.activeFeature != null) parts.add('在"${ctx.activeFeature}"模块');
    if (ctx.activeTask != null && ctx.activeTask!.isNotEmpty) {
      parts.add('处理"${ctx.activeTask}"');
    }
    if (ctx.triggerSource != null) {
      parts.add(ctx.triggerSource.toString());
    }
    return parts.isEmpty ? '' : '情境：${parts.join(' · ')}';
  }
}
