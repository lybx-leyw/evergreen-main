/// DataOrchestrator 凭证/数据拉取在 Android 上的关键路径测试。
///
/// 不依赖 Cache（persistentKey 设为 null），走纯内存路径，模拟 Android 上
/// path_provider 不可用 / Cache 未初始化时的拉取行为。
///
/// 覆盖：
///   1. DataType 全字段构造 + equals/hashCode
///   2. 注册 + get（内存路径缓存命中）
///   3. refresh 拉取失败 → 返回 null，状态标记错误
///   4. 未注册类型 → 抛 DataTypeNotRegisteredException
///   5. getByName / refreshByName（Agent Tool 通过字符串名称访问）
///   6. 状态追踪（connected / lastError / freshnessLabel）
///   7. testConnectivity 连通性测试
///   8. 重复注册 → 覆盖旧 fetcher
///   9. 注销 → 状态清除 + 再次访问抛异常
library;

import 'package:evergreen_base/core/data/exceptions.dart';
import 'package:evergreen_base/core/data/orchestrator.dart';
import 'package:evergreen_base/core/data/type.dart';
import 'package:flutter_test/flutter_test.dart';

// ═════════════════════════════════════════════════════════════════════
// 测试用 DataType 定义
// ═════════════════════════════════════════════════════════════════════

const coursesType = DataType<Map<String, dynamic>>(
  name: 'courses',
  category: '教务',
  displayName: '课程数据',
  ttl: Duration(minutes: 10),
  // ⚠️ 不设 persistentKey → 不依赖 Cache → Android safe
);

const gradesType = DataType<List<dynamic>>(
  name: 'grades',
  category: '教务',
  displayName: '成绩数据',
);

const scraperCredentialType = DataType<String>(
  name: 'scraper_credential',
  category: '系统',
  displayName: '爬虫凭证状态',
  ttl: Duration(minutes: 30),
);

void main() {
  late DataOrchestrator orch;

  setUp(() {
    orch = DataOrchestrator();
  });

  tearDown(() {
    orch.stopAutoRefresh();
  });

  // ═════════════════════════════════════════════════════════════════
  // DataType 构造
  // ═════════════════════════════════════════════════════════════════

  group('DataType 构造与相等性', () {
    test('全字段构造', () {
      const t = DataType<int>(
        name: 'my_type',
        category: '测试',
        displayName: '我的类型',
        ttl: Duration(seconds: 30),
        persistentKey: 'my_cache_key',
      );
      expect(t.name, 'my_type');
      expect(t.category, '测试');
      expect(t.displayName, '我的类型');
      expect(t.label, '我的类型'); // label = displayName ?? name
      expect(t.ttl, const Duration(seconds: 30));
      expect(t.persistentKey, 'my_cache_key');
    });

    test('缺省字段 → 合理默认值', () {
      const t = DataType<bool>(name: 'simple');
      expect(t.category, '未分类');
      expect(t.displayName, isNull);
      expect(t.label, 'simple'); // fallback to name
      expect(t.ttl, const Duration(minutes: 5));
      expect(t.persistentKey, isNull);
    });

    test('equals: 同名即相等', () {
      const a = DataType<int>(name: 'x', category: 'A');
      const b = DataType<int>(name: 'x', category: 'B');
      expect(a, equals(b));
    });

    test('hashCode: 同名同 hash', () {
      const a = DataType<int>(name: 'x', category: 'A');
      const b = DataType<int>(name: 'x', category: 'B');
      expect(a.hashCode, b.hashCode);
    });

    test('toString 含名称', () {
      const t = DataType<String>(name: 'my_data');
      expect(t.toString(), contains('my_data'));
    });
  });

  // ═════════════════════════════════════════════════════════════════
  // 注册 + 获取（内存路径，无 Cache）
  // ═════════════════════════════════════════════════════════════════

  group('注册 + get（内存路径，persistentKey=null）', () {
    test('注册后 get 触发拉取并返回数据', () async {
      orch.register(coursesType, () async => {'title': '数学分析', 'credits': 4});

      final result = await orch.get(coursesType);

      expect(result, isNotNull);
      expect(result!['title'], '数学分析');
      expect(result['credits'], 4);
    });

    test('已注册 → isRegistered 返回 true', () {
      orch.register(coursesType, () async => <String, dynamic>{});
      expect(orch.isRegistered(coursesType), isTrue);
    });

    test('get 后同类型再 get → 重新拉取（persistentKey=null 无缓存）', () async {
      int callCount = 0;
      orch.register(coursesType, () async {
        callCount++;
        return {'count': callCount};
      });

      await orch.get(coursesType);
      await orch.get(coursesType);

      expect(callCount, 2, reason: 'persistentKey=null 每次 get 都重新拉取');
    });

    test('批量注册 registerAll → 全部可用', () async {
      final entries = <DataType, Future<dynamic> Function()>{
        coursesType: () async => {'name': 'course'},
        gradesType: () async => [
              {'course': 'A', 'score': 90}
            ],
      };
      orch.registerAll(entries);

      expect(orch.isRegistered(coursesType), isTrue);
      expect(orch.isRegistered(gradesType), isTrue);

      final course = await orch.get(coursesType);
      final grade = await orch.get(gradesType);

      expect((course as Map)['name'], 'course');
      expect((grade as List).length, 1);
    });
  });

  // ═════════════════════════════════════════════════════════════════
  // refresh — 拉取失败路径（Android 上常见：chaquopy 调用失败）
  // ═════════════════════════════════════════════════════════════════

  group('refresh — 失败路径（模拟 Android Chaquopy 调用失败）', () {
    test('refresh 拉取成功 → 返回数据并更新状态', () async {
      orch.register(coursesType, () async => {'status': 'ok'});

      final result = await orch.refresh(coursesType);

      expect(result, isNotNull);
      expect(result!['status'], 'ok');
      final s = orch.status('courses')!;
      expect(s.connected, isTrue);
    });

    test('refresh fetcher 抛异常 → 返回 null + 状态标记错误', () async {
      orch.register(coursesType, () async =>
          throw const DataFetchException('courses', 'Chaquopy 执行失败: timeout'));

      final result = await orch.refresh(coursesType);

      expect(result, isNull,
          reason: '拉取失败应返回 null，不崩');
      final s = orch.status('courses')!;
      expect(s.connected, isFalse);
      expect(s.lastError, isNotNull);
      expect(s.lastError, contains('timeout'));
    });

    test('refresh fetcher 返回 null → connected=false（无效数据）', () async {
      // _fetchAndCache 检查 data is! T：null 不满足类型约束 → 视为无效数据
      orch.register(coursesType, () async => null);

      final result = await orch.refresh(coursesType);

      expect(result, isNull);
      final s = orch.status('courses')!;
      expect(s.connected, isFalse,
          reason: '_fetchAndCache: data==null → 无效数据 → connected=false');
      // T4 起空数据门控区分「源可达但语义空」：lastError 用 kDataEmptyReachableError
      expect(s.lastError, kDataEmptyReachableError);
    });

    test('refresh 前未拉取过 → freshnessLabel 为 "从未"', () {
      orch.register(coursesType, () async => {'x': 1});

      final s = orch.status('courses')!;
      expect(s.freshnessLabel, '从未');
    });

    test('refresh 后 freshnessLabel 变为 "新鲜"', () async {
      orch.register(coursesType, () async => {'x': 1});

      await orch.refresh(coursesType);

      final s = orch.status('courses')!;
      expect(s.freshnessLabel, '新鲜');
    });
  });

  // ═════════════════════════════════════════════════════════════════
  // 未注册类型 → 抛异常
  // ═════════════════════════════════════════════════════════════════

  group('未注册类型 → DataTypeNotRegisteredException', () {
    test('get 未注册类型 → 抛异常', () {
      expect(
        () => orch.get(coursesType),
        throwsA(isA<DataTypeNotRegisteredException>()),
      );
    });

    test('refresh 未注册类型 → 抛异常', () {
      expect(
        () => orch.refresh(coursesType),
        throwsA(isA<DataTypeNotRegisteredException>()),
      );
    });

    test('getByName 未注册 → 抛异常', () {
      expect(
        () => orch.getByName('ghost_type'),
        throwsA(isA<DataTypeNotRegisteredException>()),
      );
    });

    test('异常信息包含类型名', () async {
      try {
        await orch.get(coursesType);
        fail('应抛异常');
      } on DataTypeNotRegisteredException catch (e) {
        expect(e.typeName, 'courses');
        expect(e.toString(), contains('courses'));
      }
    });
  });

  // ═════════════════════════════════════════════════════════════════
  // getByName / refreshByName（Agent Tool 用）
  // ═════════════════════════════════════════════════════════════════

  group('getByName / refreshByName（Agent 通过字符串名访问）', () {
    test('getByName 等价于 get', () async {
      orch.register(coursesType, () async => {'via': 'name'});

      final result = await orch.getByName('courses');
      expect((result as Map)['via'], 'name');
    });

    test('refreshByName 等价于 refresh', () async {
      orch.register(coursesType, () async => {'refreshed': true});

      final result = await orch.refreshByName('courses');
      expect((result as Map)['refreshed'], true);
    });

    test('typeByName 返回正确 DataType', () {
      orch.register(coursesType, () async => {});
      final t = orch.typeByName('courses');
      expect(t, isNotNull);
      expect(t!.name, 'courses');
      expect(t.category, '教务');
    });

    test('typeByName 未注册 → null', () {
      expect(orch.typeByName('nonexistent'), isNull);
    });
  });

  // ═════════════════════════════════════════════════════════════════
  // 连通性测试
  // ═════════════════════════════════════════════════════════════════

  group('连通性测试', () {
    test('testConnectivity fetcher 成功 → true', () async {
      orch.register(coursesType, () async => {'ok': true});

      await orch.testConnectivity('courses');

      expect(orch.status('courses')!.connected, isTrue);
    });

    test('testConnectivity fetcher 抛异常 → false', () async {
      orch.register(
          coursesType, () async => throw Exception('网络不可达'));

      await orch.testConnectivity('courses');

      expect(orch.status('courses')!.connected, isFalse);
      expect(orch.status('courses')!.lastError, contains('网络不可达'));
    });

    test('testConnectivity 未注册 → 静默返回不崩', () async {
      await orch.testConnectivity('ghost');
      expect(orch.status('ghost'), isNull,
          reason: '未注册数据源无状态记录');
    });
  });

  // ═════════════════════════════════════════════════════════════════
  // 重复注册 + 注销
  // ═════════════════════════════════════════════════════════════════

  group('重复注册 + 注销', () {
    test('重复注册 → 覆盖旧 fetcher', () async {
      orch.register(coursesType, () async => {'v': 1});
      orch.register(coursesType, () async => {'v': 2}); // 覆盖

      final result = await orch.get(coursesType);
      expect(result!['v'], 2, reason: '第二次注册覆盖第一次的 fetcher');
    });

    test('注销后 → get 抛异常', () {
      orch.register(coursesType, () async => {});
      orch.unregister(coursesType);

      expect(orch.isRegistered(coursesType), isFalse);
      expect(
        () => orch.get(coursesType),
        throwsA(isA<DataTypeNotRegisteredException>()),
      );
    });

    test('注销后 → status 返回 null', () {
      orch.register(coursesType, () async => {});
      orch.unregister(coursesType);

      expect(orch.status('courses'), isNull);
    });

    test('registeredTypes 列出所有已注册 DataType 名称', () {
      orch.register(coursesType, () async => {});
      orch.register(gradesType, () async => []);

      final names = orch.registeredTypes;
      expect(names, contains('courses'));
      expect(names, contains('grades'));
      expect(names.length, 2);
    });
  });

  // ═════════════════════════════════════════════════════════════════
  // 凭证相关场景（模拟 scraper 凭证检查）
  // ═════════════════════════════════════════════════════════════════

  group('凭证检查数据源（scraper 模式）', () {
    test('凭证状态 fetcher 返回已配置 → connected=true', () async {
      orch.register(scraperCredentialType,
          () async => 'ZJU_USERNAME=***, ZJU_PASSWORD=***');

      final result = await orch.refresh(scraperCredentialType);

      expect(result, isNotNull);
      expect(orch.status('scraper_credential')!.connected, isTrue);
    });

    test('凭证状态 fetcher 抛 "未配置凭证" → connected=false + 错误信息', () async {
      orch.register(scraperCredentialType, () async =>
          throw const DataFetchException('scraper_credential', '未配置凭证: ZJU_USERNAME 或 ZJU_PASSWORD 为空'));

      await orch.refresh(scraperCredentialType);

      final s = orch.status('scraper_credential')!;
      expect(s.connected, isFalse);
      expect(s.lastError, contains('未配置凭证'));
    });
  });
}
