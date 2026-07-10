/// 请求日志面板——实时展示用户 WebView 操作中捕获的 HTTP 请求。
///
/// 特性：
/// - 方法彩色标签（GET=绿 POST=蓝 PUT=橙 DELETE=红）
/// - URL 截断 + Tooltip 完整显示
/// - 可展开详情（headers、body）
/// - 时间戳 + 请求序号
/// - 底部按钮：开始抓包 / 分析日志
library request_log_panel;

import 'package:flutter/material.dart';

import 'scraper_workflow.dart';

/// 请求日志面板。
class RequestLogPanel extends StatelessWidget {
  final ScraperWorkflow workflow;
  final VoidCallback? onAnalyze;

  const RequestLogPanel({
    super.key,
    required this.workflow,
    this.onAnalyze,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final logs = workflow.logs;
    final isCapturing = workflow.phase == ScraperPhase.capturing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── 标题栏 ──
        _buildHeader(theme, logs.length, isCapturing),
        // ── 日志列表 ──
        Expanded(
          child: logs.isEmpty
              ? _buildEmptyState(theme, isCapturing)
              : ListView.builder(
                  itemCount: logs.length,
                  padding: EdgeInsets.zero,
                  itemBuilder: (ctx, i) => _buildLogItem(
                      ctx, theme, logs[logs.length - 1 - i], logs.length - i), // 最新的排最上面
                ),
        ),
        // ── 操作按钮 ──
        _buildActions(theme, logs.isNotEmpty, isCapturing),
      ],
    );
  }

  Widget _buildHeader(ThemeData theme, int count, bool isCapturing) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.http_rounded,
            size: 14,
            color: isCapturing ? Colors.green : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text(
            '请求日志',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 6),
          if (isCapturing)
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
              ),
            ),
          if (isCapturing) const SizedBox(width: 4),
          const Spacer(),
          Text(
            '$count 条',
            style: TextStyle(
              fontSize: 10,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme, bool isCapturing) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isCapturing ? Icons.wifi_find_rounded : Icons.language_rounded,
              size: 32,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 8),
            Text(
              isCapturing ? '正在监听网络请求...' : '在左侧 WebView 中浏览目标网站\nHTTP 请求将自动捕获',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogItem(BuildContext context, ThemeData theme, HttpRequestLog log, int index) {
    final methodColor = _methodColor(log.method);
    final isDark = theme.brightness == Brightness.dark;

    return InkWell(
      onTap: () => _showDetail(context, log, index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: theme.dividerColor.withValues(alpha: 0.3),
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 序号
            SizedBox(
              width: 20,
              child: Text(
                '#$index',
                style: TextStyle(
                  fontSize: 9,
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                ),
              ),
            ),
            // 方法标签
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: methodColor.withValues(alpha: isDark ? 0.2 : 0.1),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: methodColor.withValues(alpha: 0.3),
                  width: 0.5,
                ),
              ),
              child: Text(
                log.method,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: methodColor,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(width: 6),
            // URL
            Expanded(
              child: Tooltip(
                message: log.url,
                child: Text(
                  log.url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontFamily: 'monospace',
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ),
            // 时间
            const SizedBox(width: 4),
            Text(
              _formatTime(log.timestamp),
              style: TextStyle(
                fontSize: 9,
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActions(
      ThemeData theme, bool hasLogs, bool isCapturing) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          top: BorderSide(color: theme.dividerColor, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: hasLogs ? workflow.clearLogs : null,
              icon: const Icon(Icons.delete_outline, size: 14),
              label: const Text('清空', style: TextStyle(fontSize: 11)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 6),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 分析
          Expanded(
            flex: 2,
            child: FilledButton.icon(
              onPressed: hasLogs ? onAnalyze : null,
              icon: const Icon(Icons.analytics_rounded, size: 14),
              label: Text(
                hasLogs ? '分析日志 (${workflow.logs.length}条)' : '等待请求...',
                style: const TextStyle(fontSize: 11),
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 6),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showDetail(BuildContext context, HttpRequestLog log, int index) {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(16),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.5,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _methodColor(log.method).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    log.method,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _methodColor(log.method),
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '请求 #$index  ${_formatFullTime(log.timestamp)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const Divider(height: 16),
            // URL
            Text(
              'URL:',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 2),
            SelectableText(
              log.url,
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
            ),
            const SizedBox(height: 12),
            // Headers
            if (log.headers != null && log.headers!.isNotEmpty) ...[
              Text(
                'Headers:',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 2),
              ...log.headers!.entries.map((e) => SelectableText(
                    '  ${e.key}: ${e.value}',
                    style: const TextStyle(
                        fontSize: 10, fontFamily: 'monospace'),
                  )),
              const SizedBox(height: 12),
            ],
            // Body
            if (log.body != null && log.body!.isNotEmpty) ...[
              Text(
                'Body:',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 2),
              Expanded(
                child: SingleChildScrollView(
                  child: SelectableText(
                    log.body!,
                    style: const TextStyle(
                        fontSize: 10, fontFamily: 'monospace'),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _methodColor(String method) => switch (method) {
        'GET' => const Color(0xFF52C41A),
        'POST' => const Color(0xFF1677FF),
        'PUT' => const Color(0xFFFA8C16),
        'DELETE' => const Color(0xFFFF4D4F),
        'PATCH' => const Color(0xFF722ED1),
        _ => Colors.grey,
      };

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}'
        ':${dt.minute.toString().padLeft(2, '0')}'
        ':${dt.second.toString().padLeft(2, '0')}';
  }

  String _formatFullTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}'
        '-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}'
        ':${dt.minute.toString().padLeft(2, '0')}'
        ':${dt.second.toString().padLeft(2, '0')}';
  }
}
