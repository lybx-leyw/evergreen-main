import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/connectivity/connection_manager.dart';
import '../providers/connectivity_provider.dart' show connectivityCheckProvider, connectionManagerProvider;

/// 快速连接——一键检查所有服务的连通性，支持逐项重试。
class QuickConnectScreen extends ConsumerStatefulWidget {
  const QuickConnectScreen({super.key});

  @override
  ConsumerState<QuickConnectScreen> createState() => _QuickConnectScreenState();
}

class _QuickConnectScreenState extends ConsumerState<QuickConnectScreen>
    with WidgetsBindingObserver {
  // 逐项重试的结果管理
  final Map<String, AsyncValue<ConnectionResult>> _retryResults = {};
  final Set<String> _retrying = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 进入页面时立即主动刷新一次
    Future.microtask(() {
      ref.invalidate(connectionManagerProvider);
      ref.invalidate(connectivityCheckProvider);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 从后台切回前台时自动刷新
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(connectionManagerProvider);
      ref.invalidate(connectivityCheckProvider);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(connectivityCheckProvider);
    final manager = ref.read(connectionManagerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('快速连接'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _retryResults.clear();
              _retrying.clear();
              ref.invalidate(connectionManagerProvider);
              ref.invalidate(connectivityCheckProvider);
            },
          ),
        ],
      ),
      body: status.when(
        loading: () => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在检查各服务连接...'),
            ],
          ),
        ),
        error: (err, _) => Center(child: Text('检查失败: $err')),
        data: (allResults) {
          // 合并全量结果和逐项重试结果
          final merged = _mergeResults(allResults);

          final ok = merged.where((r) => r.ok).length;
          final total = merged.length;
          final hasRetries = _retryResults.isNotEmpty;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 汇总
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        ok == total ? Icons.check_circle : Icons.warning_amber,
                        color: ok == total ? Colors.green : Colors.orange,
                        size: 32,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ok == total ? '全部连通' : '$ok/$total 连通',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 16),
                            ),
                            Text(
                              ok == total
                                  ? '所有服务均可正常使用'
                                  : '点击右侧重试按钮单独重试失败的服务',
                              style: const TextStyle(
                                  fontSize: 13, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 逐项结果
              for (final r in merged) ...[
                Card(
                  child: ListTile(
                    leading: Icon(
                      r.ok ? Icons.check_circle : Icons.cancel,
                      color: r.ok ? Colors.green : Colors.red,
                    ),
                    title: Text(r.service),
                    subtitle: r.ok
                        ? Text('${r.elapsed.inMilliseconds}ms',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey))
                        : Text(r.message ?? '未知错误',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.red),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis),
                    trailing: _retrying.contains(r.service)
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : r.ok
                            ? const Icon(Icons.verified,
                                color: Colors.green, size: 20)
                            : IconButton(
                                icon: const Icon(Icons.refresh,
                                    color: Colors.orange),
                                tooltip: '重试',
                                onPressed: () =>
                                    _retryService(manager, r.service),
                              ),
                  ),
                ),
                const SizedBox(height: 4),
              ],

              if (hasRetries)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Center(
                    child: TextButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text('重新检查全部'),
                      onPressed: () {
                        _retryResults.clear();
                        _retrying.clear();
                        ref.invalidate(connectionManagerProvider);
                        ref.invalidate(connectivityCheckProvider);
                      },
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// 合并全量结果与逐项重试结果（重试结果优先）。
  List<ConnectionResult> _mergeResults(List<ConnectionResult> all) {
    final map = {for (final r in all) r.service: r};
    for (final entry in _retryResults.entries) {
      final value = entry.value;
      value.whenData((r) => map[entry.key] = r);
    }
    return all.map((r) => map[r.service] ?? r).toList();
  }

  Future<void> _retryService(ConnectionManager manager, String service) async {
    setState(() => _retrying.add(service));
    try {
      final result = await manager.checkOne(service);
      setState(() {
        _retryResults[service] = AsyncValue.data(result);
        _retrying.remove(service);
      });
    } catch (e) {
      setState(() {
        _retryResults[service] =
            AsyncValue.error(e, StackTrace.current);
        _retrying.remove(service);
      });
    }
  }
}
