/// data 包 API 规则 & 使用示例。

// ignore_for_file: avoid_print

import 'dart:io' show exit;
import '../data.dart';

// ═══════════════════════════════════════════════════════════════════════════
// 模拟数据源
// ═══════════════════════════════════════════════════════════════════════════

int _callCount = 0;

Future<Map<String, dynamic>> _fetchScores() async {
  _callCount++;
  return {'semester': '2026春', 'gpa': 3.8, 'call': _callCount};
}

Future<List<Map<String, dynamic>>> _fetchNews() async {
  return [
    {'title': '教务通知', 'date': '2026-06-29'},
    {'title': '考试安排', 'date': '2026-07-01'},
  ];
}

// ═══════════════════════════════════════════════════════════════════════════
// 数据类型定义
// ═══════════════════════════════════════════════════════════════════════════
//
// 每种数据定义一个 DataType<T> 常量，name 全局唯一。
// T 是 fetcher 返回的数据类型，get/refresh 的返回值类型与之对应。

const scoresType = DataType<Map<String, dynamic>>(
  name: 'scores',
  category: '教务',
  displayName: '成绩单',
  ttl: Duration(seconds: 5),   // 缓存有效期
  persistentKey: 'scores',      // 持久化键 → 存盘。不设则每次拉取不缓存
);

const newsType = DataType<List<Map<String, dynamic>>>(
  name: 'news',
  category: '资讯',
  displayName: '新闻列表',
  ttl: Duration(minutes: 10),
);

// ═══════════════════════════════════════════════════════════════════════════
Future<void> main() async {
  await Cache.getInstance();
  final orch = DataOrchestrator();

  // ---- 注册 ----
  //
  // orch.register(type, fetcher) 绑定类型和拉取函数。
  // 同一 name 重复 register → 覆盖旧 fetcher，Status 保留。

  orch.register(scoresType, _fetchScores);

  // orch.registerAll({...}) 批量注册。
  orch.registerAll({newsType: _fetchNews});

  // orch.unregister(type) 注销并同时清除缓存。
  const temp = DataType<dynamic>(name: 'temp', category: '');
  orch.register(temp, () async => 'x');
  orch.unregister(temp);

  // ---- 获取 ----
  //
  // orch.get(type)：缓存优先。有缓存就返回（即使已过期），无缓存才调 fetcher。
  // 返回 T?：命中返回数据；fetcher 返回 null/异常时返回 null，旧缓存不动。

  final scores = await orch.get(scoresType);
  print('首次 get: call=${scores?['call']}'); // → 1

  final scores2 = await orch.get(scoresType);
  print('缓存命中: call=${scores2?['call']}'); // → 1 不变

  // 无 persistentKey 的类型不缓存，每次 get 都重新拉取。
  int n = 0;
  const noCache = DataType<Map<String, dynamic>>(name: 'nc', category: '');
  orch.register(noCache, () async => {'v': ++n});
  print('无缓存key 第1次: ${(await orch.get(noCache))?['v']}'); // → 1
  print('无缓存key 第2次: ${(await orch.get(noCache))?['v']}'); // → 2

  // ---- 刷新 ----
  //
  // orch.refresh(type)：忽略缓存，强制调 fetcher。
  // 合法数据覆写缓存，非法（null/类型错）返回 null 不覆写。

  final fresh = await orch.refresh(scoresType);
  print('refresh 后: call=${fresh?['call']}'); // → 2

  // orch.refreshAllStale()：遍历所有 Status，isFresh==false 的逐一 refresh。
  await orch.refreshAllStale();

  // orch.refreshAllStale(types: [...])：仅刷新指定类型中的过期项。
  await orch.refreshAllStale(types: [scoresType]);

  // orch.invalidate(type)：删缓存，下次 get 重新拉取。
  await orch.invalidate(scoresType);

  // ---- 状态可视化 ----
  //
  // register 时自动创建 DataSourceStatus，get/refresh 成功/失败自动更新。

  for (final s in orch.allStatuses) {
    print('${s.category}/${s.displayName}  ${s.freshnessLabel}  ${s.relativeTime}');
  }
  // DataSourceStatus 字段: connected / isFresh / freshnessLabel / relativeTime / lastFetchedAt / lastError

  print('总计 ${orch.totalCount}  已连通 ${orch.connectedCount}  新鲜 ${orch.freshCount}');

  // orch.status(name) 按名查询；statusByCategory(c) 按分类过滤；categories 所有分类名。
  // orch.refreshStatusFromDisk() 从缓存文件恢复 lastFetchedAt（重启后调用）。

  // ---- 连通性测试 ----
  //
  // orch.testConnectivity(name)：调一次 fetcher，成功 connected=true，失败 connected=false。

  await orch.testConnectivity('scores');
  await orch.testAllConnectivity(); // 全测

  // ---- 异常处理 ----
  //
  // 未注册类型 get → DataTypeNotRegisteredException。
  // fetcher 抛异常或返回 null → get/refresh 返回 null，不写缓存，旧数据仍在。

  try {
    const unknown = DataType<dynamic>(name: 'not_registered', category: '');
    await orch.get(unknown);
  } on DataTypeNotRegisteredException catch (e) {
    print('异常: $e');
  }

  // ---- HTTP 管理服务器 ----
  //
  // DataHttpServer 暴露 REST 端点供插件 .exe 查询/刷新/测试连通性。
  // 与 DataOrchestrator 绑定，启动后插件即可通过 HTTP 回调平台。

  final httpServer = DataHttpServer(orch);
  final serverPort = await httpServer.start();
  print('DataHttpServer 启动: port=$serverPort');

  // 可通过 HTTP 访问：GET http://127.0.0.1:$serverPort/data/health 等

  // ---- 远程清单拉取 ----
  //
  // fetchRemoteManifestList(url) 从远程拉取插件清单列表。
  // fetchRemoteManifest(url) 拉取单个清单。网络失败返回空/不抛异常。

  // 示例：从本地文件模拟远程拉取（生产环境用真实 URL）
  final remoteList = await fetchRemoteManifestList('http://127.0.0.1:$serverPort/data/types');
  print('远程清单拉取: ${remoteList.length} 个 (HTTP 端点不返回 manifest 格式，此处仅为示例)');

  // ---- 插件加载 ----
  //
  // scanAndLoadDataSources(dir, orch) 扫描 plugins/*/data/manifest.json，
  // 逐个启动 .exe，自动注册。加载后插件数据与内置模块完全一致。
  // 示例插件：example/plugins/douban/（爬取豆瓣电影 Top250）

  print('\n加载插件...');
  final loaders = await scanAndLoadDataSources(
    pluginsDir: 'example/plugins/',
    orchestrator: orch,
    projectRoot: Directory.current.path,
  );

  for (final l in loaders) {
    print('插件: ${l.manifest.id}  running=${l.isRunning}  port=${l.port}');

    // 插件数据与内置模块一样走 orch.get()
    for (final decl in l.manifest.dataTypes) {
      final type = decl.toDataType();
      final data = await orch.refresh(type);
      print('\n${decl.displayName} (来自 .exe 插件):');
      for (final item in data ?? []) {
        final m = item as Map;
        print('  ${m['rank']}. ${m['title']}  ★${m['rating']}  ${m['quote']}');
      }
    }

    // 用完关闭插件进程，否则程序不会退出
    l.unregisterAll(orch);
    await l.stop();
  }

  // 关闭 HTTP 管理服务器
  await httpServer.stop();

  print('\n===== 完成 =====');
  exit(0);
}
