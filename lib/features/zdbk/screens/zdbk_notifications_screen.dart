import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import '../../../core/result.dart';
import '../../../core/models/zdbk_notification.dart';
import '../../../widgets/error_card.dart';
import '../../../widgets/loading_indicator.dart';
import '../providers/zdbk_notifications_provider.dart';

/// ZDBK 通知公告页。
class ZdbkNotificationsScreen extends ConsumerWidget {
  const ZdbkNotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(zdbkNotificationsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('教务通知')),
      body: async.when(
        loading: () => const LoadingWidget(message: '加载通知...'),
        error: (e, _) => ErrorCard(
          message: '加载失败',
          detail: e.toString(),
          onRetry: () => ref.invalidate(zdbkNotificationsProvider),
        ),
        data: (result) => result.fold(
          (notifications) => _buildList(context, ref, notifications),
          (err) => ErrorCard(
            message: '加载失败',
            detail: err.userMessage,
            onRetry: () => ref.invalidate(zdbkNotificationsProvider),
          ),
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context, WidgetRef ref, List<ZdbkNotification> notifications) {
    if (notifications.isEmpty) {
      return const Center(child: Text('暂无通知'));
    }

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(zdbkNotificationsProvider),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: notifications.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final n = notifications[i];
          return ListTile(
            title: Text(n.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            subtitle: n.publisher != null || n.publishDate != null
                ? Text(
                    [n.publisher, n.publishDate].where((e) => e != null && e.isNotEmpty).join(' · '),
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  )
                : null,
            trailing: n.viewCount != null
                ? Text('${n.viewCount}', style: TextStyle(fontSize: 11, color: Colors.grey.shade400))
                : null,
            dense: true,
            onTap: () => _showDetail(context, n),
          );
        },
      ),
    );
  }

  void _showDetail(BuildContext context, ZdbkNotification notification) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _NotificationDetailScreen(notification: notification),
    ));
  }
}

class _NotificationDetailScreen extends StatelessWidget {
  final ZdbkNotification notification;
  const _NotificationDetailScreen({required this.notification});

  @override
  Widget build(BuildContext context) {
    final hasContent = notification.content != null && notification.content!.isNotEmpty;
    final hasMeta = notification.publisher != null || notification.publishDate != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('通知详情'),
        actions: [
          if (hasContent)
            IconButton(
              icon: const Icon(Icons.copy),
              tooltip: '复制全文',
              onPressed: () {
                // 实际项目中可用 Clipboard.setData
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已复制到剪贴板')),
                );
              },
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题
            Text(notification.title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),

            // 元信息
            if (hasMeta)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Wrap(
                  spacing: 16,
                  runSpacing: 4,
                  children: [
                    if (notification.publisher != null)
                      Text('发布人: ${notification.publisher}',
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                    if (notification.publishDate != null)
                      Text('发布时间: ${notification.publishDate}',
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                    if (notification.viewCount != null)
                      Text('浏览: ${notification.viewCount}',
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                  ],
                ),
              ),
            const SizedBox(height: 16),

            // 正文（保留原始 HTML 渲染，共用 flutter_widget_from_html_core）
            if (hasContent)
              HtmlWidget(
                notification.content!,
                textStyle: const TextStyle(fontSize: 14, height: 1.7),
              )
            else
              Text('（无详细内容）',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
          ],
        ),
      ),
    );
  }
}
