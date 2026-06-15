import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/log.dart';

/// E-card provider — 校园卡余额查询（elife.zju.edu.cn / BlueWare 新中新平台）。
///
/// BlueWare API 不使用 CAS SSO cookie，而是使用 `synjones-auth: bearer <token>`
/// 请求头认证。token 通过 BlueWare 登录页获取，暂未自动化实现。
final ecardBalanceProvider =
    FutureProvider<Map<String, dynamic>?>((ref) async {
  final dio = ref.read(dioClientProvider);

  // BlueWare API 使用 synjones-auth bearer token
  final headers = <String, dynamic>{
    'Referer': 'https://elife.zju.edu.cn/plat-pc/',
    'X-Requested-With': 'XMLHttpRequest',
    'synAccessSource': 'pc',
  };

  try {
    final res = await dio.get(
      'https://elife.zju.edu.cn/berserker-app/ykt/tsm/getCampusCards',
      queryParameters: {'synAccessSource': 'pc'},
      options: Options(
        headers: headers,
        validateStatus: (s) => s != null && s < 500,
        receiveTimeout: const Duration(seconds: 5),
      ),
    );

    if (res.statusCode == 200) {
      final data = res.data;
      if (data is Map && data['data'] is Map) {
        final inner = data['data'] as Map;
        final cards = inner['card'] as List?;
        if (cards != null && cards.isNotEmpty) {
          final card = cards[0] as Map;
          final dbBalance = card['db_balance'];

          return {
            'balance': dbBalance is int ? dbBalance / 100.0 : 0.0,
            'card_name': card['name']?.toString() ?? '',
            'account': card['account']?.toString() ?? '',
          };
        }
      }
    }
  } on DioException catch (e) {
    Log().warn('Ecard fetch failed',
        data: {'status': e.response?.statusCode});
  } catch (e) {
    Log().warn('Ecard unexpected error', error: e);
  }

  return null;
});
