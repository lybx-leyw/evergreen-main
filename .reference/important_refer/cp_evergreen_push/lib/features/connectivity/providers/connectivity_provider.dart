import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/connectivity/connection_manager.dart';
import '../../../core/log.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/storage/database.dart';
import '../../../core/connectivity/data_status_manager.dart';
import '../../auth/providers/auth_provider.dart';
import '../../zdbk/providers/zdbk_provider.dart';

/// ConnectionManager 实例。
///
/// 仅在鉴权状态变化时重建，不做定时自动检查（开销太大）。
final connectionManagerProvider = Provider<ConnectionManager>((ref) {
  final httpClient = ref.read(httpClientProvider);
  final cookieJar = ref.read(cookieJarProvider);
  final auth = ref.watch(authProvider);
  final zdbkService = ref.watch(zdbkServiceInstanceProvider).valueOrNull;
  return ConnectionManager(
    httpClient,
    cookieJar,
    auth,
    () => zdbkService ?? (throw Exception('ZDBK 服务未就绪')),
  );
});

/// 全量连接检查——仅手动刷新时重建。
final connectivityCheckProvider =
    FutureProvider<List<ConnectionResult>>((ref) async {
  final manager = ref.watch(connectionManagerProvider);
  final results = await manager.checkAll();

  // 自动重试失败的服务（最多 1 次）
  final retried = <ConnectionResult>[];
  for (final r in results) {
    if (!r.ok) {
      Log().debug('Connectivity auto-retry: ${r.service}');
      final retryResult = await manager.checkOne(r.service);
      retried.add(retryResult);
    } else {
      retried.add(r);
    }
  }

  return retried;
});

/// 全局数据状态管理器（持久实例，不被 invalidate 重建）。
final dataStatusManagerProvider = FutureProvider<DataStatusManager>((ref) async {
  final db = await WebCacheDatabase.getInstance();
  final manager = DataStatusManager();
  manager.registerDefaults();
  manager.refreshFreshness(db);
  return manager;
});

/// 数据状态刷新计数器 —— UI watch 此 provider 可在刷新后重建。
final dataStatusTickProvider = StateProvider<int>((_) => 0);

/// 刷新单个数据源的状态（供 _refreshDataSource 调用）。
void updateDataStatus(WidgetRef ref, String name, {required bool ok, String? error}) {
  final mgr = ref.read(dataStatusManagerProvider).valueOrNull;
  if (mgr == null) return;
  final src = mgr.source(name);
  if (src == null) return;
  src.connected = ok;
  if (ok) {
    src.lastFetchedAt = DateTime.now();
    src.lastError = null;
  } else {
    src.lastError = error;
  }
  ref.read(dataStatusTickProvider.notifier).state++;
}
