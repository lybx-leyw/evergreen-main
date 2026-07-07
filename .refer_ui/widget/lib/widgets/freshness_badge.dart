/// 数据新鲜度徽章 — 显示缓存数据的"上次更新时间"。
///
/// 用于各数据页面的 AppBar actions 区域。
import 'package:flutter/material.dart';
import '../core/storage/database.dart';

/// 数据新鲜度指示器。
class FreshnessBadge extends StatelessWidget {
  /// WebCacheDatabase 缓存 key（为 null 或空字符串时仅依赖 lastFetchedAt）。
  final String cacheKey;

  /// 内存中的最后更新时间（优先于 cacheKey）。
  final DateTime? lastFetchedAt;

  const FreshnessBadge({
    super.key,
    this.cacheKey = '',
    this.lastFetchedAt,
  });

  String get _relativeTime {
    final ts = lastFetchedAt ??
        WebCacheDatabase.instanceOrNull?.getCacheTimestamp(cacheKey);
    if (ts == null) return '从未更新';
    final diff = DateTime.now().difference(ts);
    if (diff.inSeconds < 60) return '刚刚更新';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    return '${diff.inDays}天前';
  }

  bool get _hasData =>
      lastFetchedAt != null ||
      (cacheKey.isNotEmpty &&
          WebCacheDatabase.instanceOrNull?.getCacheTimestamp(cacheKey) != null);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.access_time,
              size: 14, color: Theme.of(context).colorScheme.outline),
          const SizedBox(width: 4),
          Text(
            _hasData ? _relativeTime : '从未更新',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ],
      ),
    );
  }
}
