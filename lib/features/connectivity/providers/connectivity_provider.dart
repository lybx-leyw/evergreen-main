import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/connectivity/connection_manager.dart';
import '../../../core/log.dart';
import '../../../core/network/dio_client.dart';
import '../../auth/providers/auth_provider.dart';
import '../../zdbk/providers/zdbk_provider.dart';

/// ConnectionManager 实例。
///
/// 仅在鉴权状态变化时重建，不做定时自动检查（开销太大）。
final connectionManagerProvider = Provider<ConnectionManager>((ref) {
  final httpClient = ref.read(httpClientProvider);
  final cookieJar = ref.read(cookieJarProvider);
  final auth = ref.read(authProvider);
  ref.watch(authProvider);
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
