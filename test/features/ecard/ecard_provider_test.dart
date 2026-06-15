import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:evergreen_multi_tools/core/network/dio_client.dart';
import 'package:evergreen_multi_tools/features/ecard/providers/ecard_provider.dart';

import '../../mocks/mock_dio.dart';

void main() {
  late Dio dio;
  late MockDioAdapter adapter;

  setUp(() {
    (dio, adapter) = createMockDio();
  });

  group('ecardBalanceProvider', () {
    test('正常解析余额', () async {
      adapter.stub(
        'https://elife.zju.edu.cn/berserker-app/ykt/tsm/getCampusCards?synAccessSource=pc',
        MockResponse(
          statusCode: 200,
          body: {
            'data': {
              'card': [
                {
                  'name': '校园卡',
                  'db_balance': 12345,
                  'account': '2021000000',
                },
              ],
            },
          },
        ),
      );

      final container = ProviderContainer(overrides: [
        dioClientProvider.overrideWithValue(dio),
      ]);
      addTearDown(container.dispose);
      final result = await container.read(ecardBalanceProvider.future);

      expect(result, isNotNull);
      expect(result!['balance'], 123.45);
      expect(result['card_name'], '校园卡');
      expect(result['account'], '2021000000');
    });

    test('余额为零', () async {
      adapter.stub(
        'https://elife.zju.edu.cn/berserker-app/ykt/tsm/getCampusCards?synAccessSource=pc',
        MockResponse(
          statusCode: 200,
          body: {
            'data': {
              'card': [
                {'name': '校园卡', 'db_balance': 0, 'account': '2021000000'},
              ],
            },
          },
        ),
      );

      final container = ProviderContainer(overrides: [
        dioClientProvider.overrideWithValue(dio),
      ]);
      addTearDown(container.dispose);
      final result = await container.read(ecardBalanceProvider.future);

      expect(result, isNotNull);
      expect(result!['balance'], 0.0);
      expect(result['card_name'], '校园卡');
    });

    test('卡片列表为空 → null', () async {
      adapter.stub(
        'https://elife.zju.edu.cn/berserker-app/ykt/tsm/getCampusCards?synAccessSource=pc',
        MockResponse(
          statusCode: 200,
          body: {'data': {'card': <Map<String, dynamic>>[]}},
        ),
      );

      final container = ProviderContainer(overrides: [
        dioClientProvider.overrideWithValue(dio),
      ]);
      addTearDown(container.dispose);
      final result = await container.read(ecardBalanceProvider.future);

      expect(result, isNull);
    });

    test('缺失 data 字段 → null', () async {
      adapter.stub(
        'https://elife.zju.edu.cn/berserker-app/ykt/tsm/getCampusCards?synAccessSource=pc',
        MockResponse(statusCode: 200, body: {'foo': 'bar'}),
      );

      final container = ProviderContainer(overrides: [
        dioClientProvider.overrideWithValue(dio),
      ]);
      addTearDown(container.dispose);
      final result = await container.read(ecardBalanceProvider.future);

      expect(result, isNull);
    });

    test('db_balance 非 int 时兜底为 0', () async {
      adapter.stub(
        'https://elife.zju.edu.cn/berserker-app/ykt/tsm/getCampusCards?synAccessSource=pc',
        MockResponse(
          statusCode: 200,
          body: {
            'data': {
              'card': [
                {'name': '校园卡', 'db_balance': 'abc', 'account': '2021'},
              ],
            },
          },
        ),
      );

      final container = ProviderContainer(overrides: [
        dioClientProvider.overrideWithValue(dio),
      ]);
      addTearDown(container.dispose);
      final result = await container.read(ecardBalanceProvider.future);

      expect(result, isNotNull);
      expect(result!['balance'], 0.0);
    });

    test('401 → null（不抛异常）', () async {
      adapter.stub(
        'https://elife.zju.edu.cn/berserker-app/ykt/tsm/getCampusCards?synAccessSource=pc',
        MockResponse(
          statusCode: 401,
          body: {'code': 401, 'message': '缺失令牌'},
        ),
      );

      final container = ProviderContainer(overrides: [
        dioClientProvider.overrideWithValue(dio),
      ]);
      addTearDown(container.dispose);
      final result = await container.read(ecardBalanceProvider.future);

      expect(result, isNull);
    });

    test('DioException 网络错误 → null（不抛异常）', () async {
      adapter.stubError(
        'https://elife.zju.edu.cn/berserker-app/ykt/tsm/getCampusCards?synAccessSource=pc',
        DioException(
          requestOptions: RequestOptions(path: ''),
          message: 'Connection timeout',
        ),
      );

      final container = ProviderContainer(overrides: [
        dioClientProvider.overrideWithValue(dio),
      ]);
      addTearDown(container.dispose);
      final result = await container.read(ecardBalanceProvider.future);

      expect(result, isNull);
    });

    test('请求发出（不含认证头，因 BlueWare token 需额外获取）', () async {
      adapter.stub(
        'https://elife.zju.edu.cn/berserker-app/ykt/tsm/getCampusCards?synAccessSource=pc',
        MockResponse(
          statusCode: 200,
          body: {
            'data': {
              'card': [
                {'name': '校园卡', 'db_balance': 100, 'account': '2021'},
              ],
            },
          },
        ),
      );

      final container = ProviderContainer(overrides: [
        dioClientProvider.overrideWithValue(dio),
      ]);
      addTearDown(container.dispose);
      await container.read(ecardBalanceProvider.future);

      expect(adapter.wasRequested(
        'https://elife.zju.edu.cn/berserker-app/ykt/tsm/getCampusCards?synAccessSource=pc',
      ), isTrue);
    });
  });
}
