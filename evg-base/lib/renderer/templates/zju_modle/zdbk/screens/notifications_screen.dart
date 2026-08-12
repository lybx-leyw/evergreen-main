/// 教务通知视图（zju / zdbk → 教务通知）。
///
/// B3-zdbk（2026-08-12）自参考工程
/// `cp_evergreen_push/lib/features/zdbk/screens/zdbk_notifications_screen.dart`
/// 移植，改造点：
/// - 模块主区去 Scaffold/AppBar（evg-base 桌面规范，页面自绘标题头）；
/// - 数据改经数据中枢 `orch.fastReadByName('zju_notifications')`；
/// - `ZdbkNotification`→`ZjuZdbkNotification`；
/// - 详情页保留 Scaffold（临时路由页面，参考实现同款）；正文用
///   `flutter_widget_from_html_core` 的 HtmlWidget 渲染（evg-base 已有该依赖）。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import 'package:evergreen_base/providers.dart' show dataOrchestratorProvider;

import '../../shared/models/zju_zdbk_notification.dart';

/// 教务通知主视图：通知列表 + 详情页。
class NotificationsView extends ConsumerStatefulWidget {
  const NotificationsView({super.key});

  @override
  ConsumerState<NotificationsView> createState() => _NotificationsViewState();
}

class _NotificationsViewState extends ConsumerState<NotificationsView> {
  Future<Map<String, dynamic>?>? _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  /// 经数据中枢拉取（内存快读 → 磁盘/网络）。
  Future<Map<String, dynamic>?> _fetch() async {
    final orch = ref.read(dataOrchestratorProvider);
    if (orch.typeByName('zju_notifications') == null) {
      throw StateError('数据源 zju_notifications 未注册');
    }
    final mem = await orch.fastReadByName('zju_notifications');
    if (mem != null) return mem as Map<String, dynamic>;
    final data = await orch.getByName('zju_notifications');
    return data as Map<String, dynamic>?;
  }

  void _reload() => setState(() => _future = _fetch());

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(),
        Expanded(
          child: FutureBuilder<Map<String, dynamic>?>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) return _buildError(snap.error.toString());
              final data = snap.data;
              if (data == null) return _buildError(_statusError());
              final notifications =
                  ((data['notifications'] as List<dynamic>?) ?? [])
                      .map((e) => ZjuZdbkNotification.fromJson(
                          e as Map<String, dynamic>))
                      .toList();
              if (notifications.isEmpty) return _buildEmpty();
              return _buildList(notifications);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      child: Row(
        children: [
          Text('教务通知', style: Theme.of(context).textTheme.titleLarge),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: _reload,
          ),
        ],
      ),
    );
  }

  Widget _buildError(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 40, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            const Text('加载教务通知失败', style: TextStyle(fontSize: 15)),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: _reload,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  String _statusError() {
    final orch = ref.read(dataOrchestratorProvider);
    final s = orch.status('zju_notifications');
    final err = s?.lastError;
    if (err == null || err.isEmpty) return '数据源未连接（zju_notifications）';
    if (err.contains('未配置') || err.contains('设置')) {
      return '$err\n请先在「设置」中填写学号密码，再点重试。';
    }
    return err;
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.campaign, size: 40, color: Colors.grey.shade400),
          const SizedBox(height: 8),
          const Text('暂无教务通知', style: TextStyle(fontSize: 15)),
          const SizedBox(height: 4),
          Text(
            '教务网通知公告公布后显示',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  /// 通知列表——下拉刷新（B3-ui，对齐参考 RefreshIndicator）。
  Widget _buildList(List<ZjuZdbkNotification> notifications) {
    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
        itemCount: notifications.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 16),
        itemBuilder: (_, i) {
          final n = notifications[i];
          return ListTile(
            title: Text(n.title,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            subtitle: (n.publisher != null && n.publisher!.isNotEmpty) ||
                    (n.publishDate != null && n.publishDate!.isNotEmpty)
                ? Text(
                    [n.publisher, n.publishDate]
                        .where((e) => e != null && e.isNotEmpty)
                        .join(' · '),
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  )
                : null,
            trailing: n.viewCount != null
                ? Text('${n.viewCount}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade400))
                : null,
            dense: true,
            onTap: () => _showDetail(n),
          );
        },
      ),
    );
  }

  void _showDetail(ZjuZdbkNotification notification) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => _NotificationDetailScreen(notification: notification),
    ));
  }
}

/// 通知详情页（临时路由，保留 Scaffold——参考实现同款）。
class _NotificationDetailScreen extends StatelessWidget {
  final ZjuZdbkNotification notification;

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
              onPressed: () => _copyFullText(context),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(notification.title,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (hasMeta)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Wrap(
                  spacing: 16,
                  runSpacing: 4,
                  children: [
                    if (notification.publisher != null)
                      Text('发布人: ${notification.publisher}',
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey.shade700)),
                    if (notification.publishDate != null)
                      Text('发布时间: ${notification.publishDate}',
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey.shade700)),
                    if (notification.viewCount != null)
                      Text('浏览: ${notification.viewCount}',
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey.shade700)),
                  ],
                ),
              ),
            const SizedBox(height: 16),
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

  /// 复制全文到剪贴板（B3-ui：标题 + 元信息 + 正文纯文本，参考「复制全文」按钮）。
  Future<void> _copyFullText(BuildContext context) async {
    final parts = <String>[
      notification.title,
      if (notification.publisher != null) '发布人: ${notification.publisher}',
      if (notification.publishDate != null)
        '发布时间: ${notification.publishDate}',
      if (notification.content != null && notification.content!.isNotEmpty)
        _stripHtml(notification.content!),
    ];
    await Clipboard.setData(ClipboardData(text: parts.join('\n\n')));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制全文到剪贴板'), duration: Duration(seconds: 1)),
    );
  }

  /// HTML → 纯文本（段落转行 + 去标签 + 常见实体解码）。
  static String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }
}
