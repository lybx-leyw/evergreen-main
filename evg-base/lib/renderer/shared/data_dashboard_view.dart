/// 数据中枢面板——内置于模块，直连 DataOrchestrator，展示所有数据源状态。
///
/// 逻辑：
/// - 加载时列出所有已注册数据源及其新鲜度
/// - 从未拉取的数据源显示"点击拉取"按钮（调用 orch.get）
/// - 已拉取过的数据源显示新鲜度 + "重新拉取"按钮（调用 orch.refresh）
/// - 永不自动拉取，只响应用户点击
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:evergreen_base/core/data/data.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/providers.dart';

class DataDashboardView extends ConsumerStatefulWidget {
  final ModuleDescriptor descriptor;
  const DataDashboardView({super.key, required this.descriptor});

  @override
  ConsumerState<DataDashboardView> createState() => _DataDashboardViewState();
}

class _DataDashboardViewState extends ConsumerState<DataDashboardView> {
  List<DataSourceStatus> _statuses = [];
  Map<String, bool> _loading = {};

  @override
  void initState() {
    super.initState();
    _refreshStatuses();
  }

  void _refreshStatuses() {
    final orch = ref.read(dataOrchestratorProvider);
    _statuses = orch.allStatuses;
  }

  Future<void> _fetchSource(DataSourceStatus status) async {
    final orch = ref.read(dataOrchestratorProvider);
    final type = DataType<dynamic>(
      name: status.name,
      category: status.category,
      displayName: status.displayName,
      ttl: status.ttl,
    );
    setState(() => _loading[status.name] = true);
    try {
      // 首次用 get（缓存优先，无缓存才拉取），后续用 refresh
      if (status.lastFetchedAt == null) {
        await orch.get(type);
      } else {
        await orch.refresh(type);
      }
    } catch (_) {}
    if (mounted) {
      setState(() {
        _loading[status.name] = false;
        _refreshStatuses();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final items = _statuses;
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.storage, size: 48, color: theme.colorScheme.primary.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text('暂无注册数据源', style: theme.textTheme.bodyLarge),
            const SizedBox(height: 4),
            Text('data 插件将在启动时自动注册', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      );
    }

    // 按 category 分组
    final grouped = <String, List<DataSourceStatus>>{};
    for (final s in items) {
      grouped.putIfAbsent(s.category.isNotEmpty ? s.category : '其他', () => []);
      grouped[s.category.isNotEmpty ? s.category : '其他']!.add(s);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 汇总栏
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [Colors.blueGrey.shade800, Colors.blueGrey.shade900]
                  : [Colors.blue.shade50, Colors.blue.shade100],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: _StatTile(
                  icon: Icons.storage,
                  label: '数据源',
                  value: '${items.length}',
                  color: theme.colorScheme.primary,
                ),
              ),
              Container(width: 1, height: 36, color: theme.dividerColor),
              Expanded(
                child: _StatTile(
                  icon: Icons.check_circle,
                  label: '连通',
                  value: '${items.where((s) => s.connected).length}',
                  color: Colors.green,
                ),
              ),
              Container(width: 1, height: 36, color: theme.dividerColor),
              Expanded(
                child: _StatTile(
                  icon: Icons.access_time,
                  label: '新鲜',
                  value: '${items.where((s) => s.isFresh).length}',
                  color: Colors.orange,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // 分组列表
        for (final entry in grouped.entries) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8, top: 8),
            child: Text(entry.key,
                style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary)),
          ),
          ...entry.value.map((s) => _SourceCard(
                status: s,
                loading: _loading[s.name] == true,
                onTap: () => _fetchSource(s),
              )),
        ],
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _StatTile({required this.icon, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color)),
        Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

class _SourceCard extends StatelessWidget {
  final DataSourceStatus status;
  final bool loading;
  final VoidCallback onTap;
  const _SourceCard({required this.status, required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final never = status.lastFetchedAt == null;
    final label = never ? '点击拉取' : (status.isFresh ? '新鲜 · ${status.relativeTime}' : '过期 · ${status.relativeTime}');
    final labelColor = never
        ? theme.colorScheme.primary
        : status.isFresh
            ? Colors.green
            : Colors.orange;

    return Card(
      elevation: 0,
      color: isDark ? Colors.grey.shade900 : Colors.grey.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: never
              ? theme.colorScheme.primary.withValues(alpha: 0.3)
              : status.connected
                  ? (status.isFresh ? Colors.green.withValues(alpha: 0.3) : Colors.orange.withValues(alpha: 0.3))
                  : Colors.red.withValues(alpha: 0.3),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // 状态指示
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: never
                      ? theme.colorScheme.primary
                      : status.connected
                          ? (status.isFresh ? Colors.green : Colors.orange)
                          : Colors.red,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(status.displayName,
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(label, style: TextStyle(fontSize: 12, color: labelColor)),
                        if (status.lastError != null) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(status.lastError!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11, color: Colors.red.shade300)),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (loading)
                const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              else
                Icon(
                  never ? Icons.download : Icons.refresh,
                  size: 20,
                  color: labelColor,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
