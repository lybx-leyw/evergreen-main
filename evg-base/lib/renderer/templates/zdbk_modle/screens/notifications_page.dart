/// 教务通知页（modle_route: notifications）——照搬 `.reference/.../zdbk_notifications_screen.dart`
/// 的 UI 逻辑，数据源由内嵌/直连改为数据中枢（orch://zdbk_notifications）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';

import 'package:evergreen_base/core/module/module_descriptor.dart';

import '../models.dart';
import '../zdbk_view.dart';

class NotificationsPage extends ConsumerStatefulWidget {
  final WidgetRef ref;
  final Map<String, DataSourceDescriptor> sources;
  const NotificationsPage({super.key, required this.ref, required this.sources});

  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
  Future<Map<String, dynamic>>? _future;
  List<ZdbkNotification> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _future = zdbkResolve(widget.ref, widget.sources);
    });
    _future!.then((m) {
      if (mounted) {
        setState(() => _items = ZdbkData.notifications(
            m['notifications'], widget.sources['notifications']?.bindings));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final raw = snap.data?['notifications'];
        if (snap.hasError || (_items.isEmpty && raw == null)) {
          return zdbkError('加载失败', _load);
        }
        if (_items.isEmpty) {
          return zdbkEmpty('暂无通知');
        }
        final theme = Theme.of(context);
        return Column(
          children: [
            zdbkPageHeader(context, '教务通知'),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async => _load(),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final n = _items[i];
                    return ListTile(
                      title: Text(n.title,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w500)),
                      subtitle: (n.publisher != null || n.publishDate != null)
                          ? Text(
                              [n.publisher, n.publishDate]
                                  .where((e) => e != null && e.isNotEmpty)
                                  .join(' · '),
                              style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurfaceVariant),
                            )
                          : null,
                      trailing: n.viewCount != null
                          ? Text('${n.viewCount}',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: theme.colorScheme.outline))
                          : null,
                      dense: true,
                      onTap: () => _showDetail(context, n),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showDetail(BuildContext context, ZdbkNotification n) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _NotificationDetailScreen(notification: n),
    ));
  }
}

class _NotificationDetailScreen extends StatelessWidget {
  final ZdbkNotification notification;
  const _NotificationDetailScreen({required this.notification});

  @override
  Widget build(BuildContext context) {
    final n = notification;
    final theme = Theme.of(context);
    final hasContent = n.content != null && n.content!.isNotEmpty;
    final hasMeta = n.publisher != null || n.publishDate != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('通知详情'),
        actions: [
          if (hasContent)
            IconButton(
              icon: const Icon(Icons.copy),
              tooltip: '复制全文',
              onPressed: () {
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
            Text(n.title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (hasMeta)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Wrap(
                  spacing: 16,
                  runSpacing: 4,
                  children: [
                    if (n.publisher != null)
                      Text('发布人: ${n.publisher}',
                          style: TextStyle(
                              fontSize: 13,
                              color: theme.colorScheme.onSurfaceVariant)),
                    if (n.publishDate != null)
                      Text('发布时间: ${n.publishDate}',
                          style: TextStyle(
                              fontSize: 13,
                              color: theme.colorScheme.onSurfaceVariant)),
                    if (n.viewCount != null)
                      Text('浏览: ${n.viewCount}',
                          style: TextStyle(
                              fontSize: 13,
                              color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            if (hasContent)
              HtmlWidget(
                n.content!,
                textStyle: const TextStyle(fontSize: 14, height: 1.7),
              )
            else
              Text('（无详细内容）',
                  style: TextStyle(fontSize: 13, color: theme.colorScheme.outline)),
          ],
        ),
      ),
    );
  }
}
