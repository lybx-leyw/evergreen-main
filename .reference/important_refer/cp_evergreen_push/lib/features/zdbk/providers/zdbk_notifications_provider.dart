import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/result.dart';
import '../../../core/errors.dart';
import '../../../core/config/app_config.dart';
import '../../../core/models/zdbk_notification.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../core/network/dio_client.dart';
import 'zdbk_provider.dart';

/// ZDBK 通知公告 Provider。
final zdbkNotificationsProvider =
    FutureProvider<Result<List<ZdbkNotification>>>((ref) async {
  final auth = ref.watch(authProvider);
  if (!auth.isLoggedIn || auth.ssoCookie == null) {
    return Err(AppError.configMissing('学号和密码')
      ..recoveryHint = '请先登录统一认证');
  }
  final service = await ref.read(zdbkServiceInstanceProvider.future);
  final httpClient = ref.read(httpClientProvider);
  return service.getNotifications(httpClient, AppConfig.zjuUsername ?? '');
});
